// SPDX-License-Identifier: MIT

const std = @import("std");
const ansi = @import("fern_ansi");

pub const Renderer = struct {
    writer: *std.Io.Writer,
    cols: u16,
    rows: u16,
    prev_frame_buf: ?[]u8,
    prev_lines: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    sync_mode: bool,
    alt_screen: bool,
    cursor_hidden: bool,
    cursor_row: u16,
    first_render: bool,

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
            .cursor_hidden = false,
            .cursor_row = 0,
            .first_render = true,
        };
    }

    pub fn deinit(self: *Renderer) void {
        if (self.prev_frame_buf) |buf| self.alloc.free(buf);
        self.prev_lines.deinit(self.alloc);
    }

    pub fn resize(self: *Renderer, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
        self.reset();
    }

    pub fn setAltScreen(self: *Renderer, enabled: bool) void {
        self.alt_screen = enabled;
        self.reset();
    }

    pub fn setCursorHidden(self: *Renderer, hidden: bool) void {
        self.cursor_hidden = hidden;
    }

    pub fn setSyncMode(self: *Renderer, enabled: bool) void {
        self.sync_mode = enabled;
    }

    pub fn reset(self: *Renderer) void {
        self.first_render = true;
    }

    pub fn render(self: *Renderer, frame: []const u8) error{OutOfMemory}!void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);

        if (!self.cursor_hidden) {
            try out.appendSlice(self.alloc, "\x1B[?25l");
        }

        if (self.sync_mode) {
            try out.appendSlice(self.alloc, "\x1B[?2026h");
        }

        const new_lines = try ansi.str.splitLines(frame, self.alloc);
        defer self.alloc.free(new_lines);

        if (self.first_render) {
            if (self.alt_screen) {
                try out.appendSlice(self.alloc, "\x1B[H");
            }
            try fullRepaint(&out, self.alloc, new_lines);
            self.cursor_row = @intCast(new_lines.len -| 1);
            self.first_render = false;
        } else {
            try diffRepaint(self, &out, new_lines);
        }

        if (self.sync_mode) {
            try out.appendSlice(self.alloc, "\x1B[?2026l");
        }

        if (!self.cursor_hidden) {
            try out.appendSlice(self.alloc, "\x1B[?25h");
        }

        try self.cacheFrame(frame, new_lines);
        self.writer.writeAll(out.items) catch {};
    }

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

    fn cacheFrame(self: *Renderer, frame: []const u8, new_lines: [][]const u8) error{OutOfMemory}!void {
        if (self.prev_frame_buf) |buf| self.alloc.free(buf);

        const frame_copy = try self.alloc.dupe(u8, frame);
        self.prev_frame_buf = frame_copy;
        self.prev_lines.clearRetainingCapacity();

        var offset: usize = 0;
        for (new_lines) |line| {
            const start = offset;
            const end = start + line.len;
            try self.prev_lines.append(self.alloc, frame_copy[start..end]);
            offset = end + 1;
        }
    }
};

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

        try out.appendSlice(self.alloc, "\r\x1B[K");
        try out.appendSlice(self.alloc, new_line);
    }

    if (self.prev_lines.items.len > new_lines.len) {
        const erase_from: u16 = @intCast(new_lines.len);
        try moveCursor(self, out, self.cursor_row, erase_from);
        try out.appendSlice(self.alloc, "\r\x1B[0J");
        self.cursor_row = erase_from;
    }

    if (new_lines.len > 0) {
        const final_row: u16 = @intCast(new_lines.len -| 1);
        try moveCursor(self, out, self.cursor_row, final_row);
        self.cursor_row = final_row;
    }
}

fn moveCursor(
    self: *const Renderer,
    out: *std.ArrayList(u8),
    from: u16,
    to: u16,
) error{OutOfMemory}!void {
    if (from == to) return;

    var buf: [16]u8 = undefined;

    if (self.alt_screen) {
        const seq = std.fmt.bufPrint(&buf, "\x1B[{d};1H", .{to + 1}) catch return;
        try out.appendSlice(self.alloc, seq);
    } else {
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

test "Renderer first render writes all lines with CRLF" {
    const allocator = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    const written = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[H") == null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "line3") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[H") != null);
}

test "Renderer second render writes only changed lines" {
    const allocator = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();

    try r.render("line1\nline2\nline3");

    var aw2: std.Io.Writer.Allocating = .init(allocator);
    defer aw2.deinit();
    r.writer = &aw2.writer;
    try r.render("line1\nLINE2\nline3");

    const written2 = aw2.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written2, "LINE2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written2, "\x1B[K") != null);
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

test "Renderer with cursor_hidden true does not restore cursor visibility" {
    const allocator = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var r = Renderer.init(allocator, &aw.writer, 80, 24);
    defer r.deinit();
    r.setCursorHidden(true);

    try r.render("hello");

    const written = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1B[?25h") == null);
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

    try moveCursor(&r, &out, 2, 5);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[3B\r") != null);

    out.clearRetainingCapacity();

    try moveCursor(&r, &out, 5, 3);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\x1B[2A\r") != null);
}
