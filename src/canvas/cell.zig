const std = @import("std");
const ansi = @import("fern_ansi");

pub const Cell = struct {
    char: u21 = ' ',
    fg: ansi.Color = .none,
    bg: ansi.Color = .none,
    bold: bool = false,

    pub const BLANK: Cell = .{};
};

test "BLANK is space with no attributes" {
    const b = Cell.BLANK;
    try std.testing.expectEqual(@as(u21, ' '), b.char);
    try std.testing.expect(b.fg == .none);
    try std.testing.expect(b.bg == .none);
    try std.testing.expect(!b.bold);
}

test "default Cell equals BLANK" {
    const c: Cell = .{};
    try std.testing.expectEqual(Cell.BLANK.char, c.char);
    try std.testing.expectEqual(Cell.BLANK.bold, c.bold);
    try std.testing.expect(std.meta.eql(Cell.BLANK.fg, c.fg));
    try std.testing.expect(std.meta.eql(Cell.BLANK.bg, c.bg));
}

test "Cell fields set correctly" {
    const c = Cell{
        .char = '█',
        .fg = .{ .ansi16 = .red },
        .bg = .{ .ansi256 = 22 },
        .bold = true,
    };
    try std.testing.expectEqual(@as(u21, '█'), c.char);
    try std.testing.expect(c.bold);
    try std.testing.expect(c.fg == .ansi16);
    try std.testing.expect(c.bg == .ansi256);
}
