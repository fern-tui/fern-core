// SPDX-License-Identifier: MIT

// render.zig - Diff renderer: frame string -> minimal terminal escape sequences.
//
// Imports: std, fern_ansi.
// Named "cursed renderer". Algorithm is line-level diff --
// simple but fast enough for 60 fps on any modern terminal.
//
// Platform: Linux + macOS only.

const std = @import("std");
const ansi = @import("fern_ansi");

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

pub const Renderer = struct {

    // ---- fields (private) -------------------------------------------------

    // Writer to the terminal output.  Owned by caller; Renderer never closes it.
    // Must be a pointer: std.Io.Writer vtable functions use @fieldParentPtr("writer", w)
    // to recover the owning struct (e.g. Allocating).  A value copy would make
    // that arithmetic point into Renderer instead — instant segfault.
    writer: *std.Io.Writer,

    // Terminal dimensions.
    cols: u16,
    rows: u16,

    // Lines from the previous rendered frame.  Owned by Renderer.
    prev_lines: std.ArrayList([]u8),

    // Allocator for prev_lines and their contents.
    alloc: std.mem.Allocator,

    // Whether synchronized output mode is active.
    sync_mode: bool,

    // Current cursor row (0-based) as last left by render().
    cursor_row: u16,

    // True on the very first render -- full repaint needed.
    first_render: bool,

    // ---- lifecycle --------------------------------------------------------

    /// Initialize.  writer must outlive the Renderer.
    pub fn init(
        allocator: std.mem.Allocator,
        writer: *std.Io.Writer,
        cols: u16,
        rows: u16,
    ) Renderer {
        return .{
            .writer = writer,
            .cols = cols,
            .rows = rows,
            .prev_lines = .empty,
            .alloc = allocator,
            .sync_mode = false,
            .cursor_row = 0,
            .first_render = true,
        };
    }

    /// Free prev_lines and all owned line strings.
    pub fn deinit(self: *Renderer) void {
        for (self.prev_lines.items) |line| self.alloc.free(line);
        self.prev_lines.deinit(self.alloc);
    }

    // ---- control ----------------------------------------------------------

    /// Update terminal dimensions.  Called on resize events.
    pub fn resize(self: *Renderer, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
    }

    /// Enable or disable synchronized output mode (terminal mode 2026).
    pub fn setSyncMode(self: *Renderer, enabled: bool) void {
        self.sync_mode = enabled;
    }

    /// Force a full repaint on the next render() call.
    /// Use after alt-screen enter/leave or terminal restore.
    pub fn reset(self: *Renderer) void {
        self.first_render = true;
    }

    // ---- rendering --------------------------------------------------------

    /// Render frame to the terminal using line-level diffing.
    /// frame is an ANSI-styled string produced by view().
    /// Caller owns frame; Renderer does not free it.
    pub fn render(self: *Renderer, frame: []const u8) error{OutOfMemory}!void {
        // Accumulate all output in a heap buffer, then flush once.
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);

        if (self.sync_mode) {
            // BSU: DEC private mode 2026 -- synchronized output begin.
            try out.appendSlice(self.alloc, "\x1B[?2026h");
        }

        const new_lines = try ansi.str.splitLines(frame, self.alloc);
        defer self.alloc.free(new_lines);

        if (self.first_render) {
            try fullRepaint(&out, self.alloc, new_lines);
            self.cursor_row = @intCast(new_lines.len -| 1);
            self.first_render = false;
        } else {
            try diffRepaint(self, &out, new_lines);
        }

        if (self.sync_mode) {
            // ESU: synchronized output end.
            try out.appendSlice(self.alloc, "\x1B[?2026l");
        }

        try updatePrevLines(self, new_lines);

        // Flush everything to the terminal in one write.
        self.writer.writeAll(out.items) catch {};
    }

    /// Move cursor above the current frame for inline (non-altscreen) rendering.
    /// Emits cursor-up sequences to return to the top of the rendered area.
    /// Called by run() before each render when not in alt-screen mode.
    pub fn moveToTop(self: *Renderer) error{OutOfMemory}!void {
        if (self.cursor_row == 0) return;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);
        var buf: [16]u8 = undefined;
        // ESC[<n>A moves cursor up n rows.
        const seq = std.fmt.bufPrint(&buf, "\x1B[{d}A", .{self.cursor_row}) catch return;
        try out.appendSlice(self.alloc, seq);
        self.cursor_row = 0;
        self.writer.writeAll(out.items) catch {};
    }
};

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Write every line in full (first render path).
fn fullRepaint(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    lines: [][]const u8,
) error{OutOfMemory}!void {
    for (lines, 0..) |line, i| {
        try out.appendSlice(allocator, line);
        if (i < lines.len - 1) try out.append(allocator, '\n');
    }
}

/// Write only changed lines (subsequent render path).
fn diffRepaint(
    self: *Renderer,
    out: *std.ArrayList(u8),
    new_lines: [][]const u8,
) error{OutOfMemory}!void {
    for (new_lines, 0..) |new_line, row_usize| {
        const row: u16 = @intCast(row_usize);
        const prev_line: []const u8 = if (row < self.prev_lines.items.len)
            self.prev_lines.items[row]
        else
            "";

        if (std.mem.eql(u8, new_line, prev_line)) continue;

        try moveCursorToRow(out, self.alloc, self.cursor_row, row);
        self.cursor_row = row;

        try out.append(self.alloc, '\r');
        // ESC[K -- erase to end of line.
        try out.appendSlice(self.alloc, "\x1B[K");
        try out.appendSlice(self.alloc, new_line);
    }

    // Erase lines that existed in prev frame but not in new frame.
    if (self.prev_lines.items.len > new_lines.len) {
        const erase_from: u16 = @intCast(new_lines.len);
        try moveCursorToRow(out, self.alloc, self.cursor_row, erase_from);
        // ESC[0J -- erase to end of screen.
        try out.appendSlice(self.alloc, "\x1B[0J");
        self.cursor_row = erase_from;
    }

    // Leave cursor at the start of the last rendered line.
    if (new_lines.len > 0) {
        const final_row: u16 = @intCast(new_lines.len -| 1);
        try moveCursorToRow(out, self.alloc, self.cursor_row, final_row);
        self.cursor_row = final_row;
    }
}

/// Emit the minimum bytes to move cursor from `from` to `to` row (0-based).
fn moveCursorToRow(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    from: u16,
    to: u16,
) error{OutOfMemory}!void {
    if (from == to) return;

    if (to == from + 1) {
        // One row down -- a bare newline is the shortest encoding.
        try out.append(allocator, '\n');
        return;
    }

    // CSI row ; col H  (1-based rows, column always 1).
    var buf: [16]u8 = undefined;
    // to+1 converts 0-based internal row to 1-based terminal row.
    const seq = std.fmt.bufPrint(&buf, "\x1B[{d};1H", .{to + 1}) catch return;
    try out.appendSlice(allocator, seq);
}

/// Replace prev_lines cache with duplicates of new_lines.
fn updatePrevLines(self: *Renderer, new_lines: [][]const u8) error{OutOfMemory}!void {
    // Free all existing owned strings.
    for (self.prev_lines.items) |line| self.alloc.free(line);
    self.prev_lines.clearRetainingCapacity();

    for (new_lines) |line| {
        const owned = try self.alloc.dupe(u8, line);
        try self.prev_lines.append(self.alloc, owned);
    }
}

// ---------------------------------------------------------------------------
// Tests (no real terminal required -- fake writer backed by Allocating)
// ---------------------------------------------------------------------------

test "Renderer first render writes all lines" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    const written = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line3") != null);
}

test "Renderer second render writes only changed lines" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    // Switch to a fresh writer so we only see the second render's output.
    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    r.writer = &aw2.writer;
    try r.render("line1\nLINE2\nline3");

    const written2 = aw2.writer.buffered();
    // Changed line must appear.
    try std.testing.expect(std.mem.indexOf(u8, written2, "LINE2") != null);
    // Erase-line sequence must appear.
    try std.testing.expect(std.mem.indexOf(u8, written2, "\x1B[K") != null);
    // Unchanged lines must NOT appear.
    try std.testing.expect(std.mem.indexOf(u8, written2, "line1") == null);
    try std.testing.expect(std.mem.indexOf(u8, written2, "line3") == null);
}

test "Renderer erases extra lines when frame shrinks" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("a\nb\nc");

    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    r.writer = &aw2.writer;
    try r.render("a\nb");

    const written2 = aw2.writer.buffered();
    // ESC[0J must appear to erase trailing line.
    try std.testing.expect(std.mem.indexOf(u8, written2, "\x1B[0J") != null);
}

test "Renderer reset forces full repaint on next render" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("a\nb");

    r.reset();
    try std.testing.expect(r.first_render == true);

    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    r.writer = &aw2.writer;
    // No change in content, but first_render forces full repaint.
    try r.render("a\nb");

    const written2 = aw2.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written2, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, written2, "b") != null);
}

test "Renderer sync_mode wraps output in BSU and ESU" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    r.setSyncMode(true);
    try r.render("hello");

    const written = aw.writer.buffered();
    // BSU marker.
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[?2026h") != null);
    // ESU marker.
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[?2026l") != null);
}

test "Renderer resize updates cols and rows" {
    const allocator = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    r.resize(120, 40);
    try std.testing.expectEqual(@as(u16, 120), r.cols);
    try std.testing.expectEqual(@as(u16, 40), r.rows);
}

test "moveCursorToRow from same row emits nothing" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try moveCursorToRow(&out, allocator, 5, 5);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "moveCursorToRow to adjacent row emits newline" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try moveCursorToRow(&out, allocator, 3, 4);
    try std.testing.expectEqualStrings("\n", out.items);
}

test "moveCursorToRow to distant row emits CSI position" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    // Moving from row 0 to row 5 (0-based) -> ESC[6;1H (1-based).
    try moveCursorToRow(&out, allocator, 0, 5);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "6;1H") != null);
}
