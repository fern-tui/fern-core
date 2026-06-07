// SPDX-License-Identifier: MIT

// spinner.zig - animated spinner widget.
//
// spinner:  Uses fern's Cmd(.every) for ticking.
// The caller routes TickMsg back into update() to advance frames.
//
// Imports: std, fern_ansi, fern_style, fern_app (Cmd, TickMsg).

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");

// ---------------------------------------------------------------------------
// Spinner presets (mirrors bubbles exactly)
// ---------------------------------------------------------------------------

pub const Preset = struct {
    frames: []const []const u8,
    /// Tick interval in nanoseconds.
    interval_ns: u64,
};

pub const LINE: Preset = .{
    .frames = &.{ "|", "/", "-", "\\" },
    .interval_ns = std.time.ns_per_s / 10,
};

pub const DOT: Preset = .{
    .frames = &.{ "\xe2\xa3\xbe ", "\xe2\xa3\xbd ", "\xe2\xa3\xbb ", "\xe2\xa2\xbf ", "\xe2\xa1\xbf ", "\xe2\xa3\x9f ", "\xe2\xa3\xaf ", "\xe2\xa3\xb7 " },
    .interval_ns = std.time.ns_per_s / 10,
};

pub const MINI_DOT: Preset = .{
    .frames = &.{ "\xe2\xa0\x8b", "\xe2\xa0\x99", "\xe2\xa0\xb9", "\xe2\xa0\xb8", "\xe2\xa0\xbc", "\xe2\xa0\xb4", "\xe2\xa0\xa6", "\xe2\xa0\xa7", "\xe2\xa0\x87", "\xe2\xa0\x8f" },
    .interval_ns = std.time.ns_per_s / 12,
};

pub const JUMP: Preset = .{
    .frames = &.{ "\xe2\xa2\x84", "\xe2\xa2\x82", "\xe2\xa2\x81", "\xe2\xa1\x81", "\xe2\xa1\x88", "\xe2\xa1\x90", "\xe2\xa1\xa0" },
    .interval_ns = std.time.ns_per_s / 10,
};

pub const PULSE: Preset = .{
    .frames = &.{ "\xe2\x96\x88", "\xe2\x96\x93", "\xe2\x96\x92", "\xe2\x96\x91" },
    .interval_ns = std.time.ns_per_s / 8,
};

pub const POINTS: Preset = .{
    .frames = &.{ "\xe2\x88\x99\xe2\x88\x99\xe2\x88\x99", "\xe2\x97\x8f\xe2\x88\x99\xe2\x88\x99", "\xe2\x88\x99\xe2\x97\x8f\xe2\x88\x99", "\xe2\x88\x99\xe2\x88\x99\xe2\x97\x8f" },
    .interval_ns = std.time.ns_per_s / 7,
};

pub const METER: Preset = .{
    .frames = &.{ "\xe2\x96\xb1\xe2\x96\xb1\xe2\x96\xb1", "\xe2\x96\xb0\xe2\x96\xb1\xe2\x96\xb1", "\xe2\x96\xb0\xe2\x96\xb0\xe2\x96\xb1", "\xe2\x96\xb0\xe2\x96\xb0\xe2\x96\xb0", "\xe2\x96\xb0\xe2\x96\xb0\xe2\x96\xb1", "\xe2\x96\xb0\xe2\x96\xb1\xe2\x96\xb1", "\xe2\x96\xb1\xe2\x96\xb1\xe2\x96\xb1" },
    .interval_ns = std.time.ns_per_s / 7,
};

pub const ELLIPSIS: Preset = .{
    .frames = &.{ "", ".", "..", "..." },
    .interval_ns = std.time.ns_per_s / 3,
};

// ---------------------------------------------------------------------------
// TickMsg -- routed back to update() each tick
// ---------------------------------------------------------------------------

/// The message the runtime sends on each spinner tick.
/// id must match the spinner's own id; tag must match to guard against stale ticks.
pub const TickMsg = struct {
    id: u32,
    tag: u32,
    now: i64,
};

// ---------------------------------------------------------------------------
// Spinner
// ---------------------------------------------------------------------------

/// Monotonically incrementing global ID counter.
var next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub const Spinner = struct {
    preset: Preset = LINE,
    style_: style.Style = style.Style.init(),
    frame: u32 = 0,
    id: u32 = 0,
    tag: u32 = 0,

    // --- lifecycle ----------------------------------------------------------

    pub fn init() Spinner {
        return .{ .id = next_id.fetchAdd(1, .monotonic) };
    }

    pub fn initPreset(p: Preset) Spinner {
        return .{ .preset = p, .id = next_id.fetchAdd(1, .monotonic) };
    }

    // --- setters ------------------------------------------------------------

    pub fn setPreset(self: *Spinner, p: Preset) void {
        self.preset = p;
    }
    pub fn setStyle(self: *Spinner, s: style.Style) void {
        self.style_ = s;
    }

    // --- tick command -------------------------------------------------------

    /// Returns a Cmd that fires a TickMsg after one interval.
    /// MsgT must have a field `spinner_tick: TickMsg`.
    pub fn tick(self: *Spinner, comptime MsgT: type) app.Cmd(MsgT) {
        const packed_id: u32 = (self.id & 0xFFFF) | (@as(u32, self.tag & 0xFFFF) << 16);
        const ns = self.preset.interval_ns;
        const Gen = struct {
            fn gen(ev_id: u32, now: i64) MsgT {
                return @unionInit(MsgT, "spinner_tick", TickMsg{
                    .id = ev_id & 0xFFFF,
                    .tag = (ev_id >> 16) & 0xFFFF,
                    .now = now,
                });
            }
        };
        return app.Cmd(MsgT){ .every = .{
            .ns = ns,
            .id = packed_id,
            .gen = Gen.gen,
        } };
    }

    // --- update -------------------------------------------------------------

    /// Handle a TickMsg.  Returns the updated spinner and an optional
    /// next-tick Cmd (null when the tick was rejected due to id/tag mismatch).
    pub fn update(
        self: Spinner,
        msg: TickMsg,
        comptime MsgT: type,
    ) struct { s: Spinner, cmd: ?app.Cmd(MsgT) } {
        if (msg.id != self.id or msg.tag != self.tag) {
            return .{ .s = self, .cmd = null };
        }
        var s = self;
        s.frame = (s.frame + 1) % @as(u32, @intCast(s.preset.frames.len));
        s.tag +%= 1;
        return .{ .s = s, .cmd = s.tick(MsgT) };
    }

    // --- view ---------------------------------------------------------------

    /// Render the current frame, applying the spinner's style.
    /// Caller owns the returned slice; free with allocator.free().
    pub fn view(self: Spinner, allocator: std.mem.Allocator) ![]u8 {
        if (self.frame >= self.preset.frames.len) return allocator.dupe(u8, "");
        const frame_str = self.preset.frames[self.frame];
        return self.style_.render(allocator, frame_str);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Spinner init has frame 0" {
    const s = Spinner.init();
    try std.testing.expectEqual(@as(u32, 0), s.frame);
}

test "Spinner view returns first frame of LINE" {
    const allocator = std.testing.allocator;
    const s = Spinner.initPreset(LINE);
    const v = try s.view(allocator);
    defer allocator.free(v);
    try std.testing.expectEqualStrings(LINE.frames[0], v);
}

test "Spinner update with wrong id is rejected" {
    const s = Spinner.init();
    const msg = TickMsg{ .id = s.id +% 1, .tag = 0, .now = 0 };
    const TestMsg = union(enum) { spinner_tick: TickMsg };
    const r = s.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u32, 0), r.s.frame);
    try std.testing.expect(r.cmd == null);
}

test "Spinner update with correct id advances frame" {
    var s = Spinner.initPreset(LINE);
    const msg = TickMsg{ .id = s.id, .tag = s.tag, .now = 0 };
    const TestMsg = union(enum) { spinner_tick: TickMsg };
    const r = s.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u32, 1), r.s.frame);
    try std.testing.expect(r.cmd != null);
}

test "Spinner frame wraps at end of preset" {
    const TestMsg = union(enum) { spinner_tick: TickMsg };
    var s = Spinner.initPreset(LINE);
    // Advance to last frame.
    s.frame = @as(u32, @intCast(LINE.frames.len)) - 1;
    s.tag = 0;
    const msg = TickMsg{ .id = s.id, .tag = 0, .now = 0 };
    const r = s.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u32, 0), r.s.frame);
}
