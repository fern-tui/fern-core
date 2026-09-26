const std = @import("std");
const ansi = @import("fern_ansi");
const cell_mod = @import("cell.zig");

const Cell = cell_mod.Cell;

pub fn setCell(cells: []Cell, cols: u16, rows: u16, x: i32, y: i32, cell: Cell) void {
    if (x < 0 or y < 0 or x >= @as(i32, cols) or y >= @as(i32, rows)) return;
    cells[@as(usize, @intCast(y)) * cols + @as(usize, @intCast(x))] = cell;
}

pub fn hline(cells: []Cell, cols: u16, rows: u16, x: i32, y: i32, len: i32, cell: Cell) void {
    if (y < 0 or y >= @as(i32, rows) or len <= 0) return;
    const row_off: usize = @as(usize, @intCast(y)) * cols;
    var i: i32 = 0;
    while (i < len) : (i += 1) {
        const xi = x + i;
        if (xi < 0) continue;
        if (xi >= @as(i32, cols)) break;
        cells[row_off + @as(usize, @intCast(xi))] = cell;
    }
}

pub fn vline(cells: []Cell, cols: u16, rows: u16, x: i32, y: i32, len: i32, cell: Cell) void {
    if (x < 0 or x >= @as(i32, cols) or len <= 0) return;
    const xi: usize = @intCast(x);
    var i: i32 = 0;
    while (i < len) : (i += 1) {
        const yi = y + i;
        if (yi < 0) continue;
        if (yi >= @as(i32, rows)) break;
        cells[@as(usize, @intCast(yi)) * cols + xi] = cell;
    }
}

pub fn line(cells: []Cell, cols: u16, rows: u16, x0: i32, y0: i32, x1: i32, y1: i32, char: u21, fg: ansi.Color) void {
    const dx = if (x1 > x0) x1 - x0 else x0 - x1;
    const dy = if (y1 > y0) y1 - y0 else y0 - y1;
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err: i32 = dx - dy;
    var x = x0;
    var y = y0;
    while (true) {
        setCell(cells, cols, rows, x, y, .{ .char = char, .fg = fg });
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn rect(cells: []Cell, cols: u16, rows: u16, x: i32, y: i32, w: i32, h: i32, fill: Cell) void {
    if (w <= 0 or h <= 0) return;
    var row: i32 = 0;
    while (row < h) : (row += 1) {
        hline(cells, cols, rows, x, y + row, w, fill);
    }
}

fn plotEllipse4(cells: []Cell, cols: u16, rows: u16, cx: i32, cy: i32, x: i32, y: i32, char: u21, fg: ansi.Color) void {
    const c = Cell{ .char = char, .fg = fg };
    setCell(cells, cols, rows, cx + x, cy + y, c);
    setCell(cells, cols, rows, cx - x, cy + y, c);
    setCell(cells, cols, rows, cx + x, cy - y, c);
    setCell(cells, cols, rows, cx - x, cy - y, c);
}

pub fn ellipseLines(cells: []Cell, cols: u16, rows: u16, cx: i32, cy: i32, rx: i32, ry: i32, char: u21, fg: ansi.Color) void {
    if (rx <= 0 or ry <= 0) return;
    const a2: i64 = @as(i64, rx) * rx;
    const b2: i64 = @as(i64, ry) * ry;

    var xi: i64 = 0;
    var yi: i64 = ry;
    var sigma: i64 = 2 * b2 + a2 * (1 - 2 * @as(i64, ry));
    while (b2 * xi <= a2 * yi) {
        plotEllipse4(cells, cols, rows, cx, cy, @intCast(xi), @intCast(yi), char, fg);
        if (sigma >= 0) {
            sigma += 4 * a2 * (1 - yi);
            yi -= 1;
        }
        sigma += b2 * (4 * xi + 6);
        xi += 1;
    }

    xi = rx;
    yi = 0;
    sigma = 2 * a2 + b2 * (1 - 2 * @as(i64, rx));
    while (a2 * yi <= b2 * xi) {
        plotEllipse4(cells, cols, rows, cx, cy, @intCast(xi), @intCast(yi), char, fg);
        if (sigma >= 0) {
            sigma += 4 * b2 * (1 - xi);
            xi -= 1;
        }
        sigma += a2 * (4 * yi + 6);
        yi += 1;
    }
}

pub fn ellipse(cells: []Cell, cols: u16, rows: u16, cx: i32, cy: i32, rx: i32, ry: i32, fill: Cell) void {
    if (rx <= 0 or ry <= 0) return;
    const rx2: i64 = @as(i64, rx) * rx;
    const ry2: i64 = @as(i64, ry) * ry;
    var yi: i32 = -ry;
    while (yi <= ry) : (yi += 1) {
        const y2: i64 = @as(i64, yi) * yi;
        const rem: i64 = ry2 - y2;
        if (rem < 0) continue;
        var xw: i64 = 0;
        while ((xw + 1) * (xw + 1) * ry2 <= rx2 * rem) : (xw += 1) {}
        const span: i32 = @intCast(2 * xw + 1);
        hline(cells, cols, rows, cx - @as(i32, @intCast(xw)), cy + yi, span, fill);
    }
}

test "setCell writes to correct flat index" {
    var cells: [9]Cell = @splat(Cell.BLANK);
    setCell(&cells, 3, 3, 1, 1, .{ .char = 'X' });
    try std.testing.expectEqual(@as(u21, 'X'), cells[4].char);
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
}

test "setCell clips out-of-bounds silently" {
    var cells: [4]Cell = @splat(Cell.BLANK);
    setCell(&cells, 2, 2, 5, 5, .{ .char = 'X' });
    setCell(&cells, 2, 2, -1, 0, .{ .char = 'X' });
    setCell(&cells, 2, 2, 0, -1, .{ .char = 'X' });
    for (cells) |c| try std.testing.expectEqual(@as(u21, ' '), c.char);
}

test "hline fills correct range" {
    var cells: [10]Cell = @splat(Cell.BLANK);
    hline(&cells, 10, 1, 2, 0, 5, .{ .char = '-' });
    for (cells[2..7]) |c| try std.testing.expectEqual(@as(u21, '-'), c.char);
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
    try std.testing.expectEqual(@as(u21, ' '), cells[7].char);
}

test "hline clips at canvas edge" {
    var cells: [5]Cell = @splat(Cell.BLANK);
    hline(&cells, 5, 1, 3, 0, 10, .{ .char = '=' });
    for (cells[3..5]) |c| try std.testing.expectEqual(@as(u21, '='), c.char);
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
}

test "vline fills correct column" {
    var cells: [9]Cell = @splat(Cell.BLANK);
    vline(&cells, 3, 3, 1, 0, 3, .{ .char = '|' });
    try std.testing.expectEqual(@as(u21, '|'), cells[1].char);
    try std.testing.expectEqual(@as(u21, '|'), cells[4].char);
    try std.testing.expectEqual(@as(u21, '|'), cells[7].char);
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
}

test "line draws endpoints" {
    var cells: [25]Cell = @splat(Cell.BLANK);
    line(&cells, 5, 5, 0, 0, 4, 0, '*', .none);
    for (cells[0..5]) |c| try std.testing.expectEqual(@as(u21, '*'), c.char);
}

test "line single point" {
    var cells: [4]Cell = @splat(Cell.BLANK);
    line(&cells, 2, 2, 1, 1, 1, 1, '+', .none);
    try std.testing.expectEqual(@as(u21, '+'), cells[3].char);
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
}

test "rect fills region" {
    var cells: [25]Cell = @splat(Cell.BLANK);
    rect(&cells, 5, 5, 1, 1, 3, 2, .{ .char = '#' });
    for ([_]usize{ 6, 7, 8, 11, 12, 13 }) |i| {
        try std.testing.expectEqual(@as(u21, '#'), cells[i].char);
    }
    try std.testing.expectEqual(@as(u21, ' '), cells[0].char);
    try std.testing.expectEqual(@as(u21, ' '), cells[24].char);
}

test "ellipse fills center row" {
    var cells: [20 * 10]Cell = @splat(Cell.BLANK);
    ellipse(&cells, 20, 10, 10, 5, 4, 3, .{ .char = 'o' });
    try std.testing.expectEqual(@as(u21, 'o'), cells[5 * 20 + 10].char);
}

test "ellipseLines does not fill interior" {
    var cells: [20 * 10]Cell = @splat(Cell.BLANK);
    ellipseLines(&cells, 20, 10, 10, 5, 4, 3, '*', .none);
    try std.testing.expectEqual(@as(u21, ' '), cells[5 * 20 + 10].char);
}
