const std = @import("std");
const ansi = @import("fern_ansi");
const cell_mod = @import("cell.zig");
const draw = @import("draw.zig");

pub const Cell = cell_mod.Cell;

pub const BoxChars = struct {
    tl: u21,
    tr: u21,
    bl: u21,
    br: u21,
    h: u21,
    v: u21,
};

pub const box = struct {
    pub const LIGHT: BoxChars = .{ .tl = '┌', .tr = '┐', .bl = '└', .br = '┘', .h = '─', .v = '│' };
    pub const HEAVY: BoxChars = .{ .tl = '┏', .tr = '┓', .bl = '┗', .br = '┛', .h = '━', .v = '┃' };
    pub const ROUNDED: BoxChars = .{ .tl = '╭', .tr = '╮', .bl = '╰', .br = '╯', .h = '─', .v = '│' };
    pub const DOUBLE: BoxChars = .{ .tl = '╔', .tr = '╗', .bl = '╚', .br = '╝', .h = '═', .v = '║' };
    pub const ASCII: BoxChars = .{ .tl = '+', .tr = '+', .bl = '+', .br = '+', .h = '-', .v = '|' };
};

pub const Canvas = struct {
    cells: []Cell,
    cols: u16,
    rows: u16,
    profile: ansi.ColorProfile,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, cols: u16, rows: u16, profile: ansi.ColorProfile) !Canvas {
        const cells = try alloc.alloc(Cell, @as(usize, cols) * @as(usize, rows));
        @memset(cells, Cell.BLANK);
        return .{
            .cells = cells,
            .cols = cols,
            .rows = rows,
            .profile = profile,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.alloc.free(self.cells);
        self.* = undefined;
    }

    pub fn resize(self: *Canvas, cols: u16, rows: u16) !void {
        const new_cells = try self.alloc.alloc(Cell, @as(usize, cols) * @as(usize, rows));
        @memset(new_cells, Cell.BLANK);
        self.alloc.free(self.cells);
        self.cells = new_cells;
        self.cols = cols;
        self.rows = rows;
    }

    pub fn clear(self: *Canvas, bg: ansi.Color) void {
        @memset(self.cells, Cell{ .bg = bg });
    }

    pub fn setCell(self: *Canvas, x: i32, y: i32, cell: Cell) void {
        draw.setCell(self.cells, self.cols, self.rows, x, y, cell);
    }

    pub fn getCell(self: *const Canvas, x: u16, y: u16) Cell {
        if (x >= self.cols or y >= self.rows) return Cell.BLANK;
        return self.cells[@as(usize, y) * self.cols + x];
    }

    pub fn drawChar(self: *Canvas, x: i32, y: i32, char: u21, fg: ansi.Color, bg: ansi.Color) void {
        draw.setCell(self.cells, self.cols, self.rows, x, y, .{ .char = char, .fg = fg, .bg = bg });
    }

    pub fn drawLine(self: *Canvas, x0: i32, y0: i32, x1: i32, y1: i32, char: u21, fg: ansi.Color) void {
        draw.line(self.cells, self.cols, self.rows, x0, y0, x1, y1, char, fg);
    }

    pub fn drawHLine(self: *Canvas, x: i32, y: i32, len: i32, char: u21, fg: ansi.Color, bg: ansi.Color) void {
        draw.hline(self.cells, self.cols, self.rows, x, y, len, .{ .char = char, .fg = fg, .bg = bg });
    }

    pub fn drawVLine(self: *Canvas, x: i32, y: i32, len: i32, char: u21, fg: ansi.Color, bg: ansi.Color) void {
        draw.vline(self.cells, self.cols, self.rows, x, y, len, .{ .char = char, .fg = fg, .bg = bg });
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, fill: Cell) void {
        draw.rect(self.cells, self.cols, self.rows, x, y, w, h, fill);
    }

    pub fn drawRectLines(self: *Canvas, x: i32, y: i32, w: i32, h: i32, chars: BoxChars, fg: ansi.Color) void {
        if (w <= 0 or h <= 0) return;

        draw.setCell(self.cells, self.cols, self.rows, x, y, .{ .char = chars.tl, .fg = fg });
        draw.setCell(self.cells, self.cols, self.rows, x + w - 1, y, .{ .char = chars.tr, .fg = fg });
        draw.setCell(self.cells, self.cols, self.rows, x, y + h - 1, .{ .char = chars.bl, .fg = fg });
        draw.setCell(self.cells, self.cols, self.rows, x + w - 1, y + h - 1, .{ .char = chars.br, .fg = fg });

        if (w > 2) {
            var xi: i32 = x + 1;
            while (xi < x + w - 1) : (xi += 1) {
                draw.setCell(self.cells, self.cols, self.rows, xi, y, .{ .char = chars.h, .fg = fg });
                draw.setCell(self.cells, self.cols, self.rows, xi, y + h - 1, .{ .char = chars.h, .fg = fg });
            }
        }

        if (h > 2) {
            var yi: i32 = y + 1;
            while (yi < y + h - 1) : (yi += 1) {
                draw.setCell(self.cells, self.cols, self.rows, x, yi, .{ .char = chars.v, .fg = fg });
                draw.setCell(self.cells, self.cols, self.rows, x + w - 1, yi, .{ .char = chars.v, .fg = fg });
            }
        }
    }

    pub fn drawCircle(self: *Canvas, cx: i32, cy: i32, r: i32, fill: Cell) void {
        draw.ellipse(self.cells, self.cols, self.rows, cx, cy, r * 2, r, fill);
    }

    pub fn drawCircleLines(self: *Canvas, cx: i32, cy: i32, r: i32, char: u21, fg: ansi.Color) void {
        draw.ellipseLines(self.cells, self.cols, self.rows, cx, cy, r * 2, r, char, fg);
    }

    pub fn drawEllipse(self: *Canvas, cx: i32, cy: i32, rx: i32, ry: i32, fill: Cell) void {
        draw.ellipse(self.cells, self.cols, self.rows, cx, cy, rx, ry, fill);
    }

    pub fn drawEllipseLines(self: *Canvas, cx: i32, cy: i32, rx: i32, ry: i32, char: u21, fg: ansi.Color) void {
        draw.ellipseLines(self.cells, self.cols, self.rows, cx, cy, rx, ry, char, fg);
    }

    pub fn drawText(self: *Canvas, x: i32, y: i32, text: []const u8, fg: ansi.Color, bg: ansi.Color) void {
        if (y < 0 or y >= @as(i32, self.rows)) return;
        var col: i32 = x;
        var i: usize = 0;
        while (i < text.len) {
            if (col >= @as(i32, self.cols)) break;
            const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
                i += 1;
                continue;
            };
            if (i + cp_len > text.len) break;
            const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
                i += cp_len;
                continue;
            };
            const w: i32 = @intCast(ansi.cpWidth(cp));
            if (col >= 0) {
                draw.setCell(self.cells, self.cols, self.rows, col, y, .{ .char = cp, .fg = fg, .bg = bg });
                if (w == 2) {
                    draw.setCell(self.cells, self.cols, self.rows, col + 1, y, .{ .char = ' ', .fg = fg, .bg = bg });
                }
            }
            col += w;
            i += cp_len;
        }
    }

    pub fn measureText(_: *const Canvas, text: []const u8) u16 {
        const w = ansi.strWidth(text);
        return if (w > 0xFFFF) 0xFFFF else @intCast(w);
    }

    pub fn blit(self: *Canvas, dst_x: i32, dst_y: i32, src: *const Canvas) void {
        var sy: i32 = 0;
        while (sy < @as(i32, src.rows)) : (sy += 1) {
            const dy = dst_y + sy;
            if (dy < 0 or dy >= @as(i32, self.rows)) continue;
            var sx: i32 = 0;
            while (sx < @as(i32, src.cols)) : (sx += 1) {
                const dx = dst_x + sx;
                if (dx < 0 or dx >= @as(i32, self.cols)) continue;
                const src_cell = src.cells[@as(usize, @intCast(sy)) * src.cols + @as(usize, @intCast(sx))];
                self.cells[@as(usize, @intCast(dy)) * self.cols + @as(usize, @intCast(dx))] = src_cell;
            }
        }
    }

    pub fn render(self: *const Canvas, alloc: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(alloc);

        var utf8_buf: [4]u8 = undefined;

        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            var cur = ansi.Attrs{};

            var col: u16 = 0;
            while (col < self.cols) : (col += 1) {
                const cell = self.cells[@as(usize, row) * self.cols + col];

                const fg_dg = cell.fg.downgrade(self.profile);
                const bg_dg = cell.bg.downgrade(self.profile);
                const next_dg = ansi.Attrs{ .fg = fg_dg, .bg = bg_dg, .bold = cell.bold };

                if (!next_dg.eql(cur)) {
                    const next_raw = ansi.Attrs{ .fg = cell.fg, .bg = cell.bg, .bold = cell.bold };
                    var aw: std.Io.Writer.Allocating = .init(alloc);
                    defer aw.deinit();
                    try ansi.sgr.diff(&aw.writer, cur, next_raw, self.profile);
                    const seq = aw.writer.buffered();
                    if (seq.len > 0) try out.appendSlice(alloc, seq);
                    cur = next_dg;
                }

                const cp_len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch {
                    try out.append(alloc, '?');
                    continue;
                };
                try out.appendSlice(alloc, utf8_buf[0..cp_len]);
            }

            if (cur.any()) {
                var aw: std.Io.Writer.Allocating = .init(alloc);
                defer aw.deinit();
                try ansi.sgr.reset(&aw.writer);
                try out.appendSlice(alloc, aw.writer.buffered());
            }

            if (row < self.rows - 1) {
                try out.append(alloc, '\n');
            }
        }

        return out.toOwnedSlice(alloc);
    }
};

test "init creates correct dimensions" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 10, 5, .true_color);
    defer cv.deinit();
    try std.testing.expectEqual(@as(u16, 10), cv.cols);
    try std.testing.expectEqual(@as(u16, 5), cv.rows);
    try std.testing.expectEqual(@as(usize, 50), cv.cells.len);
}

test "init cells are BLANK" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 4, 4, .true_color);
    defer cv.deinit();
    for (cv.cells) |c| try std.testing.expectEqual(@as(u21, ' '), c.char);
}

test "clear fills bg color" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 3, 3, .true_color);
    defer cv.deinit();
    cv.clear(.{ .ansi16 = .blue });
    for (cv.cells) |c| try std.testing.expect(std.meta.eql(c.bg, ansi.Color{ .ansi16 = .blue }));
}

test "resize changes dimensions and resets cells" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 5, 5, .true_color);
    defer cv.deinit();
    cv.drawChar(3, 3, 'Z', .none, .none);
    try cv.resize(8, 3);
    try std.testing.expectEqual(@as(u16, 8), cv.cols);
    try std.testing.expectEqual(@as(u16, 3), cv.rows);
    try std.testing.expectEqual(@as(usize, 24), cv.cells.len);
    for (cv.cells) |c| try std.testing.expectEqual(@as(u21, ' '), c.char);
}

test "setCell and getCell roundtrip" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 5, 5, .true_color);
    defer cv.deinit();
    cv.setCell(2, 3, .{ .char = '★', .fg = .{ .ansi16 = .yellow } });
    const c = cv.getCell(2, 3);
    try std.testing.expectEqual(@as(u21, '★'), c.char);
    try std.testing.expect(std.meta.eql(c.fg, ansi.Color{ .ansi16 = .yellow }));
}

test "getCell out-of-bounds returns BLANK" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 4, 4, .true_color);
    defer cv.deinit();
    const c = cv.getCell(99, 99);
    try std.testing.expectEqual(Cell.BLANK.char, c.char);
}

test "render blank canvas produces spaces and newlines only" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 3, 2, .true_color);
    defer cv.deinit();
    const out = try cv.render(alloc);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("   \n   ", out);
}

test "render single row no trailing newline" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 4, 1, .true_color);
    defer cv.deinit();
    const out = try cv.render(alloc);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("    ", out);
}

test "render colored cell emits SGR and content" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 3, 1, .true_color);
    defer cv.deinit();
    cv.drawChar(0, 0, 'A', .{ .ansi16 = .red }, .none);
    const out = try cv.render(alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "A") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1B[") != null);
}

test "render no_color profile emits no SGR sequences" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 2, 1, .no_color);
    defer cv.deinit();
    cv.drawChar(0, 0, 'X', .{ .ansi16 = .red }, .{ .ansi256 = 200 });
    cv.drawChar(1, 0, 'Y', .{ .rgb = .{ .r = 0, .g = 255, .b = 0 } }, .none);
    const out = try cv.render(alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1B[") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "X") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Y") != null);
}

test "render reset emitted at end of colored row" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 2, 2, .true_color);
    defer cv.deinit();
    cv.drawChar(0, 0, 'A', .{ .ansi16 = .green }, .none);
    cv.drawChar(1, 0, 'B', .{ .ansi16 = .green }, .none);
    const out = try cv.render(alloc);
    defer alloc.free(out);

    const reset_pos = std.mem.indexOf(u8, out, "\x1B[0m") orelse
        std.mem.indexOf(u8, out, "\x1B[m");

    try std.testing.expect(reset_pos != null);
    const newline_pos = std.mem.indexOf(u8, out, "\n");
    try std.testing.expect(newline_pos != null);
    try std.testing.expect(reset_pos.? < newline_pos.?);
}

test "drawText writes ascii string" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 10, 1, .true_color);
    defer cv.deinit();
    cv.drawText(0, 0, "hello", .none, .none);
    try std.testing.expectEqual(@as(u21, 'h'), cv.getCell(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), cv.getCell(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), cv.getCell(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), cv.getCell(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), cv.getCell(4, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cv.getCell(5, 0).char);
}

test "drawText clips at right edge" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 3, 1, .true_color);
    defer cv.deinit();
    cv.drawText(2, 0, "abc", .none, .none);
    try std.testing.expectEqual(@as(u21, 'a'), cv.getCell(2, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cv.getCell(0, 0).char);
}

test "drawText out-of-bounds y is noop" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 3, 1, .true_color);
    defer cv.deinit();
    cv.drawText(0, 5, "abc", .none, .none);
    for (cv.cells) |c| try std.testing.expectEqual(@as(u21, ' '), c.char);
}

test "measureText returns visible width" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 10, 1, .true_color);
    defer cv.deinit();
    try std.testing.expectEqual(@as(u16, 5), cv.measureText("hello"));
    try std.testing.expectEqual(@as(u16, 0), cv.measureText(""));
}

test "blit copies src into dst at offset" {
    const alloc = std.testing.allocator;
    var dst = try Canvas.init(alloc, 6, 6, .true_color);
    defer dst.deinit();
    var src = try Canvas.init(alloc, 2, 2, .true_color);
    defer src.deinit();
    src.drawChar(0, 0, 'S', .none, .none);
    src.drawChar(1, 1, 'E', .none, .none);
    dst.blit(2, 3, &src);
    try std.testing.expectEqual(@as(u21, 'S'), dst.getCell(2, 3).char);
    try std.testing.expectEqual(@as(u21, 'E'), dst.getCell(3, 4).char);
    try std.testing.expectEqual(@as(u21, ' '), dst.getCell(0, 0).char);
}

test "blit clips out-of-bounds regions" {
    const alloc = std.testing.allocator;
    var dst = try Canvas.init(alloc, 4, 4, .true_color);
    defer dst.deinit();
    var src = try Canvas.init(alloc, 3, 3, .true_color);
    defer src.deinit();
    src.clear(.{ .ansi16 = .red });
    dst.blit(-1, -1, &src);
    try std.testing.expectEqual(@as(u21, ' '), dst.getCell(0, 0).char);
    try std.testing.expect(std.meta.eql(dst.getCell(0, 0).bg, ansi.Color{ .ansi16 = .red }));
}

test "drawRectLines places corners correctly" {
    const alloc = std.testing.allocator;
    var cv = try Canvas.init(alloc, 10, 5, .true_color);
    defer cv.deinit();
    cv.drawRectLines(1, 1, 5, 3, box.ASCII, .none);
    try std.testing.expectEqual(@as(u21, '+'), cv.getCell(1, 1).char);
    try std.testing.expectEqual(@as(u21, '+'), cv.getCell(5, 1).char);
    try std.testing.expectEqual(@as(u21, '+'), cv.getCell(1, 3).char);
    try std.testing.expectEqual(@as(u21, '+'), cv.getCell(5, 3).char);
    try std.testing.expectEqual(@as(u21, '-'), cv.getCell(3, 1).char);
    try std.testing.expectEqual(@as(u21, '|'), cv.getCell(1, 2).char);
    try std.testing.expectEqual(@as(u21, ' '), cv.getCell(3, 2).char);
}
