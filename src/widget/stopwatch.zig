// SPDX-License-Identifier: MIT

// stopwatch.zig - elapsed time stopwatch widget.
//
// stopwatch:  Counts up from zero.
// Supports start, stop, toggle, and reset.
//
// Imports: std, fern_app.

const std = @import("std");
const app = @import("fern_app");

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

pub const TickMsg = struct {
    id: u32,
    tag: u32,
    now: i64,
};

pub const StartStopMsg = struct {
    id: u32,
    running: bool,
};

pub const ResetMsg = struct { id: u32 };

// ---------------------------------------------------------------------------
// Stopwatch
// ---------------------------------------------------------------------------

var next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub const Stopwatch = struct {
    id: u32,
    tag: u32 = 0,
    elapsed_ns: u64 = 0,
    interval_ns: u64 = std.time.ns_per_s,
    running: bool = false,

    // --- lifecycle ----------------------------------------------------------

    pub fn init() Stopwatch {
        return .{ .id = next_id.fetchAdd(1, .monotonic) };
    }

    pub fn initInterval(interval_ns: u64) Stopwatch {
        return .{ .id = next_id.fetchAdd(1, .monotonic), .interval_ns = interval_ns };
    }

    // --- state queries ------------------------------------------------------

    pub fn running_(self: Stopwatch) bool {
        return self.running;
    }

    pub fn elapsedNs(self: Stopwatch) u64 {
        return self.elapsed_ns;
    }
    pub fn elapsedMs(self: Stopwatch) u64 {
        return self.elapsed_ns / std.time.ns_per_ms;
    }
    pub fn elapsedS(self: Stopwatch) u64 {
        return self.elapsed_ns / std.time.ns_per_s;
    }

    // --- commands -----------------------------------------------------------

    /// Start the stopwatch.  MsgT must have `stopwatch_tick`, `stopwatch_startstop`.
    pub fn start(self: *Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        // Send a StartStopMsg first (via .batch), then begin ticking.
        const ss_msg = @unionInit(MsgT, "stopwatch_startstop", StartStopMsg{
            .id = self.id,
            .running = true,
        });
        const cmds: [2]app.Cmd(MsgT) = .{
            .{ .after = .{ .ns = 0, .msg = ss_msg } },
            self.tickCmd(MsgT),
        };
        return app.Cmd(MsgT){ .batch = &cmds };
    }

    pub fn stop(self: Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        return app.Cmd(MsgT){ .after = .{
            .ns = 0,
            .msg = @unionInit(MsgT, "stopwatch_startstop", StartStopMsg{
                .id = self.id,
                .running = false,
            }),
        } };
    }

    pub fn toggle(self: *Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        return if (self.running_()) self.stop(MsgT) else self.start(MsgT);
    }

    pub fn reset(self: Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        return app.Cmd(MsgT){ .after = .{
            .ns = 0,
            .msg = @unionInit(MsgT, "stopwatch_reset", ResetMsg{ .id = self.id }),
        } };
    }

    fn tickCmd(self: *const Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        // Pack both id (low 16 bits) and tag (high 16 bits) into the u32
        // that the runtime echoes back as ev_id in gen().
        const packed_id: u32 = (self.id & 0xFFFF) | (@as(u32, self.tag & 0xFFFF) << 16);
        const ns = self.interval_ns;
        const Gen = struct {
            fn gen(ev_id: u32, now: i64) MsgT {
                return @unionInit(MsgT, "stopwatch_tick", TickMsg{
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

    pub fn update(
        self: Stopwatch,
        msg: TickMsg,
        comptime MsgT: type,
    ) struct { sw: Stopwatch, cmd: ?app.Cmd(MsgT) } {
        if (!self.running or msg.id != self.id) return .{ .sw = self, .cmd = null };
        if (msg.tag != 0 and msg.tag != self.tag) return .{ .sw = self, .cmd = null };

        var sw = self;
        sw.elapsed_ns +%= sw.interval_ns;
        sw.tag +%= 1;
        return .{ .sw = sw, .cmd = sw.tickCmd(MsgT) };
    }

    pub fn updateStartStop(self: Stopwatch, msg: StartStopMsg) Stopwatch {
        if (msg.id != self.id) return self;
        var sw = self;
        sw.running = msg.running;
        return sw;
    }

    pub fn updateReset(self: Stopwatch, msg: ResetMsg) Stopwatch {
        if (msg.id != self.id) return self;
        var sw = self;
        sw.elapsed_ns = 0;
        return sw;
    }

    // --- view ---------------------------------------------------------------

    /// Render elapsed time as "Xs" or "XmYs".
    pub fn view(self: Stopwatch, buf: []u8) []const u8 {
        const total_s = self.elapsedS();
        if (total_s < 60) {
            return std.fmt.bufPrint(buf, "{d}s", .{total_s}) catch "?s";
        }
        const mins = total_s / 60;
        const secs = total_s % 60;
        return std.fmt.bufPrint(buf, "{d}m{d}s", .{ mins, secs }) catch "?m?s";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Stopwatch init is stopped at zero" {
    const sw = Stopwatch.init();
    try std.testing.expect(!sw.running_());
    try std.testing.expectEqual(@as(u64, 0), sw.elapsedNs());
}

test "Stopwatch update increments elapsed when running" {
    const TestMsg = union(enum) {
        stopwatch_tick: TickMsg,
        stopwatch_startstop: StartStopMsg,
        stopwatch_reset: ResetMsg,
    };
    var sw = Stopwatch.init();
    sw.running = true;
    const msg = TickMsg{ .id = sw.id, .tag = 0, .now = 0 };
    const r = sw.update(msg, TestMsg);
    try std.testing.expectEqual(sw.interval_ns, r.sw.elapsed_ns);
}

test "Stopwatch update rejects wrong id" {
    const TestMsg = union(enum) {
        stopwatch_tick: TickMsg,
        stopwatch_startstop: StartStopMsg,
        stopwatch_reset: ResetMsg,
    };
    var sw = Stopwatch.init();
    sw.running = true;
    const msg = TickMsg{ .id = sw.id +% 1, .tag = 0, .now = 0 };
    const r = sw.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u64, 0), r.sw.elapsed_ns);
}

test "Stopwatch updateReset clears elapsed" {
    var sw = Stopwatch.init();
    sw.elapsed_ns = 12345;
    sw = sw.updateReset(ResetMsg{ .id = sw.id });
    try std.testing.expectEqual(@as(u64, 0), sw.elapsed_ns);
}

test "Stopwatch view formats seconds" {
    var sw = Stopwatch.init();
    sw.elapsed_ns = 42 * std.time.ns_per_s;
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("42s", sw.view(&buf));
}

test "Stopwatch view formats minutes" {
    var sw = Stopwatch.init();
    sw.elapsed_ns = 125 * std.time.ns_per_s;
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("2m5s", sw.view(&buf));
}
