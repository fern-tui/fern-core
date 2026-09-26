// SPDX-License-Identifier: MIT
//
// Diff renderer: turns raw frame strings into optimized terminal escape sequences.
// Supports both full-screen (alternate screen) and inline CLI rendering.

const std = @import("std");
const ansi = @import("fern_ansi");

pub const Renderer = struct {
    // Terminal writer. Unowned; we never close it.
    writer: *std.Io.Writer,

    // Terminal dimensions.
    cols: u16,
    rows: u16,

    // Contiguous buffer holding the previous frame's raw contents.
    prev_frame_buf: ?[]u8,

    // Lines from the previous rendered frame (slices pointing into prev_frame_buf).
    prev_lines: std.ArrayList([]const u8),

    // Allocator for frame buffers and line caches.
    alloc: std.mem.Allocator,

    // Whether synchronized output mode is active (DEC mode 2026).
    sync_mode: bool,

    // Whether the renderer is operating inside the alternate screen buffer.
    alt_screen: bool,

    // Current cursor row (0-based) relative to the top of our render region.
    cursor_row: u16,

    // True on the very first render or after an explicit reset() call.
    first_render: bool,

    /// Initialize. writer must outlive the Renderer.
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
            .prev_frame_buf = null,
            .prev_lines = .empty,
            .alloc = allocator,
            .sync_mode = false,
            .alt_screen = false,
            .cursor_row = 0,
            .first_render = true,
        };
    }

    /// Free previous frame buffers and line cache.
    pub fn deinit(self: *Renderer) void {
        if (self.prev_frame_buf) |buf| self.alloc.free(buf);
        self.prev_lines.deinit(self.alloc);
    }

    /// Update terminal dimensions. Called on resize events.
    pub fn resize(self: *Renderer, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
        self.reset();
    }

    /// Set whether rendering in the alternate screen buffer.
    pub fn setAltScreen(self: *Renderer, enabled: bool) void {
        self.alt_screen = enabled;
        self.reset();
    }

    /// Enable or disable synchronized output mode (DEC private mode 2026).
    pub fn setSyncMode(self: *Renderer, enabled: bool) void {
        self.sync_mode = enabled;
    }

    /// Force a full repaint on the next render() call.
    pub fn reset(self: *Renderer) void {
        self.first_render = true;
    }

    /// Render frame to the terminal using line-level diffing.
    /// frame is an ANSI-styled string produced by view().
    pub fn render(self: *Renderer, frame: []const u8) error{OutOfMemory}!void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);

        // Hide cursor during paint to prevent cursor flickering
        try out.appendSlice(self.alloc, "\x1B[?25l");

        if (self.sync_mode) {
            // DEC private mode 2026: Synchronized output begin
            try out.appendSlice(self.alloc, "\x1B[?2026h");
        }

        const new_lines = try ansi.str.splitLines(frame, self.alloc);
        defer self.alloc.free(new_lines);

        if (self.first_render) {
            if (self.alt_screen) {
                // Home the cursor in alternate screen
                try out.appendSlice(self.alloc, "\x1B[H");
            }
            try fullRepaint(&out, self.alloc, new_lines);
            self.cursor_row = @intCast(new_lines.len -| 1);
            self.first_render = false;
        } else {
            try diffRepaint(self, &out, new_lines);
        }

        if (self.sync_mode) {
            // Synchronized output end
            try out.appendSlice(self.alloc, "\x1B[?2026l");
        }

        // Restore cursor visibility
        try out.appendSlice(self.alloc, "\x1B[?25h");

        try self.cacheFrame(frame, new_lines);

        // Flush frame in a single I/O write
        self.writer.writeAll(out.items) catch {};
    }

    /// Return cursor to the top of the rendered block in inline mode.
    pub fn moveToTop(self: *Renderer) error{OutOfMemory}!void {
        if (self.cursor_row == 0) return;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);

        var buf: [16]u8 = undefined;
        const seq = std.fmt.bufPrint(&buf, "\x1B[{d}A\r", .{self.cursor_row}) catch return;
        try out.appendSlice(self.alloc, seq);
        self.cursor_row = 0;
        self.writer.writeAll(out.items) catch {};
    }

    /// Stores the frame contents in one single heap buffer rather than N line allocations.
    fn cacheFrame(self: *Renderer, frame: []const u8, new_lines: [][]const u8) error{OutOfMemory}!void {
        if (self.prev_frame_buf) |buf| self.alloc.free(buf);

        const frame_copy = try self.alloc.dupe(u8, frame);
        self.prev_frame_buf = frame_copy;

        self.prev_lines.clearRetainingCapacity();

        // Re-slice prev_lines directly into frame_copy with zero string copies
        var offset: usize = 0;
        for (new_lines) |line| {
            const start = offset;
            const end = start + line.len;
            try self.prev_lines.append(self.alloc, frame_copy[start..end]);
            offset = end + 1; // skip delimiter
        }
    }
};

// Private helpers
/// Write every line in full (raw mode requires \r\n to prevent staircasing).
fn fullRepaint(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    lines: [][]const u8,
) error{OutOfMemory}!void {
    for (lines, 0..) |line, i| {
        try out.appendSlice(allocator, line);
        if (i < lines.len - 1) {
            try out.appendSlice(allocator, "\r\n");
        }
    }
}

/// Write only changed lines.
fn diffRepaint(
    self: *Renderer,
    out: *std.ArrayList(u8),
    new_lines: [][]const u8,
) error{OutOfMemory}!void {
    for (new_lines, 0..) |new_line, row_usize| {
        const row: u16 = @intCast(row_usize);
        const prev_line = if (row < self.prev_lines.items.len)
            self.prev_lines.items[row]
        else
            "";

        if (std.mem.eql(u8, new_line, prev_line)) continue;

        try moveCursor(self, out, self.cursor_row, row);
        self.cursor_row = row;

        // \r to col 0, ESC[K to erase to end of line
        try out.appendSlice(self.alloc, "\r\x1B[K");
        try out.appendSlice(self.alloc, new_line);
    }

    // Erase lines that existed in the previous frame if the new frame is shorter
    if (self.prev_lines.items.len > new_lines.len) {
        const erase_from: u16 = @intCast(new_lines.len);
        try moveCursor(self, out, self.cursor_row, erase_from);
        try out.appendSlice(self.alloc, "\r\x1B[0J");
        self.cursor_row = erase_from;
    }

    // Leave cursor at the last rendered line
    if (new_lines.len > 0) {
        const final_row: u16 = @intCast(new_lines.len -| 1);
        try moveCursor(self, out, self.cursor_row, final_row);
        self.cursor_row = final_row;
    }
}

/// Move cursor from `from` row to `to` row.
/// Uses absolute coordinates in alt-screen mode, relative movements in inline mode.
fn moveCursor(
    self: *const Renderer,
    out: *std.ArrayList(u8),
    from: u16,
    to: u16,
) error{OutOfMemory}!void {
    if (from == to) return;

    var buf: [16]u8 = undefined;

    if (self.alt_screen) {
        // Absolute positioning in full-screen alt buffer
        const seq = std.fmt.bufPrint(&buf, "\x1B[{d};1H", .{to + 1}) catch return;
        try out.appendSlice(self.alloc, seq);
    } else {
        // Relative movement for inline mode (never touches lines above the app)
        if (to > from) {
            const diff = to - from;
            const seq = std.fmt.bufPrint(&buf, "\x1B[{d}B\r", .{diff}) catch return;
            try out.appendSlice(self.alloc, seq);
        } else {
            const diff = from - to;
            const seq = std.fmt.bufPrint(&buf, "\x1B[{d}A\r", .{diff}) catch return;
            try out.appendSlice(self.alloc, seq);
        }
    }
}

// Headless Tests
test "Renderer first render writes all lines with CRLF" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    const written = aw.writer.buffered();
    // Inline mode (default) must NOT home the cursor to the top of screen
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[H") == null);
    // Must preserve line content
    try std.testing.expect(std.mem.indexOf(u8, written, "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line3") != null);
    // Must contain CRLF to prevent staircase in raw mode
    try std.testing.expect(std.mem.indexOf(u8, written, "\r\n") != null);
}

test "Renderer first render in alt_screen homes cursor" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();
    r.setAltScreen(true);

    try r.render("line1\nline2\nline3");

    const written = aw.writer.buffered();
    // Must home cursor when alternate screen is active
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[H") != null);
}

test "Renderer second render writes only changed lines" {
    const allocator = std.testing.allocator;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    // Fresh writer for second render frame
    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    r.writer = &aw2.writer;
    try r.render("line1\nLINE2\nline3");

    const written2 = aw2.writer.buffered();
    // Changed line must appear
    try std.testing.expect(std.mem.indexOf(u8, written2, "LINE2") != null);
    // Erase-line sequence must appear
    try std.testing.expect(std.mem.indexOf(u8, written2, "\x1B[K") != null);
    // Unchanged lines must NOT appear in output buffer
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
    // ESC[0J must appear to erase obsolete trailing lines
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
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[?2026h") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[?2026l") != null);
}

test "moveCursor in alt_screen emits CSI position" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();
    r.alt_screen = true;

    // Moving from row 0 to row 5 (0-based) -> ESC[6;1H (1-based)
    try moveCursor(&r, &out, 0, 5);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[6;1H") != null);
}

test "moveCursor in inline mode emits relative CUU/CUD" {
    const allocator = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();
    r.alt_screen = false;

    // Moving down 3 rows in inline mode -> ESC[3B\r
    try moveCursor(&r, &out, 2, 5);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[3B\r") != null);

    out.clearRetainingCapacity();

    // Moving up 2 rows in inline mode -> ESC[2A\r
    try moveCursor(&r, &out, 5, 3);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[2A\r") != null);
}
