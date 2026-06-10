// SPDX-License-Identifier: MIT

// Horizontal and vertical block composition.
// Completely stateless and side-effect free. Every function in here just crunches
// the layout and returns a freshly allocated []u8. The caller takes full
// ownership of the memory.
const std = @import("std");
const ansi = @import("fern_ansi");

// Pos type and constants

pub const Pos = f32;

// Position constants.  LEFT and TOP share value 0.0; RIGHT and BOTTOM share 1.0.
pub const TOP: Pos = 0.0;
pub const BOTTOM: Pos = 1.0;
pub const CENTER: Pos = 0.5;
pub const LEFT: Pos = 0.0;
pub const RIGHT: Pos = 1.0;

// Clamp p to [0.0, 1.0] before any multiplication to prevent nonsense layout.
fn clampPos(p: Pos) Pos {
    return std.math.clamp(p, 0.0, 1.0);
}

// hstack

// Horizontally joins text blocks.
// `pos` handles vertical alignment for differing heights (0.0 top, 0.5 center, 1.0 bottom).
// Bails early on empty/single slices. Always returns a caller-owned []u8.
pub fn hstack(
    allocator: std.mem.Allocator,
    pos: Pos,
    blocks: []const []const u8,
) error{OutOfMemory}![]u8 {
    if (blocks.len == 0) return allocator.dupe(u8, "");
    if (blocks.len == 1) return allocator.dupe(u8, blocks[0]);

    // Split each block into its lines and compute per-block max display width.
    var split_buf = try allocator.alloc([]const []const u8, blocks.len);
    defer allocator.free(split_buf);
    var width_buf = try allocator.alloc(u16, blocks.len);
    defer allocator.free(width_buf);

    var max_height: usize = 0;
    for (blocks, 0..) |blk, i| {
        const lines = try ansi.str.splitLines(blk, allocator);
        split_buf[i] = lines;
        var w: u16 = 0;
        for (lines) |ln| {
            const lw: u16 = @intCast(ansi.strWidth(ln));
            if (lw > w) w = lw;
        }
        width_buf[i] = w;
        if (lines.len > max_height) max_height = lines.len;
    }
    defer {
        for (split_buf) |lines| allocator.free(lines);
    }

    // Expand each block to max_height by padding with empty strings.
    // Allocate a mutable slice of line arrays per block.
    var padded = try allocator.alloc([][]const u8, blocks.len);
    defer {
        for (padded) |p| allocator.free(p);
        allocator.free(padded);
    }

    const p = clampPos(pos);
    for (split_buf, 0..) |lines, i| {
        const have = lines.len;
        if (have >= max_height) {
            // No padding needed; copy slice reference.
            const row_buf = try allocator.alloc([]const u8, have);
            @memcpy(row_buf, lines);
            padded[i] = row_buf;
            continue;
        }
        const extra = max_height - have;
        const top_extra = @as(usize, @intFromFloat(
            @round(@as(f32, @floatFromInt(extra)) * p),
        ));
        const bot_extra = extra - top_extra;

        const row_buf = try allocator.alloc([]const u8, max_height);
        for (0..top_extra) |r| row_buf[r] = "";
        @memcpy(row_buf[top_extra..][0..have], lines);
        for (0..bot_extra) |r| row_buf[top_extra + have + r] = "";
        padded[i] = row_buf;
    }

    // Assemble rows: for each row append each block's line + right-pad to max_width.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (0..max_height) |row| {
        for (padded, 0..) |p_lines, i| {
            const ln = p_lines[row];
            const lw = @as(u16, @intCast(ansi.strWidth(ln)));
            try out.appendSlice(allocator, ln);
            const pad = width_buf[i] -| lw;
            try out.appendNTimes(allocator, ' ', pad);
        }
        if (row < max_height - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// vstack

// Vertically stacks text blocks.
// `pos` handles horizontal alignment for differing widths (0.0 left, 0.5 center, 1.0 right).
// Returns a caller-owned []u8.
pub fn vstack(
    allocator: std.mem.Allocator,
    pos: Pos,
    blocks: []const []const u8,
) error{OutOfMemory}![]u8 {
    if (blocks.len == 0) return allocator.dupe(u8, "");
    if (blocks.len == 1) return allocator.dupe(u8, blocks[0]);

    // Collect all lines from all blocks and compute global max_width.
    var all_lines: std.ArrayList([]const u8) = .empty;
    defer all_lines.deinit(allocator);
    var block_line_counts = try allocator.alloc(usize, blocks.len);
    defer allocator.free(block_line_counts);

    var max_width: u16 = 0;
    for (blocks, 0..) |blk, i| {
        const lines = try ansi.str.splitLines(blk, allocator);
        defer allocator.free(lines);
        block_line_counts[i] = lines.len;
        for (lines) |ln| {
            const lw: u16 = @intCast(ansi.strWidth(ln));
            if (lw > max_width) max_width = lw;
            try all_lines.append(allocator, ln);
        }
    }

    const total_lines = all_lines.items.len;
    const p = clampPos(pos);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (all_lines.items, 0..) |ln, idx| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        const gap: u16 = max_width -| lw;

        if (p == LEFT) {
            try out.appendSlice(allocator, ln);
            try out.appendNTimes(allocator, ' ', gap);
        } else if (p == RIGHT) {
            try out.appendNTimes(allocator, ' ', gap);
            try out.appendSlice(allocator, ln);
        } else {
            const right: u16 = @intCast(@as(
                usize,
                @intFromFloat(@round(@as(f32, @floatFromInt(gap)) * p)),
            ));
            const left: u16 = gap - right;
            try out.appendNTimes(allocator, ' ', left);
            try out.appendSlice(allocator, ln);
            try out.appendNTimes(allocator, ' ', right);
        }

        if (idx < total_lines - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// place

// Place str in a box of box_w x box_h cells.
// h_pos and v_pos control alignment within the box.
// Caller owns the returned slice.  Free with allocator.free().
pub fn place(
    allocator: std.mem.Allocator,
    box_w: u16,
    box_h: u16,
    h_pos: Pos,
    v_pos: Pos,
    str: []const u8,
) error{OutOfMemory}![]u8 {
    const h = try placeH(allocator, box_w, h_pos, str);
    defer allocator.free(h);
    return placeV(allocator, box_h, v_pos, h);
}

// placeH

// Pads text to `box_w` cells horizontally.
// Bails and returns a direct dupe if the content is already too wide (no truncation).
// Returns a caller-owned []u8.
pub fn placeH(
    allocator: std.mem.Allocator,
    box_w: u16,
    pos: Pos,
    str: []const u8,
) error{OutOfMemory}![]u8 {
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    var content_w: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > content_w) content_w = lw;
    }

    const gap_i: i32 = @as(i32, box_w) - @as(i32, content_w);
    if (gap_i <= 0) return allocator.dupe(u8, str);

    const gap: u16 = @intCast(gap_i);
    const p = clampPos(pos);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (lines, 0..) |ln, i| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        // This line may be shorter than content_w; close that gap too.
        const short: u16 = content_w -| lw;
        const total_gap = gap + short;

        if (p == LEFT) {
            try out.appendSlice(allocator, ln);
            try out.appendNTimes(allocator, ' ', total_gap);
        } else if (p == RIGHT) {
            try out.appendNTimes(allocator, ' ', total_gap);
            try out.appendSlice(allocator, ln);
        } else {
            const right: u16 = @intCast(@as(
                usize,
                @intFromFloat(@round(@as(f32, @floatFromInt(total_gap)) * p)),
            ));
            const left: u16 = total_gap - right;
            try out.appendNTimes(allocator, ' ', left);
            try out.appendSlice(allocator, ln);
            try out.appendNTimes(allocator, ' ', right);
        }

        if (i < lines.len - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// placeV

// Vertically pads text to `box_h` lines.
// Bails and returns a direct dupe if the content is already too tall (no clipping).
// Returns a caller-owned []u8.
pub fn placeV(
    allocator: std.mem.Allocator,
    box_h: u16,
    pos: Pos,
    str: []const u8,
) error{OutOfMemory}![]u8 {
    const content_h = blk: {
        var n: usize = 1;
        for (str) |c| if (c == '\n') {
            n += 1;
        };
        break :blk n;
    };

    const gap_i: i32 = @as(i32, box_h) - @as(i32, @intCast(content_h));
    if (gap_i <= 0) return allocator.dupe(u8, str);

    const gap: usize = @intCast(gap_i);

    // Determine line width for blank lines (max visible width in str).
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);
    var line_w: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > line_w) line_w = lw;
    }

    const p = clampPos(pos);
    const top_gap = @as(usize, @intFromFloat(
        @round(@as(f32, @floatFromInt(gap)) * p),
    ));
    const bot_gap = gap - top_gap;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    // Top blank lines.
    for (0..top_gap) |_| {
        try out.appendNTimes(allocator, ' ', line_w);
        try out.append(allocator, '\n');
    }

    try out.appendSlice(allocator, str);

    // Bottom blank lines.
    for (0..bot_gap) |_| {
        try out.append(allocator, '\n');
        try out.appendNTimes(allocator, ' ', line_w);
    }

    return out.toOwnedSlice(allocator);
}

test "hstack of two equal-height single-line strings concatenates them" {
    const allocator = std.testing.allocator;
    const r = try hstack(allocator, TOP, &.{ "aa", "bb" });
    defer allocator.free(r);
    try std.testing.expectEqualStrings("aabb", r);
}

test "hstack of two different-height blocks pads shorter block at bottom for TOP" {
    const allocator = std.testing.allocator;
    const r = try hstack(allocator, TOP, &.{ "a\nb", "x" });
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(@as(usize, 2), ls.len);
    // First row: "a" + "x" = "ax"
    try std.testing.expectEqualStrings("ax", ls[0]);
    // Second row: "b" + space padding for "x" block
    try std.testing.expectEqual(true, std.mem.startsWith(u8, ls[1], "b"));
}

test "hstack of two different-height blocks pads shorter block at top for BOTTOM" {
    const allocator = std.testing.allocator;
    const r = try hstack(allocator, BOTTOM, &.{ "a\nb", "x" });
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(true, std.mem.startsWith(u8, ls[ls.len - 1], "b"));
}

test "hstack with one element returns that element" {
    const allocator = std.testing.allocator;
    const r = try hstack(allocator, TOP, &.{"hello"});
    defer allocator.free(r);
    try std.testing.expectEqualStrings("hello", r);
}

test "hstack with empty slice returns empty string" {
    const allocator = std.testing.allocator;
    const r = try hstack(allocator, TOP, &.{});
    defer allocator.free(r);
    try std.testing.expectEqual(@as(usize, 0), r.len);
}

test "vstack of two blocks joins them with newline" {
    const allocator = std.testing.allocator;
    const r = try vstack(allocator, LEFT, &.{ "aa", "bb" });
    defer allocator.free(r);
    try std.testing.expectEqualStrings("aa\nbb", r);
}

test "vstack RIGHT-aligns shorter lines" {
    const allocator = std.testing.allocator;
    const r = try vstack(allocator, RIGHT, &.{ "a", "bbb" });
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(@as(usize, 2), ls.len);
    // "a" should be padded to 3 cells on the left: "  a"
    try std.testing.expectEqualStrings("  a", ls[0]);
}

test "vstack CENTER-aligns shorter lines" {
    const allocator = std.testing.allocator;
    const r = try vstack(allocator, CENTER, &.{ "a", "bbb" });
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    // "a" in a 3-wide box centred: one space each side -> " a "
    try std.testing.expectEqualStrings(" a ", ls[0]);
}

test "placeH with box wider than content pads on the right for LEFT" {
    const allocator = std.testing.allocator;
    const r = try placeH(allocator, 10, LEFT, "hi");
    defer allocator.free(r);
    try std.testing.expectEqual(@as(usize, 10), ansi.strWidth(r));
    try std.testing.expectEqual(true, std.mem.startsWith(u8, r, "hi"));
}

test "placeH with box wider than content pads on the left for RIGHT" {
    const allocator = std.testing.allocator;
    const r = try placeH(allocator, 10, RIGHT, "hi");
    defer allocator.free(r);
    try std.testing.expectEqual(@as(usize, 10), ansi.strWidth(r));
    try std.testing.expectEqual(true, std.mem.endsWith(u8, r, "hi"));
}

test "placeH with box not wider than content returns input unchanged" {
    const allocator = std.testing.allocator;
    const r = try placeH(allocator, 2, LEFT, "hi");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("hi", r);
}

test "placeV with box taller than content adds blank lines at bottom for TOP" {
    const allocator = std.testing.allocator;
    const r = try placeV(allocator, 4, TOP, "hi");
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(@as(usize, 4), ls.len);
    try std.testing.expectEqualStrings("hi", ls[0]);
}

test "placeV with box taller than content adds blank lines at top for BOTTOM" {
    const allocator = std.testing.allocator;
    const r = try placeV(allocator, 4, BOTTOM, "hi");
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(@as(usize, 4), ls.len);
    try std.testing.expectEqualStrings("hi", ls[3]);
}

test "place combines placeH and placeV" {
    const allocator = std.testing.allocator;
    const r = try place(allocator, 10, 4, CENTER, CENTER, "hi");
    defer allocator.free(r);
    const ls = try ansi.str.splitLines(r, allocator);
    defer allocator.free(ls);
    try std.testing.expectEqual(@as(usize, 4), ls.len);
    try std.testing.expectEqual(@as(usize, 10), ansi.strWidth(ls[0]));
}
