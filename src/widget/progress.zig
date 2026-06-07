// SPDX-License-Identifier: MIT

// progress.zig - animated progress bar widget.
//
// progress:  Supports solid fill or a per-cell RGB
// gradient across the filled portion, animated percent display, and
// spring-based smooth transition via fern_anim.
//
// Default fill character is now FULL_FULL_BLOCK (█) for a continuous bar.
// Gradient is enabled by default: full_color (low) → full_color_high.
// Set use_gradient = false to revert to the single-colour path.
//
// Imports: std, fern_ansi, fern_style, fern_app, fern_anim.

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const anim = @import("fern_anim");

// ---------------------------------------------------------------------------
// Fill characters
// ---------------------------------------------------------------------------

pub const FULL_HALF_BLOCK: []const u8 = "\xe2\x96\x8c"; // U+258C ▌ left half
pub const FULL_FULL_BLOCK: []const u8 = "\xe2\x96\x88"; // U+2588 █ full block
pub const EMPTY_BLOCK: []const u8 = "\xe2\x96\x91"; // U+2591 ░ light shade

// ---------------------------------------------------------------------------
// Gradient helpers (file-private)
// ---------------------------------------------------------------------------

/// Extract an RGB triple from any Color variant.
/// Non-RGB variants fall back to the default purple so gradient math
/// still produces a valid colour even if the caller used ansi16/256.
fn toRgb(c: ansi.Color) ansi.Rgb {
    return switch (c) {
        .rgb => |v| v,
        // Fallback keeps the bar visible rather than producing black.
        else => .{ .r = 0x75, .g = 0x71, .b = 0xF9 },
    };
}

/// Linear interpolation between two u8 values.
/// t is clamped to [0, 1] before use, so the result is always [0, 255].
fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const fa: f32 = @floatFromInt(a);
    const fb: f32 = @floatFromInt(b);
    const val = std.math.clamp(fa + (fb - fa) * t, 0.0, 255.0);
    return @intFromFloat(@round(val));
}

// ---------------------------------------------------------------------------
// FrameMsg -- drives spring animation
// ---------------------------------------------------------------------------

pub const FrameMsg = struct { id: u32, tag: u32 };

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

var next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

const FPS: u64 = 60;
const NS_PER_FRAME: u64 = std.time.ns_per_s / FPS;

pub const Progress = struct {
    id: u32,
    tag: u32 = 0,

    width: u16 = 40,
    // Full block gives a continuous bar; half-block (▌) leaves visible gaps.
    full_char: []const u8 = FULL_FULL_BLOCK,
    empty_char: []const u8 = EMPTY_BLOCK,
    // Gradient low (left edge) and high (right edge) colours.
    // Matches the charmbracelet/bubbles default palette.
    full_color: ansi.Color = .{ .rgb = .{ .r = 0x75, .g = 0x71, .b = 0xF9 } },
    full_color_high: ansi.Color = .{ .rgb = .{ .r = 0xEE, .g = 0x6F, .b = 0xF8 } },
    empty_color: ansi.Color = .{ .rgb = .{ .r = 0x60, .g = 0x60, .b = 0x60 } },
    // When true, each filled cell gets an individually interpolated colour.
    use_gradient: bool = true,
    show_percent: bool = true,
    percent_fmt: []const u8 = " {d:>3.0}%",

    // Spring animation state.
    spring: anim.Spring = anim.Spring.init(anim.fps(FPS), 18.0, 1.0),
    percent_shown: f32 = 0.0,
    percent_target: f32 = 0.0,
    velocity: f32 = 0.0,

    // --- lifecycle ----------------------------------------------------------

    pub fn init() Progress {
        return .{ .id = next_id.fetchAdd(1, .monotonic) };
    }

    // --- setters ------------------------------------------------------------

    pub fn setWidth(self: *Progress, w: u16) void {
        self.width = w;
    }

    pub fn setFullColor(self: *Progress, c: ansi.Color) void {
        self.full_color = c;
    }

    pub fn setEmptyColor(self: *Progress, c: ansi.Color) void {
        self.empty_color = c;
    }

    /// Set both gradient endpoints and enable gradient mode.
    pub fn setGradient(self: *Progress, low: ansi.Color, high: ansi.Color) void {
        self.full_color = low;
        self.full_color_high = high;
        self.use_gradient = true;
    }

    pub fn showPercent(self: *Progress, on: bool) void {
        self.show_percent = on;
    }

    pub fn setSpring(self: *Progress, frequency: f32, damping: f32) void {
        self.spring = anim.Spring.init(
            anim.fps(FPS),
            @as(f64, frequency),
            @as(f64, damping),
        );
    }

    // --- percent control ----------------------------------------------------

    /// Set the target percent (0.0..1.0) and return an animation Cmd.
    /// MsgT must have a field `progress_frame: FrameMsg`.
    pub fn setPercent(
        self: *Progress,
        pct: f32,
        comptime MsgT: type,
    ) app.Cmd(MsgT) {
        self.percent_target = std.math.clamp(pct, 0.0, 1.0);
        self.tag +%= 1;
        return self.nextFrame(MsgT);
    }

    pub fn incrPercent(self: *Progress, delta: f32, comptime MsgT: type) app.Cmd(MsgT) {
        return self.setPercent(self.percent_target + delta, MsgT);
    }

    pub fn decrPercent(self: *Progress, delta: f32, comptime MsgT: type) app.Cmd(MsgT) {
        return self.setPercent(self.percent_target - delta, MsgT);
    }

    fn nextFrame(self: *const Progress, comptime MsgT: type) app.Cmd(MsgT) {
        const frame_id = self.id;
        const frame_tag = self.tag;
        return app.Cmd(MsgT){ .after = .{
            .ns = NS_PER_FRAME,
            .msg = @unionInit(MsgT, "progress_frame", FrameMsg{
                .id = frame_id,
                .tag = frame_tag,
            }),
        } };
    }

    // --- update -------------------------------------------------------------

    pub fn update(
        self: Progress,
        msg: FrameMsg,
        comptime MsgT: type,
    ) struct { p: Progress, cmd: ?app.Cmd(MsgT) } {
        if (msg.id != self.id or msg.tag != self.tag) {
            return .{ .p = self, .cmd = null };
        }
        var p = self;
        if (!p.isAnimating()) return .{ .p = p, .cmd = null };
        const result = p.spring.update(
            @as(f64, p.percent_shown),
            @as(f64, p.velocity),
            @as(f64, p.percent_target),
        );
        p.percent_shown = @floatCast(result.pos);
        p.velocity = @floatCast(result.vel);
        return .{ .p = p, .cmd = p.nextFrame(MsgT) };
    }

    pub fn isAnimating(self: Progress) bool {
        const dist = @abs(self.percent_shown - self.percent_target);
        return !(dist < 0.001 and @abs(self.velocity) < 0.01);
    }

    // --- view ---------------------------------------------------------------

    /// Render the progress bar at the current animated percent.
    /// Caller owns the returned slice.
    pub fn view(self: Progress, allocator: std.mem.Allocator) ![]u8 {
        return self.viewAs(allocator, self.percent_shown);
    }

    /// Render a static progress bar at an explicit percent.
    pub fn viewAs(self: Progress, allocator: std.mem.Allocator, pct: f32) ![]u8 {
        const clamped = std.math.clamp(pct, 0.0, 1.0);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        // Build percent label first so we know its display width.
        var pct_buf: [16]u8 = undefined;
        const pct_str: []const u8 = if (self.show_percent)
            std.fmt.bufPrint(&pct_buf, " {d:>3.0}%", .{clamped * 100.0}) catch ""
        else
            "";

        const pct_w: u16 = @intCast(ansi.strWidth(pct_str));
        const bar_w: u16 = if (self.width > pct_w) self.width - pct_w else 0;
        const filled: u16 = @intFromFloat(
            @round(@as(f32, @floatFromInt(bar_w)) * clamped),
        );
        const empty_cells: u16 = bar_w - filled;

        // Filled section.
        if (filled > 0) {
            if (self.use_gradient) {
                try renderGradient(&out, allocator, self.full_char, filled, self.full_color, self.full_color_high);
            } else {
                const full_attrs = ansi.Attrs{ .fg = self.full_color };
                var color_w: std.Io.Writer.Allocating = .init(allocator);
                defer color_w.deinit();
                try ansi.sgr.diff(&color_w.writer, ansi.Attrs{}, full_attrs, .true_color);
                try out.appendSlice(allocator, color_w.writer.buffered());
                for (0..filled) |_| try out.appendSlice(allocator, self.full_char);
                var reset_w: std.Io.Writer.Allocating = .init(allocator);
                defer reset_w.deinit();
                try ansi.sgr.reset(&reset_w.writer);
                try out.appendSlice(allocator, reset_w.writer.buffered());
            }
        }

        // Empty section — single colour, no gradient.
        if (empty_cells > 0) {
            const empty_attrs = ansi.Attrs{ .fg = self.empty_color };
            var color_w: std.Io.Writer.Allocating = .init(allocator);
            defer color_w.deinit();
            try ansi.sgr.diff(&color_w.writer, ansi.Attrs{}, empty_attrs, .true_color);
            try out.appendSlice(allocator, color_w.writer.buffered());
            for (0..empty_cells) |_| try out.appendSlice(allocator, self.empty_char);
            var reset_w: std.Io.Writer.Allocating = .init(allocator);
            defer reset_w.deinit();
            try ansi.sgr.reset(&reset_w.writer);
            try out.appendSlice(allocator, reset_w.writer.buffered());
        }

        // Percent label (plain text, no SGR needed).
        try out.appendSlice(allocator, pct_str);

        return out.toOwnedSlice(allocator);
    }
};

// ---------------------------------------------------------------------------
// renderGradient — file-private; called only from viewAs
//
// Per-cell RGB escape sequences are written into `out` using stack buffers
// (no heap allocation per cell) in line with hot-path discipline.
// Maximum escape sequence length: "\x1b[38;2;255;255;255m" = 19 bytes.
// The 24-byte buf always fits this, so bufPrint never returns NoSpaceLeft.
// ---------------------------------------------------------------------------

fn renderGradient(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    fill_char: []const u8,
    cell_count: u16,
    low: ansi.Color,
    high: ansi.Color,
) !void {
    const lo = toRgb(low);
    const hi = toRgb(high);
    // Denominator for t: (count - 1) so the last cell lands exactly on `hi`.
    // When count == 1 there is no range; t stays 0 and we use lo.
    const denom: f32 = if (cell_count > 1) @as(f32, @floatFromInt(cell_count - 1)) else 1.0;

    var esc_buf: [24]u8 = undefined;

    for (0..cell_count) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / denom;
        const cell_r = lerpU8(lo.r, hi.r, t);
        const cell_g = lerpU8(lo.g, hi.g, t);
        const cell_b = lerpU8(lo.b, hi.b, t);

        // Stack-allocated escape sequence; no heap touch inside this loop.
        const esc = std.fmt.bufPrint(
            &esc_buf,
            "\x1b[38;2;{d};{d};{d}m",
            .{ cell_r, cell_g, cell_b },
        ) catch unreachable; // buffer is always large enough

        try out.appendSlice(allocator, esc);
        try out.appendSlice(allocator, fill_char);
    }

    // Reset once after the entire filled section, not per-cell.
    try out.appendSlice(allocator, "\x1b[0m");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Progress init defaults" {
    const p = Progress.init();
    try std.testing.expect(p.width == 40);
    try std.testing.expect(p.show_percent == true);
    try std.testing.expect(p.use_gradient == true);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.percent_target, 0.0001);
}

test "Progress viewAs 0.0 has no filled cells" {
    const allocator = std.testing.allocator;
    var p = Progress.init();
    p.show_percent = false;
    p.width = 10;
    const bar = try p.viewAs(allocator, 0.0);
    defer allocator.free(bar);
    // All empty: visible width == 10 empty chars (SGR sequences have 0 width).
    const vis_w = ansi.strWidth(bar);
    try std.testing.expectEqual(@as(usize, 10), vis_w);
}

test "Progress viewAs 1.0 has all filled cells" {
    const allocator = std.testing.allocator;
    var p = Progress.init();
    p.show_percent = false;
    p.width = 10;
    const bar = try p.viewAs(allocator, 1.0);
    defer allocator.free(bar);
    const vis_w = ansi.strWidth(bar);
    try std.testing.expectEqual(@as(usize, 10), vis_w);
}

test "Progress viewAs solid colour path has correct width" {
    const allocator = std.testing.allocator;
    var p = Progress.init();
    p.use_gradient = false;
    p.show_percent = false;
    p.width = 10;
    const bar = try p.viewAs(allocator, 0.5);
    defer allocator.free(bar);
    try std.testing.expectEqual(@as(usize, 10), ansi.strWidth(bar));
}

test "Progress isAnimating false when at target" {
    var p = Progress.init();
    p.percent_shown = 0.5;
    p.percent_target = 0.5;
    p.velocity = 0.0;
    try std.testing.expect(!p.isAnimating());
}

test "Progress update rejects wrong id" {
    const TestMsg = union(enum) { progress_frame: FrameMsg };
    const p = Progress.init();
    const bad_msg = FrameMsg{ .id = p.id +% 1, .tag = 0 };
    const r = p.update(bad_msg, TestMsg);
    try std.testing.expect(r.cmd == null);
}
