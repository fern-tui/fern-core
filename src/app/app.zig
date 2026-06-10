// SPDX-License-Identifier: MIT

// Runtime, raw mode, and event loop.
// Note: Linux/macOS only. Windows throws a compile error.
//
// Threads:
// 1. Main (event loop)
// 2. Stdin reader (feeds parser)
// N. Ephemeral workers for async tasks
// (SIGWINCH is handled via a self-pipe, not a thread).

const std = @import("std");
const ansi = @import("fern_ansi");
const cmd = @import("cmd.zig");
const ren = @import("render.zig");
const sys = @import("sys.zig");

pub const Cmd = cmd.Cmd;
pub const Renderer = ren.Renderer;

const FPS_DEFAULT: u32 = 60;

// 16 ms poll timeout gives ~62 fps, close enough to FPS_DEFAULT.
const POLL_TIMEOUT_MS: i32 = 1000 / FPS_DEFAULT;

// Maximum bytes read from stdin per input-reader iteration.
const STDIN_READ_BUF: usize = 4096;

// Global signal pipe (write end).
// Required because sigaction doesn't take context. Initialized once in run().
// (Limits us to one App instance per process, which is fine).
var g_sig_pipe_w: std.posix.fd_t = -1;

// SIGWINCH handler (cross-platform signature).
// Must be async-signal-safe, hence the raw sys.write().
fn sigwinchHandler(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    const byte: [1]u8 = .{0};
    _ = sys.write(g_sig_pipe_w, byte[0..].ptr, 1);
}

// Handlers >>

/// The main app interface (init, update, view).
/// State = your model, MsgT = your event union.
pub fn Handlers(comptime State: type, comptime MsgT: type) type {
    return struct {
        /// Called once at startup. Returns the initial state AND an optional startup command.
        init: *const fn (alloc: std.mem.Allocator) anyerror!struct { State, ?Cmd(MsgT) },

        /// Called for every message.  Returns an optional Cmd (null == .none).
        update: *const fn (
            state: *State,
            msg: MsgT,
            alloc: std.mem.Allocator,
        ) anyerror!?Cmd(MsgT),

        /// Returns the rendered frame string for this state.
        /// The runtime frees the returned slice.
        view: *const fn (
            state: *const State,
            alloc: std.mem.Allocator,
        ) anyerror![]u8,
    };
}
// Thread-safe MPSC queue.
// We just use a dumb atomic spinlock here. The critical section is so short
// (< 1us) and contention is so low (< 4 workers) that a real OS mutex is overkill.
const MsgQueue = struct {

    // types

    /// Type-erased message.  Re-typed in the event loop.
    const AnyMsg = union(enum) {
        event: ansi.Event, // from input reader thread
        raw: *anyopaque, // from command worker threads (type-erased MsgT ptr)
    };

    // fields

    items: std.ArrayList(AnyMsg),
    locked: std.atomic.Value(bool),
    alloc: std.mem.Allocator,

    // lifecycle

    fn init(allocator: std.mem.Allocator) MsgQueue {
        return .{
            .items = .empty,
            .locked = std.atomic.Value(bool).init(false),
            .alloc = allocator,
        };
    }

    fn deinit(self: *MsgQueue) void {
        self.items.deinit(self.alloc);
    }

    // producers

    /// Push a parsed event from the input reader thread.
    fn pushEvent(self: *MsgQueue, ev: ansi.Event) error{OutOfMemory}!void {
        self.acquire();
        defer self.release();
        try self.items.append(self.alloc, .{ .event = ev });
    }

    /// Push a type-erased MsgT from a command worker thread.
    /// Caller heap-allocates a copy; the event loop casts and frees it.
    fn pushRaw(self: *MsgQueue, ptr: *anyopaque) error{OutOfMemory}!void {
        self.acquire();
        defer self.release();
        try self.items.append(self.alloc, .{ .raw = ptr });
    }

    // consumer

    /// Drain all pending messages.  Caller owns the returned slice.
    /// Returns an empty slice if nothing is pending.
    fn drainAll(self: *MsgQueue, allocator: std.mem.Allocator) error{OutOfMemory}![]AnyMsg {
        self.acquire();
        defer self.release();
        if (self.items.items.len == 0) return &[_]AnyMsg{};
        const copy = try allocator.dupe(AnyMsg, self.items.items);
        self.items.clearRetainingCapacity();
        return copy;
    }

    // spinlock

    fn acquire(self: *MsgQueue) void {
        while (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn release(self: *MsgQueue) void {
        self.locked.store(false, .release);
    }
};

// InputReaderThread -- reads raw bytes from stdin, feeds the ANSI parser
const InputReaderThread = struct {
    stdin_fd: std.posix.fd_t,
    cmd_pipe_w: std.posix.fd_t,
    queue: *MsgQueue,
    stop: *std.atomic.Value(bool),
    parser: ansi.Parser,
    alloc: std.mem.Allocator,
};

fn inputReaderFn(args: *InputReaderThread) void {
    var buf: [STDIN_READ_BUF]u8 = undefined;

    // Watch stdin for reading
    var fds: [1]std.posix.pollfd = .{
        .{ .fd = args.stdin_fd, .events = std.posix.POLL.IN, .revents = 0 },
    };

    while (!args.stop.load(.seq_cst)) {
        // Poll with a 50ms timeout to prevent deadlock during shutdown
        const ready = std.posix.poll(&fds, 50) catch 0;

        if (ready > 0 and (fds[0].revents & std.posix.POLL.IN != 0)) {
            const n = std.posix.read(args.stdin_fd, &buf) catch break;
            if (n == 0) break; // EOF

            var events: std.ArrayList(ansi.Event) = .empty;
            defer events.deinit(args.alloc);

            args.parser.feedAll(buf[0..n], &events, args.alloc) catch continue;

            for (events.items) |ev| {
                args.queue.pushEvent(ev) catch continue;
            }

            // Wake the event loop
            wakeLoop(args.cmd_pipe_w);
        }
    }
}

// CmdWorker -- runs a .task on a worker thread
fn CmdWorker(comptime MsgT: type) type {
    return struct {
        task_ctx: *anyopaque,
        task_run: *const fn (*anyopaque, std.mem.Allocator) anyerror!MsgT,
        queue: *MsgQueue,
        cmd_pipe_w: std.posix.fd_t,
        alloc: std.mem.Allocator,
        // Pointer to self so the worker can free its own allocation on exit.
        self_ptr: *@This(),

        fn run(self: *@This()) void {
            defer self.alloc.destroy(self.self_ptr);

            const result = self.task_run(self.task_ctx, self.alloc) catch return;

            // Heap-allocate a copy of MsgT for type-erased queue transfer.
            const heap_msg = self.alloc.create(MsgT) catch return;
            heap_msg.* = result;

            self.queue.pushRaw(@ptrCast(heap_msg)) catch {
                self.alloc.destroy(heap_msg);
                return;
            };

            wakeLoop(self.cmd_pipe_w);
        }
    };
}

// Wakes the main loop via the command pipe.
// Thread-safe and async-signal-safe (raw sys.write).
inline fn wakeLoop(pipe_w: std.posix.fd_t) void {
    const byte: [1]u8 = .{0};
    _ = sys.write(pipe_w, byte[0..].ptr, 1);
}

// Write accumulated renderer output to the terminal and reset the buffer.
// Must be called after every renderer.render() and renderer.moveToTop().
fn flushOut(out_aw: *std.Io.Writer.Allocating, fd: std.posix.fd_t) void {
    const data = out_aw.written();
    if (data.len == 0) return;
    _ = sys.write(fd, data.ptr, data.len);
    out_aw.clearRetainingCapacity();
}

// Main event loop. Blocks until Cmd.quit or a fatal error.
// Always cleans up and restores the terminal before returning.
pub fn run(
    comptime State: type,
    comptime MsgT: type,
    handlers: Handlers(State, MsgT),
    alloc: std.mem.Allocator,
) !void {
    // Comptime guard: MsgT must be a tagged union.
    comptime {
        if (@typeInfo(MsgT) != .@"union") @compileError("MsgT must be a tagged union");
    }

    const stdin_fd = std.posix.STDIN_FILENO;
    const stdout_fd = std.posix.STDOUT_FILENO;

    // signal pipe
    var sig_pipe: [2]std.posix.fd_t = undefined;
    try sys.initPipe(&sig_pipe);
    errdefer sys.closePipe(&sig_pipe);
    g_sig_pipe_w = sig_pipe[1];

    // command wakeup pipe
    var cmd_pipe: [2]std.posix.fd_t = undefined;
    try sys.initPipe(&cmd_pipe);
    errdefer sys.closePipe(&cmd_pipe);

    // raw terminal mode
    // Restore termios FIRST in cleanup so output-processing flags are back
    // in effect when we emit escape sequences during teardown.
    const orig_termios = try std.posix.tcgetattr(stdin_fd);
    errdefer std.posix.tcsetattr(stdin_fd, .FLUSH, orig_termios) catch {};
    try setRawMode(stdin_fd);

    // SIGWINCH handler
    var old_sa: std.posix.Sigaction = undefined;
    const new_sa: std.posix.Sigaction = .{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &new_sa, &old_sa);
    errdefer std.posix.sigaction(std.posix.SIG.WINCH, &old_sa, null);

    // message queue
    var queue = MsgQueue.init(alloc);
    defer queue.deinit();

    // initial terminal size
    var term_cols: u16 = 80;
    var term_rows: u16 = 24;
    sys.queryTerminalSize(stdout_fd, &term_cols, &term_rows);

    // renderer
    var out_aw: std.Io.Writer.Allocating = .init(alloc);
    defer out_aw.deinit();

    var renderer = Renderer.init(alloc, &out_aw.writer, term_cols, term_rows);
    defer renderer.deinit();

    // input reader thread
    var stop_flag = std.atomic.Value(bool).init(false);
    var reader_state = InputReaderThread{
        .stdin_fd = stdin_fd,
        .cmd_pipe_w = cmd_pipe[1],
        .queue = &queue,
        .stop = &stop_flag,
        .parser = ansi.Parser.init(),
        .alloc = alloc,
    };
    const reader_thread = try std.Thread.spawn(.{}, inputReaderFn, .{&reader_state});
    defer {
        stop_flag.store(true, .seq_cst);
        reader_thread.join();
    }

    // user init
    const init_result = try handlers.init(alloc);
    var state = init_result[0];
    const initial_cmd = init_result[1];

    // Dispatch startup commands (spawns initial worker/timer threads)
    _ = try dispatchCmd(MsgT, initial_cmd, &queue, cmd_pipe[1], alloc);

    // query sync output support (mode 2026)
    // Emit DECRQM (ESC[?2026$p); the ModeReport event arrives later via the parser.
    out_aw.writer.writeAll("\x1B[?2026$p") catch {};
    flushOut(&out_aw, stdout_fd);

    // event loop
    // v1 does not use the alternate screen.
    const using_alt_screen = false;

    try eventLoop(
        State,
        MsgT,
        &state,
        handlers,
        &renderer,
        &out_aw,
        &queue,
        sig_pipe[0],
        cmd_pipe[0],
        cmd_pipe[1],
        stdout_fd,
        using_alt_screen,
        alloc,
    );

    // terminal restore
    // Order (reverse of setup):
    //   1. Restore termios (re-enables OPOST so escape sequences render)
    //   2. Show cursor
    //   3. Disable mouse tracking
    //   4. Restore SIGWINCH handler
    //   5. Close pipes

    std.posix.tcsetattr(stdin_fd, .FLUSH, orig_termios) catch {};
    out_aw.writer.writeAll("\x1B[?25h") catch {}; // show cursor
    out_aw.writer.writeAll("\x1B[?1000l\x1B[?1006l") catch {}; // disable mouse
    flushOut(&out_aw, stdout_fd);

    std.posix.sigaction(std.posix.SIG.WINCH, &old_sa, null);
    sys.closePipe(&sig_pipe);
    sys.closePipe(&cmd_pipe);
}

// eventLoop -- inner loop, separated from run() for length discipline
fn eventLoop(
    comptime State: type,
    comptime MsgT: type,
    state: *State,
    handlers: Handlers(State, MsgT),
    renderer: *Renderer,
    out_aw: *std.Io.Writer.Allocating,
    queue: *MsgQueue,
    sig_pipe_r: std.posix.fd_t,
    cmd_pipe_r: std.posix.fd_t,
    cmd_pipe_w: std.posix.fd_t,
    stdout_fd: std.posix.fd_t,
    using_alt_screen: bool,
    alloc: std.mem.Allocator,
) !void {
    var fds: [2]std.posix.pollfd = .{
        .{ .fd = sig_pipe_r, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = cmd_pipe_r, .events = std.posix.POLL.IN, .revents = 0 },
    };

    // Force the first frame to render immediately on loop entry
    var should_render = true;

    loop: while (true) {
        // render (at TOP of loop so frame 0 works perfectly)
        if (should_render) {
            const frame = try handlers.view(state, alloc);
            defer alloc.free(frame);
            if (!using_alt_screen) try renderer.moveToTop();
            try renderer.render(frame);
            flushOut(out_aw, stdout_fd);
            should_render = false;
        }

        _ = std.posix.poll(&fds, POLL_TIMEOUT_MS) catch break;

        // SIGWINCH (resize)
        if (fds[0].revents & std.posix.POLL.IN != 0) {
            drainPipe(sig_pipe_r);
            try handleResize(MsgT, state, handlers, renderer, queue, cmd_pipe_w, stdout_fd, alloc);
            should_render = true;
        }

        // input / command wakeup
        if (fds[1].revents & std.posix.POLL.IN != 0) {
            drainPipe(cmd_pipe_r);
            const quit = try processQueue(MsgT, state, handlers, renderer, queue, cmd_pipe_w, alloc);
            if (quit) break :loop;
            should_render = true;
        }
    }
}

// handleResize -- SIGWINCH processing
fn handleResize(
    comptime MsgT: type,
    state: anytype,
    handlers: Handlers(@typeInfo(@TypeOf(state)).pointer.child, MsgT),
    renderer: *Renderer,
    queue: *MsgQueue,
    cmd_pipe_w: std.posix.fd_t,
    stdout_fd: std.posix.fd_t,
    alloc: std.mem.Allocator,
) !void {
    var new_cols: u16 = renderer.cols;
    var new_rows: u16 = renderer.rows;
    sys.queryTerminalSize(stdout_fd, &new_cols, &new_rows);
    renderer.resize(new_cols, new_rows);

    const resize_ev = ansi.Event{ .resize = .{ .cols = new_cols, .rows = new_rows } };
    if (tryWrapEvent(MsgT, resize_ev)) |m| {
        const result_cmd = try handlers.update(state, m, alloc);
        _ = try dispatchCmd(MsgT, result_cmd, queue, cmd_pipe_w, alloc);
    }
}

// Drains the message queue. Returns true on .quit.
fn processQueue(
    comptime MsgT: type,
    state: anytype,
    handlers: Handlers(@typeInfo(@TypeOf(state)).pointer.child, MsgT),
    renderer: *Renderer,
    queue: *MsgQueue,
    cmd_pipe_w: std.posix.fd_t,
    alloc: std.mem.Allocator,
) !bool {
    const pending = try queue.drainAll(alloc);
    defer alloc.free(pending);

    for (pending) |any| {
        switch (any) {
            // ModeReport is intercepted here before tryWrapEvent.
            // It is a runtime concern (synchronized output), not a user message.
            .event => |ev| switch (ev) {
                .mode_report => |mr| {
                    // Mode 2026 = synchronized output. Setting 2 = supported.
                    if (mr.mode == 2026 and mr.value == 2) {
                        renderer.setSyncMode(true);
                    }
                },
                else => {
                    if (tryWrapEvent(MsgT, ev)) |m| {
                        const result_cmd = try handlers.update(state, m, alloc);
                        if (try dispatchCmd(MsgT, result_cmd, queue, cmd_pipe_w, alloc))
                            return true;
                    }
                },
            },
            .raw => |ptr| {
                const typed: *MsgT = @ptrCast(@alignCast(ptr));
                defer alloc.destroy(typed);
                const result_cmd = try handlers.update(state, typed.*, alloc);
                if (try dispatchCmd(MsgT, result_cmd, queue, cmd_pipe_w, alloc))
                    return true;
            },
        }
    }
    return false;
}

// Comptime event dispatcher. Maps ansi.Events to MsgT where names/types match.
// Unmatched events return null and compile away to nothing.
fn tryWrapEvent(comptime MsgT: type, ev: ansi.Event) ?MsgT {
    const fields = @typeInfo(MsgT).@"union".fields;
    switch (ev) {
        .key => |k| {
            inline for (fields) |f| {
                if (comptime std.mem.eql(u8, f.name, "key") and f.type == ansi.KeyEvent)
                    return @unionInit(MsgT, "key", k);
            }
            return null;
        },
        .mouse => |m| {
            inline for (fields) |f| {
                if (comptime std.mem.eql(u8, f.name, "mouse") and f.type == ansi.MouseEvent)
                    return @unionInit(MsgT, "mouse", m);
            }
            return null;
        },
        .resize => |r| {
            inline for (fields) |f| {
                if (comptime std.mem.eql(u8, f.name, "resize") and f.type == ansi.ResizeEvent)
                    return @unionInit(MsgT, "resize", r);
            }
            return null;
        },
        .focus => |f_ev| {
            inline for (fields) |f| {
                if (comptime std.mem.eql(u8, f.name, "focus") and f.type == ansi.FocusEvent)
                    return @unionInit(MsgT, "focus", f_ev);
            }
            return null;
        },
        .paste => |p| {
            inline for (fields) |f| {
                if (comptime std.mem.eql(u8, f.name, "paste") and f.type == ansi.PasteEvent)
                    return @unionInit(MsgT, "paste", p);
            }
            return null;
        },
        // mode_report is handled by processQueue before reaching here.
        else => return null,
    }
}

// Executes a Cmd from the update loop. Returns true on .quit.
fn dispatchCmd(
    comptime MsgT: type,
    cmd_opt: ?Cmd(MsgT),
    queue: *MsgQueue,
    cmd_pipe_w: std.posix.fd_t,
    alloc: std.mem.Allocator,
) error{OutOfMemory}!bool {
    const c = cmd_opt orelse return false;

    switch (c) {
        .none => return false,
        .quit => return true,

        .batch => |cmds| {
            for (cmds) |sub| {
                if (try dispatchCmd(MsgT, sub, queue, cmd_pipe_w, alloc)) return true;
            }
            return false;
        },

        // v1: treats .sequence as concurrent (ordered delivery deferred to v2).
        .sequence => |cmds| {
            for (cmds) |sub| {
                if (try dispatchCmd(MsgT, sub, queue, cmd_pipe_w, alloc)) return true;
            }
            return false;
        },

        .task => |t| {
            try spawnWorker(MsgT, t.ctx, t.run, queue, cmd_pipe_w, alloc);
            return false;
        },

        .after => |a| {
            try spawnAfterThread(MsgT, a.ns, a.msg, queue, cmd_pipe_w, alloc);
            return false;
        },

        .every => |e| {
            try spawnEveryThread(MsgT, e.ns, e.id, e.gen, queue, cmd_pipe_w, alloc);
            return false;
        },
    }
}

// Spins up a background thread for a .task.
fn spawnWorker(
    comptime MsgT: type,
    task_ctx: *anyopaque,
    task_run: *const fn (*anyopaque, std.mem.Allocator) anyerror!MsgT,
    queue: *MsgQueue,
    cmd_pipe_w: std.posix.fd_t,
    alloc: std.mem.Allocator,
) error{OutOfMemory}!void {
    const Worker = CmdWorker(MsgT);
    const worker_ptr = try alloc.create(Worker);
    worker_ptr.* = .{
        .task_ctx = task_ctx,
        .task_run = task_run,
        .queue = queue,
        .cmd_pipe_w = cmd_pipe_w,
        .alloc = alloc,
        .self_ptr = worker_ptr,
    };
    const t_handle = std.Thread.spawn(.{}, Worker.run, .{worker_ptr}) catch {
        alloc.destroy(worker_ptr);
        return;
    };
    t_handle.detach();
}

// Async timeout worker. Sleeps for `ns` then pushes the event.
fn spawnAfterThread(
    comptime MsgT: type,
    ns: u64,
    msg_val: MsgT,
    queue: *MsgQueue,
    pipe_w: std.posix.fd_t,
    alloc: std.mem.Allocator,
) error{OutOfMemory}!void {
    const AfterCtx = struct {
        ns: u64,
        msg: MsgT,
        queue: *MsgQueue,
        pipe_w: std.posix.fd_t,
        worker_alloc: std.mem.Allocator,
    };

    const ctx_ptr = try alloc.create(AfterCtx);
    ctx_ptr.* = .{
        .ns = ns,
        .msg = msg_val,
        .queue = queue,
        .pipe_w = pipe_w,
        .worker_alloc = alloc,
    };

    const AfterThread = struct {
        fn run(ctx: *AfterCtx) void {
            defer ctx.worker_alloc.destroy(ctx);
            sys.threadSleep(ctx.ns);
            const heap_msg = ctx.worker_alloc.create(MsgT) catch return;
            heap_msg.* = ctx.msg;
            ctx.queue.pushRaw(@ptrCast(heap_msg)) catch {
                ctx.worker_alloc.destroy(heap_msg);
                return;
            };
            wakeLoop(ctx.pipe_w);
        }
    };

    const t_handle = std.Thread.spawn(.{}, AfterThread.run, .{ctx_ptr}) catch {
        alloc.destroy(ctx_ptr);
        return;
    };
    t_handle.detach();
}

// Interval tick worker.
// Fires a single delayed message. Needs to be explicitly re-queued
// by returning another .every from update() to form a continuous loop.
fn spawnEveryThread(
    comptime MsgT: type,
    ns: u64,
    id: u32,
    gen: *const fn (id: u32, now: i64) MsgT,
    queue: *MsgQueue,
    pipe_w: std.posix.fd_t,
    alloc: std.mem.Allocator,
) error{OutOfMemory}!void {
    const EveryCtx = struct {
        ns: u64,
        id: u32,
        gen: *const fn (id: u32, now: i64) MsgT,
        queue: *MsgQueue,
        pipe_w: std.posix.fd_t,
        worker_alloc: std.mem.Allocator,
    };

    const ctx_ptr = try alloc.create(EveryCtx);
    ctx_ptr.* = .{
        .ns = ns,
        .id = id,
        .gen = gen,
        .queue = queue,
        .pipe_w = pipe_w,
        .worker_alloc = alloc,
    };

    const EveryThread = struct {
        fn run(ctx: *EveryCtx) void {
            defer ctx.worker_alloc.destroy(ctx);
            sys.threadSleep(ctx.ns);
            const now = sys.nanoTimestamp();
            const msg_val = ctx.gen(ctx.id, now);
            const heap_msg = ctx.worker_alloc.create(MsgT) catch return;
            heap_msg.* = msg_val;
            ctx.queue.pushRaw(@ptrCast(heap_msg)) catch {
                ctx.worker_alloc.destroy(heap_msg);
                return;
            };
            wakeLoop(ctx.pipe_w);
        }
    };

    const t_handle = std.Thread.spawn(.{}, EveryThread.run, .{ctx_ptr}) catch {
        alloc.destroy(ctx_ptr);
        return;
    };
    t_handle.detach();
}

// Terminal helpers (private)

/// Enter raw (non-canonical, no-echo) terminal mode.
/// std.posix.tcgetattr / tcsetattr work on both Linux and macOS.
fn setRawMode(fd: std.posix.fd_t) !void {
    const orig = try std.posix.tcgetattr(fd);
    var raw = orig;

    // Input: disable break signal, CR-to-NL, parity, strip, XON/XOFF.
    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;

    // Output: disable post-processing.
    raw.oflag.OPOST = false;

    // Control: 8-bit characters.
    raw.cflag.CSIZE = .CS8;

    // Local: disable echo, canonical, extension, signal generation.
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;

    // VMIN=1: read() returns as soon as 1 byte is available.
    // VTIME=0: no timeout.
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(fd, .FLUSH, raw);
}

/// Read and discard all pending bytes from a pipe fd.
/// Used to clear wakeup bytes after poll() fires.
fn drainPipe(fd: std.posix.fd_t) void {
    var buf: [64]u8 = undefined;
    _ = std.posix.read(fd, &buf) catch {};
}

test "tryWrapEvent forwards key event when Msg has key variant" {
    const TestMsg = union(enum) { key: ansi.KeyEvent, other };
    const ev = ansi.Event{ .key = .{ .code = .{ .char = 'a' }, .mods = .{} } };
    const m = tryWrapEvent(TestMsg, ev);
    try std.testing.expect(m != null);
    try std.testing.expect(m.? == .key);
}

test "tryWrapEvent returns null when Msg lacks key variant" {
    const TestMsg = union(enum) { resize: ansi.ResizeEvent };
    const ev = ansi.Event{ .key = .{ .code = .{ .char = 'a' }, .mods = .{} } };
    try std.testing.expect(tryWrapEvent(TestMsg, ev) == null);
}

test "tryWrapEvent forwards resize event when Msg has resize variant" {
    const TestMsg = union(enum) { resize: ansi.ResizeEvent, other };
    const ev = ansi.Event{ .resize = .{ .cols = 80, .rows = 24 } };
    const m = tryWrapEvent(TestMsg, ev);
    try std.testing.expect(m != null);
    try std.testing.expect(m.? == .resize);
}

test "MsgQueue init starts empty" {
    const allocator = std.testing.allocator;
    var q = MsgQueue.init(allocator);
    defer q.deinit();

    const items = try q.drainAll(allocator);
    defer allocator.free(items);
    try std.testing.expectEqual(@as(usize, 0), items.len);
}

test "MsgQueue pushEvent and drainAll round-trip" {
    const allocator = std.testing.allocator;
    var q = MsgQueue.init(allocator);
    defer q.deinit();

    const ev = ansi.Event{ .key = .{ .code = .{ .char = 'z' }, .mods = .{} } };
    try q.pushEvent(ev);

    const items = try q.drainAll(allocator);
    defer allocator.free(items);

    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expect(items[0] == .event);
}

test "MsgQueue drainAll empties the queue" {
    const allocator = std.testing.allocator;
    var q = MsgQueue.init(allocator);
    defer q.deinit();

    const ev = ansi.Event{ .key = .{ .code = .enter, .mods = .{} } };
    try q.pushEvent(ev);
    try q.pushEvent(ev);

    const first = try q.drainAll(allocator);
    defer allocator.free(first);

    const second = try q.drainAll(allocator);
    defer allocator.free(second);

    try std.testing.expectEqual(@as(usize, 0), second.len);
}

test "dispatchCmd returns false for none" {
    const TestMsg = union(enum) { ok, other };
    const allocator = std.testing.allocator;
    var q = MsgQueue.init(allocator);
    defer q.deinit();

    const result = try dispatchCmd(TestMsg, null, &q, -1, allocator);
    try std.testing.expect(result == false);
}

test "dispatchCmd returns true for quit" {
    const TestMsg = union(enum) { ok, other };
    const allocator = std.testing.allocator;
    var q = MsgQueue.init(allocator);
    defer q.deinit();

    const result = try dispatchCmd(TestMsg, Cmd(TestMsg).quit, &q, -1, allocator);
    try std.testing.expect(result == true);
}

test "spinLoopHint does not hang" {
    std.atomic.spinLoopHint();
}

// Integration tests (require a real TTY; skipped when stdin is not a TTY).

test "setRawMode and restore leaves terminal unchanged on exit" {
    _ = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return;
    const orig = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    try setRawMode(std.posix.STDIN_FILENO);
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig);
}

test "queryTerminalSize returns nonzero cols and rows on a TTY" {
    _ = std.posix.tcgetattr(std.posix.STDOUT_FILENO) catch return;
    var cols: u16 = 0;
    var rows: u16 = 0;
    sys.queryTerminalSize(std.posix.STDOUT_FILENO, &cols, &rows);
    try std.testing.expect(cols > 0);
    try std.testing.expect(rows > 0);
}
