// SPDX-License-Identifier: MIT

// terminal color types and profile downgrade. no deps.

const std = @import("std");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Ansi16 = enum(u5) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

pub const ColorProfile = enum {
    no_color,
    ansi16,
    ansi256,
    true_color,
};

pub const Color = union(enum) {
    none,
    ansi16: Ansi16,
    ansi256: u8,
    rgb: Rgb,

    // comptime only - e.g. Color.hex(0xFF5733)
    pub fn hex(comptime v: u24) Color {
        return .{ .rgb = .{
            .r = @truncate(v >> 16),
            .g = @truncate(v >> 8),
            .b = @truncate(v),
        } };
    }

    pub fn downgrade(self: Color, profile: ColorProfile) Color {
        return switch (profile) {
            .no_color => .none,
            .true_color => self,
            .ansi256 => switch (self) {
                .none, .ansi16, .ansi256 => self,
                .rgb => |c| rgb_to_ansi256(c),
            },
            .ansi16 => switch (self) {
                .none => .none,
                .ansi16 => self,
                .ansi256 => |n| ansi256_to_ansi16(n),
                .rgb => |c| rgb_to_ansi16(c),
            },
        };
    }

    // downgrades both sides before comparing
    pub fn eql(a: Color, b: Color, profile: ColorProfile) bool {
        const da = a.downgrade(profile);
        const db = b.downgrade(profile);
        return switch (da) {
            .none => db == .none,
            .ansi16 => |x| switch (db) {
                .ansi16 => |y| x == y,
                else => false,
            },
            .ansi256 => |x| switch (db) {
                .ansi256 => |y| x == y,
                else => false,
            },
            .rgb => |x| switch (db) {
                .rgb => |y| x.r == y.r and x.g == y.g and x.b == y.b,
                else => false,
            },
        };
    }
};

// xterm default 16-color palette, used for nearest-color matching
const ANSI16_PALETTE: [16]Rgb = .{
    .{ .r = 12, .g = 12, .b = 12 }, // 0  black
    .{ .r = 197, .g = 15, .b = 31 }, // 1  red
    .{ .r = 19, .g = 161, .b = 14 }, // 2  green
    .{ .r = 193, .g = 156, .b = 0 }, // 3  yellow
    .{ .r = 0, .g = 55, .b = 218 }, // 4  blue
    .{ .r = 136, .g = 23, .b = 152 }, // 5  magenta
    .{ .r = 58, .g = 150, .b = 221 }, // 6  cyan
    .{ .r = 204, .g = 204, .b = 204 }, // 7  white
    .{ .r = 128, .g = 128, .b = 128 }, // 8  bright_black
    .{ .r = 249, .g = 38, .b = 114 }, // 9  bright_red
    .{ .r = 166, .g = 226, .b = 46 }, // 10 bright_green
    .{ .r = 228, .g = 228, .b = 16 }, // 11 bright_yellow
    .{ .r = 74, .g = 20, .b = 140 }, // 12 bright_blue
    .{ .r = 249, .g = 38, .b = 114 }, // 13 bright_magenta
    .{ .r = 42, .g = 161, .b = 152 }, // 14 bright_cyan
    .{ .r = 242, .g = 242, .b = 242 }, // 15 bright_white
};

// weighted perceptual distance: 2r*dr^2 + 4g*dg^2 + 3b*db^2
fn colorDist(a: Rgb, b: Rgb) u64 {
    const dr: i64 = @as(i64, a.r) - @as(i64, b.r);
    const dg: i64 = @as(i64, a.g) - @as(i64, b.g);
    const db: i64 = @as(i64, a.b) - @as(i64, b.b);
    return @as(u64, @intCast(2 * dr * dr + 4 * dg * dg + 3 * db * db));
}

fn rgb_to_ansi16(c: Rgb) Color {
    var best_idx: u5 = 0;
    var best_dist: u64 = std.math.maxInt(u64);
    for (ANSI16_PALETTE, 0..) |ref, i| {
        const d = colorDist(c, ref);
        if (d < best_dist) {
            best_dist = d;
            best_idx = @intCast(i);
        }
    }
    return .{ .ansi16 = @enumFromInt(best_idx) };
}

// ansi256 cube index 16-231 to rgb
fn cube_to_rgb(index: u8) Rgb {
    var n = index - 16;
    const b_i: u8 = n % 6;
    n /= 6;
    const g_i: u8 = n % 6;
    n /= 6;
    const r_i: u8 = n % 6;
    const r: u8 = if (r_i == 0) 0 else 55 + r_i * 40;
    const g: u8 = if (g_i == 0) 0 else 55 + g_i * 40;
    const b: u8 = if (b_i == 0) 0 else 55 + b_i * 40;
    return .{ .r = r, .g = g, .b = b };
}

fn ansi256_to_ansi16(index: u8) Color {
    if (index < 16) {
        return .{ .ansi16 = @enumFromInt(index) };
    }
    const c: Rgb = if (index <= 231)
        cube_to_rgb(index)
    else blk: {
        // grayscale ramp 232-255
        const level: u8 = (index - 232) * 10 + 8;
        break :blk .{ .r = level, .g = level, .b = level };
    };
    return rgb_to_ansi16(c);
}

fn rgb_to_ansi256(c: Rgb) Color {
    // grayscale path: all components equal
    if (c.r == c.g and c.g == c.b) {
        if (c.r < 8) return .{ .ansi256 = 16 };
        if (c.r > 248) return .{ .ansi256 = 231 };
        const idx: u8 = 232 + @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(c.r - 8)) / 247.0 * 23.0)));
        return .{ .ansi256 = idx };
    }
    // chromatic path: 6x6x6 cube
    const ri: u8 = @intFromFloat(@round(@as(f32, @floatFromInt(c.r)) / 255.0 * 5.0));
    const gi: u8 = @intFromFloat(@round(@as(f32, @floatFromInt(c.g)) / 255.0 * 5.0));
    const bi: u8 = @intFromFloat(@round(@as(f32, @floatFromInt(c.b)) / 255.0 * 5.0));
    return .{ .ansi256 = 16 + 36 * ri + 6 * gi + bi };
}

test "rgb black downgrades to ansi256 16" {
    const c = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const got = c.downgrade(.ansi256);
    try std.testing.expectEqual(Color{ .ansi256 = 16 }, got);
}

test "rgb white downgrades to ansi256 231" {
    const c = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
    const got = c.downgrade(.ansi256);
    try std.testing.expectEqual(Color{ .ansi256 = 231 }, got);
}

test "rgb red downgrades to ansi16" {
    const c = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const got = c.downgrade(.ansi16);
    // nearest is red(1) or bright_red(9); both valid per spec
    switch (got) {
        .ansi16 => |v| try std.testing.expect(v == .red or v == .bright_red),
        else => return error.WrongTag,
    }
}

test "no_color profile returns none" {
    const c = Color{ .rgb = .{ .r = 100, .g = 200, .b = 50 } };
    try std.testing.expectEqual(Color.none, c.downgrade(.no_color));
}

test "hex comptime constructor" {
    const c = Color.hex(0xFF5733);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0xFF, .g = 0x57, .b = 0x33 } }, c);
}
