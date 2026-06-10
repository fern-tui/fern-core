// SPDX-License-Identifier: MIT

// timer:  Counts down from a timeout duration.
// Uses Cmd(.every) to tick.  Emits TimeoutMsg when the timer reaches zero.

const std = @import("std");
const app = @import("fern_app");

pub const TickMsg = struct {
    id: u32,
    tag: u32,
    timeout: bool, // true on the final tick
    now: i64,
};

pub const TimeoutMsg = struct { id: u32 };

pub const StartStopMsg = struct {
    id: u32,
    running: bool,
};

// Timer
var next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub const Timer = struct {
    id: u32,
    tag: u32 = 0,
    timeout_ns: i64, // remaining nanoseconds; counts down to 0
    interval_ns: u64 = std.time.ns_per_s,
    running: bool = true,

    // lifecycle
    pub fn init(timeout_ns: u64) Timer {
        return .{
            .id = next_id.fetchAdd(1, .monotonic),
            .timeout_ns = @intCast(timeout_ns),
        };
    }

    pub fn initMs(timeout_ms: u64) Timer {
        return init(timeout_ms * std.time.ns_per_ms);
    }

    pub fn initS(timeout_s: u64) Timer {
        return init(timeout_s * std.time.ns_per_s);
    }

    // state queries
    pub fn timedOut(self: Timer) bool {
        return self.timeout_ns <= 0;
    }

    pub fn running_(self: Timer) bool {
        return self.running and !self.timedOut();
    }

    // commands
    /// Initial command to start the timer ticking.
    /// MsgT must have fields `timer_tick: TickMsg` and `timer_timeout: TimeoutMsg`.
    pub fn start(self: *Timer, comptime MsgT: type) app.Cmd(MsgT) {
        return self.tickCmd(MsgT);
    }

    pub fn stop(self: Timer, comptime MsgT: type) app.Cmd(MsgT) {
        return app.Cmd(MsgT){ .after = .{
            .ns = 0,
            .msg = @unionInit(MsgT, "timer_startstop", StartStopMsg{
                .id = self.id,
                .running = false,
            }),
        } };
    }

    pub fn toggle(self: *Timer, comptime MsgT: type) app.Cmd(MsgT) {
        return if (self.running_())
            self.stop(MsgT)
        else
            self.start(MsgT);
    }

    fn tickCmd(self: *const Timer, comptime MsgT: type) app.Cmd(MsgT) {
        // Bit layout of packed_id (u32):
        //   bits  0-15: widget id
        //   bits 16-30: tag
        //   bit     31: timed_out flag
        const timed_out_bit: u32 = if (self.timedOut()) 0x80000000 else 0;
        const packed_id: u32 = (self.id & 0xFFFF) |
            (@as(u32, self.tag & 0x7FFF) << 16) |
            timed_out_bit;
        const ns = self.interval_ns;
        const Gen = struct {
            fn gen(ev_id: u32, now: i64) MsgT {
                return @unionInit(MsgT, "timer_tick", TickMsg{
                    .id = ev_id & 0xFFFF,
                    .tag = (ev_id >> 16) & 0x7FFF,
                    .timeout = (ev_id & 0x80000000) != 0,
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

    pub fn update(
        self: Timer,
        msg: TickMsg,
        comptime MsgT: type,
    ) struct { t: Timer, cmd: ?app.Cmd(MsgT) } {
        if (!self.running_()) return .{ .t = self, .cmd = null };
        if (msg.id != self.id) return .{ .t = self, .cmd = null };
        if (msg.tag != 0 and msg.tag != self.tag) return .{ .t = self, .cmd = null };

        var t = self;
        t.timeout_ns -= @intCast(t.interval_ns);
        // Clamp to 0; do not go negative.
        if (t.timeout_ns < 0) t.timeout_ns = 0;
        t.tag +%= 1;
        return .{ .t = t, .cmd = t.tickCmd(MsgT) };
    }

    pub fn updateStartStop(self: Timer, msg: StartStopMsg) Timer {
        if (msg.id != self.id) return self;
        var t = self;
        t.running = msg.running;
        return t;
    }

    /// Render remaining time as "Xs" (e.g. "10s", "500ms").
    pub fn view(self: Timer, buf: []u8) []const u8 {
        if (self.timeout_ns <= 0) return "0s";
        const ns: u64 = @intCast(self.timeout_ns);
        if (ns >= std.time.ns_per_s) {
            const secs = ns / std.time.ns_per_s;
            return std.fmt.bufPrint(buf, "{d}s", .{secs}) catch "?s";
        }
        const ms = ns / std.time.ns_per_ms;
        return std.fmt.bufPrint(buf, "{d}ms", .{ms}) catch "?ms";
    }
};

test "Timer init not timed out" {
    const t = Timer.initS(10);
    try std.testing.expect(!t.timedOut());
    try std.testing.expect(t.running_());
}

test "Timer update decrements timeout" {
    const TestMsg = union(enum) { timer_tick: TickMsg, timer_timeout: TimeoutMsg, timer_startstop: StartStopMsg };
    var t = Timer.initS(5);
    const msg = TickMsg{ .id = t.id, .tag = t.tag, .timeout = false, .now = 0 };
    const r = t.update(msg, TestMsg);
    try std.testing.expectEqual(
        @as(i64, 4 * std.time.ns_per_s),
        r.t.timeout_ns,
    );
}

test "Timer update rejects wrong id" {
    const TestMsg = union(enum) { timer_tick: TickMsg, timer_timeout: TimeoutMsg, timer_startstop: StartStopMsg };
    const t = Timer.initS(5);
    const msg = TickMsg{ .id = t.id +% 1, .tag = 0, .timeout = false, .now = 0 };
    const r = t.update(msg, TestMsg);
    try std.testing.expectEqual(
        @as(i64, 5 * std.time.ns_per_s),
        r.t.timeout_ns,
    );
}

test "Timer timedOut true when timeout_ns <= 0" {
    var t = Timer.initS(1);
    t.timeout_ns = 0;
    try std.testing.expect(t.timedOut());
    try std.testing.expect(!t.running_());
}

test "Timer view formats seconds" {
    const t = Timer.initS(10);
    var buf: [32]u8 = undefined;
    const s = t.view(&buf);
    try std.testing.expectEqualStrings("10s", s);
}
