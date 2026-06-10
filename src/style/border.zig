// SPDX-License-Identifier: MIT

// Border struct and comptime presets.
// Pure data container: zero logic, zero allocations.
const std = @import("std");
const ansi = @import("fern_ansi");

// helpers

// Returns the max cell width across all strings in parts.
// Empty strings contribute 0.  Uses ansi.rawWidth (no ANSI strip needed
// for border glyphs, which contain no SGR sequences).
fn maxEdgeWidth(parts: []const []const u8) u16 {
    var max: u16 = 0;
    for (parts) |p| {
        const w: u16 = @intCast(ansi.rawWidth(p));
        if (w > max) max = w;
    }
    return max;
}

// Border struct

pub const Border = struct {
    top: []const u8 = "",
    bottom: []const u8 = "",
    left: []const u8 = "",
    right: []const u8 = "",
    top_left: []const u8 = "",
    top_right: []const u8 = "",
    bottom_left: []const u8 = "",
    bottom_right: []const u8 = "",
    mid_left: []const u8 = "",
    mid_right: []const u8 = "",
    middle: []const u8 = "",
    mid_top: []const u8 = "",
    mid_bottom: []const u8 = "",

    // Cell width of the top edge.
    // Widest cell width among top_left, top, top_right; 0 if all empty.
    pub fn topSize(b: Border) u16 {
        return maxEdgeWidth(&.{ b.top_left, b.top, b.top_right });
    }

    // Cell width of the bottom edge.
    pub fn bottomSize(b: Border) u16 {
        return maxEdgeWidth(&.{ b.bottom_left, b.bottom, b.bottom_right });
    }

    // Cell width of the left edge.
    // Widest among top_left, left, bottom_left.
    pub fn leftSize(b: Border) u16 {
        return maxEdgeWidth(&.{ b.top_left, b.left, b.bottom_left });
    }

    // Cell width of the right edge.
    pub fn rightSize(b: Border) u16 {
        return maxEdgeWidth(&.{ b.top_right, b.right, b.bottom_right });
    }

    // Total horizontal border size: left + right.
    pub fn horizontalSize(b: Border) u16 {
        return b.leftSize() + b.rightSize();
    }

    // Total vertical border size: top + bottom (0 or 1 per active side).
    pub fn verticalSize(b: Border) u16 {
        return b.topSize() + b.bottomSize();
    }
};

// preset constants
// All are comptime-known; SCREAMING_SNAKE per convention.
pub const NONE: Border = .{};

// <AI>

// box-drawing light: standard single-line box characters
pub const NORMAL: Border = .{
    .top = "\xe2\x94\x80", // U+2500 light horizontal
    .bottom = "\xe2\x94\x80",
    .left = "\xe2\x94\x82", // U+2502 light vertical
    .right = "\xe2\x94\x82",
    .top_left = "\xe2\x94\x8c", // U+250C light down and right
    .top_right = "\xe2\x94\x90", // U+2510 light down and left
    .bottom_left = "\xe2\x94\x94", // U+2514 light up and right
    .bottom_right = "\xe2\x94\x98", // U+2518 light up and left
    .mid_left = "\xe2\x94\x9c", // U+251C light vertical and right
    .mid_right = "\xe2\x94\xa4", // U+2524 light vertical and left
    .middle = "\xe2\x94\xbc", // U+253C light vertical and horizontal
    .mid_top = "\xe2\x94\xac", // U+252C light down and horizontal
    .mid_bottom = "\xe2\x94\xb4", // U+2534 light up and horizontal
};

// box-drawing light arc: rounded corners, same edges as NORMAL
pub const ROUNDED: Border = .{
    .top = "\xe2\x94\x80",
    .bottom = "\xe2\x94\x80",
    .left = "\xe2\x94\x82",
    .right = "\xe2\x94\x82",
    .top_left = "\xe2\x95\xad", // U+256D light arc down and right
    .top_right = "\xe2\x95\xae", // U+256E light arc down and left
    .bottom_left = "\xe2\x95\xb0", // U+2570 light arc up and right
    .bottom_right = "\xe2\x95\xaf", // U+256F light arc up and left
    .mid_left = "\xe2\x94\x9c",
    .mid_right = "\xe2\x94\xa4",
    .middle = "\xe2\x94\xbc",
    .mid_top = "\xe2\x94\xac",
    .mid_bottom = "\xe2\x94\xb4",
};

// box-drawing heavy: bold single-line box characters
pub const THICK: Border = .{
    .top = "\xe2\x94\x81", // U+2501 heavy horizontal
    .bottom = "\xe2\x94\x81",
    .left = "\xe2\x94\x83", // U+2503 heavy vertical
    .right = "\xe2\x94\x83",
    .top_left = "\xe2\x94\x8f", // U+250F heavy down and right
    .top_right = "\xe2\x94\x93", // U+2513 heavy down and left
    .bottom_left = "\xe2\x94\x97", // U+2517 heavy up and right
    .bottom_right = "\xe2\x94\x9b", // U+251B heavy up and left
    .mid_left = "\xe2\x94\xa3", // U+2523 heavy vertical and right
    .mid_right = "\xe2\x94\xab", // U+252B heavy vertical and left
    .middle = "\xe2\x95\x8b", // U+254B heavy vertical and horizontal
    .mid_top = "\xe2\x94\xb3", // U+2533 heavy down and horizontal
    .mid_bottom = "\xe2\x94\xbb", // U+253B heavy up and horizontal
};

// box-drawing double: double-line box characters
pub const DOUBLE: Border = .{
    .top = "\xe2\x95\x90", // U+2550 double horizontal
    .bottom = "\xe2\x95\x90",
    .left = "\xe2\x95\x91", // U+2551 double vertical
    .right = "\xe2\x95\x91",
    .top_left = "\xe2\x95\x94", // U+2554 double down and right
    .top_right = "\xe2\x95\x97", // U+2557 double down and left
    .bottom_left = "\xe2\x95\x9a", // U+255A double up and right
    .bottom_right = "\xe2\x95\x9d", // U+255D double up and left
    .mid_left = "\xe2\x95\xa0", // U+2560 double vertical and right
    .mid_right = "\xe2\x95\xa3", // U+2563 double vertical and left
    .middle = "\xe2\x95\xac", // U+256C double vertical and horizontal
    .mid_top = "\xe2\x95\xa6", // U+2566 double down and horizontal
    .mid_bottom = "\xe2\x95\xa9", // U+2569 double up and horizontal
};

// block fill: all sides use the full block character
pub const BLOCK: Border = .{
    .top = "\xe2\x96\x88", // U+2588 full block
    .bottom = "\xe2\x96\x88",
    .left = "\xe2\x96\x88",
    .right = "\xe2\x96\x88",
    .top_left = "\xe2\x96\x88",
    .top_right = "\xe2\x96\x88",
    .bottom_left = "\xe2\x96\x88",
    .bottom_right = "\xe2\x96\x88",
    .mid_left = "\xe2\x96\x88",
    .mid_right = "\xe2\x96\x88",
    .middle = "\xe2\x96\x88",
    .mid_top = "\xe2\x96\x88",
    .mid_bottom = "\xe2\x96\x88",
};

// half-block outer shell; mid_* fields are empty
pub const OUTER_HALF_BLOCK: Border = .{
    .top = "\xe2\x96\x80", // U+2580 upper half block
    .bottom = "\xe2\x96\x84", // U+2584 lower half block
    .left = "\xe2\x96\x8c", // U+258C left half block
    .right = "\xe2\x96\x90", // U+2590 right half block
    .top_left = "\xe2\x96\x9b", // U+259B quadrant upper-left/right/lower-left
    .top_right = "\xe2\x96\x9c", // U+259C quadrant upper-left/right/lower-right
    .bottom_left = "\xe2\x96\x99", // U+2599 quadrant upper-left/lower-left/right
    .bottom_right = "\xe2\x96\x9f", // U+259F quadrant upper-right/lower-left/right
};

// half-block inner inversion of OUTER_HALF_BLOCK; mid_* fields are empty
pub const INNER_HALF_BLOCK: Border = .{
    .top = "\xe2\x96\x84", // U+2584 lower half block (inverted top)
    .bottom = "\xe2\x96\x80", // U+2580 upper half block (inverted bottom)
    .left = "\xe2\x96\x90", // U+2590 right half block (inverted left)
    .right = "\xe2\x96\x8c", // U+258C left half block (inverted right)
    .top_left = "\xe2\x96\x97", // U+2597 quadrant lower right
    .top_right = "\xe2\x96\x96", // U+2596 quadrant lower left
    .bottom_left = "\xe2\x96\x9d", // U+259D quadrant upper right
    .bottom_right = "\xe2\x96\x98", // U+2598 quadrant upper left
};

// hidden border: single space on every side for spacing without visible lines
pub const HIDDEN: Border = .{
    .top = " ",
    .bottom = " ",
    .left = " ",
    .right = " ",
    .top_left = " ",
    .top_right = " ",
    .bottom_left = " ",
    .bottom_right = " ",
    .mid_left = " ",
    .mid_right = " ",
    .middle = " ",
    .mid_top = " ",
    .mid_bottom = " ",
};

// ASCII fallback for terminals without box-drawing support
pub const ASCII: Border = .{
    .top = "-",
    .bottom = "-",
    .left = "|",
    .right = "|",
    .top_left = "+",
    .top_right = "+",
    .bottom_left = "+",
    .bottom_right = "+",
    .mid_left = "|",
    .mid_right = "|",
    .middle = "|",
    .mid_top = "|",
    .mid_bottom = "|",
};

// </AI>

test "Border NORMAL topSize returns 1" {
    try std.testing.expectEqual(@as(u16, 1), NORMAL.topSize());
}

test "Border NORMAL leftSize returns 1" {
    try std.testing.expectEqual(@as(u16, 1), NORMAL.leftSize());
}

test "Border NONE topSize returns 0" {
    try std.testing.expectEqual(@as(u16, 0), NONE.topSize());
}

test "Border NONE horizontalSize returns 0" {
    try std.testing.expectEqual(@as(u16, 0), NONE.horizontalSize());
}

test "Border ASCII topSize returns 1" {
    try std.testing.expectEqual(@as(u16, 1), ASCII.topSize());
}

test "Border ASCII horizontalSize returns 2" {
    try std.testing.expectEqual(@as(u16, 2), ASCII.horizontalSize());
}

test "Border BLOCK all edge sizes return 1" {
    try std.testing.expectEqual(@as(u16, 1), BLOCK.topSize());
    try std.testing.expectEqual(@as(u16, 1), BLOCK.bottomSize());
    try std.testing.expectEqual(@as(u16, 1), BLOCK.leftSize());
    try std.testing.expectEqual(@as(u16, 1), BLOCK.rightSize());
}

test "Border ROUNDED corner cells match NORMAL edge cells in width" {
    // Rounded corners are arc variants with the same cell width as plain corners.
    try std.testing.expectEqual(NORMAL.leftSize(), ROUNDED.leftSize());
    try std.testing.expectEqual(NORMAL.rightSize(), ROUNDED.rightSize());
    try std.testing.expectEqual(NORMAL.topSize(), ROUNDED.topSize());
    try std.testing.expectEqual(NORMAL.bottomSize(), ROUNDED.bottomSize());
}
