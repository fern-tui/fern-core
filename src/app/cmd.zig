// SPDX-License-Identifier: MIT

// cmd.zig - Cmd(MsgT): side-effect descriptor for the TEA runtime.
//
// Imports: std only.
// No heap allocation anywhere in this file.

const std = @import("std");

// ---------------------------------------------------------------------------
// Cmd(MsgT)
// ---------------------------------------------------------------------------

/// The return type of update().  Describes a side effect the runtime will
/// execute on the caller's behalf.  All variants except .task are zero-copy.
pub fn Cmd(comptime MsgT: type) type {
    return union(enum) {
        // No operation.  Returning null from update() is equivalent.
        none,

        // Ask the runtime to call shutdown() and exit run().
        quit,

        // Run multiple Cmds concurrently.  Results arrive in any order.
        // Caller owns the slice; the runtime does not copy or free it.
        batch: []const Cmd(MsgT),

        // Run multiple Cmds sequentially.  In v1 the runtime treats this
        // identically to .batch (concurrent execution with unordered results).
        // Sequential guarantees are deferred to v2.
        sequence: []const Cmd(MsgT),

        // Run a function on a worker thread.  The result Msg is pushed to
        // the event queue when the function returns.
        // ctx is a type-erased pointer to caller-managed state.
        // run must be safe to call from any thread.
        task: struct {
            ctx: *anyopaque,
            run: *const fn (ctx: *anyopaque, alloc: std.mem.Allocator) anyerror!MsgT,
        },

        // Send msg after ns nanoseconds (worker thread sleeps, then pushes).
        after: struct {
            ns: u64,
            msg: MsgT,
        },

        // Send a generated msg every ns nanoseconds.
        // The user returns another .every from update() to continue ticking.
        every: struct {
            ns: u64,
            id: u32,
            gen: *const fn (id: u32, now: i64) MsgT,
        },
    };
}

// ---------------------------------------------------------------------------
// TickMsg — recommended payload for .every and .after
// ---------------------------------------------------------------------------

/// Suggested Msg variant for timer payloads.
/// Include this as a field in your application's Msg union.
pub const TickMsg = struct {
    id: u32,
    time: i64, // std.time.nanoTimestamp()
};

// ---------------------------------------------------------------------------
// Convenience constructors
// ---------------------------------------------------------------------------

/// Return a .none Cmd.
pub fn none(comptime MsgT: type) Cmd(MsgT) {
    return .none;
}

/// Return a .quit Cmd.
pub fn quit(comptime MsgT: type) Cmd(MsgT) {
    return .quit;
}

/// Combine cmds for concurrent dispatch.
/// Empty slices and all-.none slices become .none.
/// A single real (non-.none) cmd passes through without wrapping.
pub fn batch(comptime MsgT: type, cmds: []const Cmd(MsgT)) Cmd(MsgT) {
    var real_count: usize = 0;
    var last_real: Cmd(MsgT) = .none;
    for (cmds) |c| {
        if (c != .none) {
            real_count += 1;
            last_real = c;
        }
    }
    if (real_count == 0) return .none;
    if (real_count == 1) return last_real;
    return .{ .batch = cmds };
}

/// Combine cmds to run in order (v1: treated as concurrent).
pub fn sequence(comptime MsgT: type, cmds: []const Cmd(MsgT)) Cmd(MsgT) {
    var real_count: usize = 0;
    var last_real: Cmd(MsgT) = .none;
    for (cmds) |c| {
        if (c != .none) {
            real_count += 1;
            last_real = c;
        }
    }
    if (real_count == 0) return .none;
    if (real_count == 1) return last_real;
    return .{ .sequence = cmds };
}

/// Wrap a typed function pointer into a type-erased .task Cmd.
/// T is the concrete type of the state pointed to by ctx_ptr.
/// run_fn has signature: fn (state: *T, alloc: Allocator) anyerror!MsgT
pub fn task(
    comptime MsgT: type,
    comptime T: type,
    ctx_ptr: *T,
    comptime run_fn: fn (ctx: *T, alloc: std.mem.Allocator) anyerror!MsgT,
) Cmd(MsgT) {
    const Wrapper = struct {
        fn run(ctx: *anyopaque, alloc: std.mem.Allocator) anyerror!MsgT {
            return run_fn(@ptrCast(@alignCast(ctx)), alloc);
        }
    };
    return .{ .task = .{
        .ctx = @ptrCast(ctx_ptr),
        .run = Wrapper.run,
    } };
}

/// Send msg after ns nanoseconds.
pub fn after(comptime MsgT: type, ns: u64, msg: MsgT) Cmd(MsgT) {
    return .{ .after = .{ .ns = ns, .msg = msg } };
}

/// Send a generated msg every ns nanoseconds.
/// id is caller-assigned; use per-component counters to distinguish ticks.
pub fn every(
    comptime MsgT: type,
    ns: u64,
    id: u32,
    comptime gen: fn (id: u32, now: i64) MsgT,
) Cmd(MsgT) {
    return .{ .every = .{ .ns = ns, .id = id, .gen = gen } };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Cmd none variant equals .none" {
    const TestMsg = union(enum) { ok, other };
    const c = Cmd(TestMsg).none;
    try std.testing.expect(c == .none);
}

test "quit helper returns quit variant" {
    const TestMsg = union(enum) { ok, other };
    const c = quit(TestMsg);
    try std.testing.expect(c == .quit);
}

test "batch with empty slice returns none" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){};
    try std.testing.expect(batch(TestMsg, &cmds) == .none);
}

test "batch with all-none slice returns none" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){ .none, .none };
    try std.testing.expect(batch(TestMsg, &cmds) == .none);
}

test "batch with one real cmd returns that cmd" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){.quit};
    try std.testing.expect(batch(TestMsg, &cmds) == .quit);
}

test "batch with one real and one none returns the real cmd" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){ .none, .quit };
    try std.testing.expect(batch(TestMsg, &cmds) == .quit);
}

test "batch with two real cmds returns batch variant" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){ .quit, .quit };
    const c = batch(TestMsg, &cmds);
    try std.testing.expect(c == .batch);
}

test "sequence with empty slice returns none" {
    const TestMsg = union(enum) { ok, other };
    const cmds = [_]Cmd(TestMsg){};
    try std.testing.expect(sequence(TestMsg, &cmds) == .none);
}

test "after carries ns and msg" {
    const TestMsg = union(enum) { ok, other };
    const c = after(TestMsg, 1_000_000, TestMsg.ok);
    try std.testing.expect(c == .after);
    try std.testing.expectEqual(@as(u64, 1_000_000), c.after.ns);
}

test "every carries ns, id, and gen pointer" {
    const TestMsg = union(enum) { tick: TickMsg, other };
    const Gen = struct {
        fn gen(id: u32, now: i64) TestMsg {
            return .{ .tick = .{ .id = id, .time = now } };
        }
    };
    const c = every(TestMsg, 16_666_666, 42, Gen.gen);
    try std.testing.expect(c == .every);
    try std.testing.expectEqual(@as(u64, 16_666_666), c.every.ns);
    try std.testing.expectEqual(@as(u32, 42), c.every.id);
}

test "task wraps ctx pointer and erases type" {
    const TestMsg = union(enum) { ok: u32, other };
    var counter: u32 = 0;
    const TaskFn = struct {
        fn run(ctx: *u32, alloc: std.mem.Allocator) anyerror!TestMsg {
            _ = alloc;
            return .{ .ok = ctx.* };
        }
    };
    const c = task(TestMsg, u32, &counter, TaskFn.run);
    try std.testing.expect(c == .task);
}
