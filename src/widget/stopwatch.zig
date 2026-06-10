// SPDX-License-Identifier: MIT

// stopwatch:  Counts up from zero.
// Supports start, stop, toggle, and reset.
const std = @import("std");
const app = @import("fern_app");

// TickMsg is the only message the stopwatch emits.
// StartStopMsg and ResetMsg have been removed: start(), stop(), and reset()
// mutate the Stopwatch directly instead of routing through the message bus.
pub const TickMsg = struct {
    id: u32,
    tag: u32,
    now: i64,
};

var next_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub const Stopwatch = struct {
    id: u32,
    tag: u32 = 0,
    elapsed_ns: u64 = 0,
    interval_ns: u64 = std.time.ns_per_s,
    running: bool = false,

    // lifecycle

    pub fn init() Stopwatch {
        return .{ .id = next_id.fetchAdd(1, .monotonic) };
    }

    pub fn initInterval(interval_ns: u64) Stopwatch {
        return .{
            .id = next_id.fetchAdd(1, .monotonic),
            .interval_ns = interval_ns,
        };
    }

    // state queries

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

    // commands

    // Start the stopwatch and begin ticking.
    // Sets running = true immediately via direct mutation.
    // MsgT must have a `stopwatch_tick: TickMsg` variant.
    pub fn start(self: *Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        self.running = true;
        return self.tickCmd(MsgT);
    }

    // Stop the stopwatch.
    // Sets running = false immediately via direct mutation.
    pub fn stop(self: *Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        self.running = false;
        return .none;
    }

    // Toggle between running and stopped.
    pub fn toggle(self: *Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        return if (self.running_()) self.stop(MsgT) else self.start(MsgT);
    }

    // Reset elapsed time to zero.
    // No Cmd needed: direct mutation only.
    pub fn reset(self: *Stopwatch) void {
        self.elapsed_ns = 0;
    }

    fn tickCmd(self: *const Stopwatch, comptime MsgT: type) app.Cmd(MsgT) {
        // Pack id (low 16 bits) and tag (high 16 bits) into the u32
        // that the runtime echoes back as ev_id in gen().
        const packed_id: u32 = (self.id & 0xFFFF) |
            (@as(u32, self.tag & 0xFFFF) << 16);
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

    // Call this from your update() when a `stopwatch_tick` message arrives.
    // Returns the updated Stopwatch and the next tick Cmd.
    // Returns cmd = null when the tick is stale or the stopwatch is stopped.
    pub fn update(
        self: Stopwatch,
        msg: TickMsg,
        comptime MsgT: type,
    ) struct { sw: Stopwatch, cmd: ?app.Cmd(MsgT) } {
        if (!self.running or msg.id != self.id)
            return .{ .sw = self, .cmd = null };
        if (msg.tag != 0 and msg.tag != self.tag)
            return .{ .sw = self, .cmd = null };

        var sw = self;
        sw.elapsed_ns +%= sw.interval_ns;
        sw.tag +%= 1;
        return .{ .sw = sw, .cmd = sw.tickCmd(MsgT) };
    }

    // Render elapsed time as "Xs" or "XmYs".
    // buf must be at least 16 bytes.
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

test "Stopwatch init is stopped at zero" {
    const sw = Stopwatch.init();
    try std.testing.expect(!sw.running_());
    try std.testing.expectEqual(@as(u64, 0), sw.elapsedNs());
}

test "Stopwatch start sets running and returns tick cmd" {
    const TestMsg = union(enum) { stopwatch_tick: TickMsg };
    var sw = Stopwatch.init();
    const cmd = sw.start(TestMsg);
    try std.testing.expect(sw.running_());
    try std.testing.expect(cmd == .every);
}

test "Stopwatch stop sets running false and returns none" {
    const TestMsg = union(enum) { stopwatch_tick: TickMsg };
    var sw = Stopwatch.init();
    _ = sw.start(TestMsg);
    const cmd = sw.stop(TestMsg);
    try std.testing.expect(!sw.running_());
    try std.testing.expect(cmd == .none);
}

test "Stopwatch reset clears elapsed without a cmd" {
    var sw = Stopwatch.init();
    sw.elapsed_ns = 99 * std.time.ns_per_s;
    sw.reset();
    try std.testing.expectEqual(@as(u64, 0), sw.elapsedNs());
}

test "Stopwatch update increments elapsed when running" {
    const TestMsg = union(enum) { stopwatch_tick: TickMsg };
    var sw = Stopwatch.init();
    sw.running = true;
    const msg = TickMsg{ .id = sw.id, .tag = 0, .now = 0 };
    const r = sw.update(msg, TestMsg);
    try std.testing.expectEqual(sw.interval_ns, r.sw.elapsed_ns);
}

test "Stopwatch update rejects wrong id" {
    const TestMsg = union(enum) { stopwatch_tick: TickMsg };
    var sw = Stopwatch.init();
    sw.running = true;
    const msg = TickMsg{ .id = sw.id +% 1, .tag = 0, .now = 0 };
    const r = sw.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u64, 0), r.sw.elapsed_ns);
}

test "Stopwatch update rejects stale tag" {
    const TestMsg = union(enum) { stopwatch_tick: TickMsg };
    var sw = Stopwatch.init();
    sw.running = true;
    sw.tag = 5;
    const msg = TickMsg{ .id = sw.id, .tag = 3, .now = 0 };
    const r = sw.update(msg, TestMsg);
    try std.testing.expectEqual(@as(u64, 0), r.sw.elapsed_ns);
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
