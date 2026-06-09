// SPDX-License-Identifier: MIT

// animated progress bar. ticks 25% per second.
// uses spring easing and rgb gradients.
//
// zig build example-progress

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");

// Msg >>

const Msg = union(enum) {
    key: ansi.KeyEvent,
    progress_frame: widget.progress.FrameMsg,
    tick: void,
};

// State >>
// a progress bar and a done flag.

const State = struct {
    progress: widget.Progress,
    done: bool = false,
};

fn tickCmd() app.Cmd(Msg) {
    const TickGen = struct {
        fn gen(id: u32, now: i64) Msg {
            _ = id;
            _ = now;
            return Msg{ .tick = {} };
        }
    };
    return app.Cmd(Msg){ .every = .{
        .ns = std.time.ns_per_s,
        .id = 0,
        .gen = TickGen.gen,
    } };
}

// Styles >>

const TITLE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }); // white

const DIM_STYLE = style.Style.init()
    .fg_(.{ .ansi16 = .bright_black }); // dark

const DONE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0x04, .g = 0xB5, .b = 0x75 } }); // green

// Handlers

fn initState(alloc: std.mem.Allocator) !State {
    _ = alloc;
    var p = widget.Progress.init();
    p.setWidth(44);
    return .{ .progress = p };
}

fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;
    switch (msg) {
        .key => return .quit,

        .tick => {
            if (state.done) return null;
            const anim_cmd = state.progress.incrPercent(0.25, Msg);
            if (state.progress.percent_target >= 1.0) {
                state.done = true;
                return anim_cmd;
            }
            const cmds = [_]app.Cmd(Msg){ tickCmd(), anim_cmd };
            return app.batch(Msg, &cmds);
        },

        .progress_frame => |frame| {
            const r = state.progress.update(frame, Msg);
            state.progress = r.p;
            return r.cmd;
        },
    }
}

// set cursor position. terminal is 1-based so add 1 to internal 0-based coords.
fn appendPos(out: *std.ArrayList(u8), alloc: std.mem.Allocator, row: usize, col: usize) !void {
    var buf: [32]u8 = undefined;
    const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}H", .{ row + 1, col + 1 });
    try out.appendSlice(alloc, seq);
}

// get 0-based column offset to center text.
// clamps to 0 to avoid negative values on small terminals.
fn centerCol(term_cols: u16, visible_width: usize) usize {
    const tc: usize = @intCast(term_cols);
    if (visible_width >= tc) return 0;
    return (tc - visible_width) / 2;
}

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // Full clear + cursor home to avoids partial-line flicker.
    try out.appendSlice(alloc, "\x1B[2J\x1B[H");

    // Query live terminal size so centering adapts to any window.
    // Defaults (80x24) are used if the ioctl fails (e.g. piped output).
    var term_cols: u16 = 80;
    var term_rows: u16 = 24;
    app.queryTerminalSize(std.posix.STDOUT_FILENO, &term_cols, &term_rows);

    // Render each element so we can measure its visible width.
    const title = if (state.done)
        try DONE_STYLE.render(alloc, "> Download complete!")
    else
        try TITLE_STYLE.render(alloc, "> Downloading fern....");
    defer alloc.free(title);

    const bar = try state.progress.view(alloc);
    defer alloc.free(bar);

    const hint = try DIM_STYLE.render(alloc, "press any key to quit (Enter ↵)");
    defer alloc.free(hint);

    // Measure visible widths
    const bar_w = ansi.strWidth(bar);

    // 6 rows total:
    // 0: title (left aligned to bar)
    // 1: blank
    // 2: progress bar (centered)
    // 3-4: blank
    // 5: hint (offset slightly)
    const BLOCK_ROWS: usize = 6;
    const tr: usize = @intCast(term_rows);
    // Start row centres the block; clamp so it never goes negative.
    const start_row: usize = if (tr > BLOCK_ROWS) (tr - BLOCK_ROWS) / 2 else 0;

    // bar_col is the shared left-edge anchor for title and bar...
    const bar_col: usize = centerCol(term_cols, bar_w);

    // Title
    try appendPos(&out, alloc, start_row, bar_col);
    try out.appendSlice(alloc, title);

    // Progress bar
    try appendPos(&out, alloc, start_row + 2, bar_col);
    try out.appendSlice(alloc, bar);

    // Hint
    const hint_col: usize = bar_col + 8;
    try appendPos(&out, alloc, start_row + 5, hint_col);
    try out.appendSlice(alloc, hint);

    return out.toOwnedSlice(alloc);
}

// App wrapper >>

const AppState = struct {
    inner: State,

    fn appInit(alloc: std.mem.Allocator) !struct { AppState, ?app.Cmd(Msg) } {
        return .{ .{ .inner = try initState(alloc) }, tickCmd() };
    }

    fn appUpdate(self: *AppState, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
        return update(&self.inner, msg, alloc);
    }

    fn appView(self: *const AppState, alloc: std.mem.Allocator) ![]u8 {
        return view(&self.inner, alloc);
    }
};

pub fn main(init_ctx: std.process.Init) !void {
    // Enter alternate screen and hide cursor.
    try std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[?1049h\x1B[?25l");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    app.run(AppState, Msg, .{
        .init = AppState.appInit,
        .update = AppState.appUpdate,
        .view = AppState.appView,
    }, alloc) catch |err| {
        try std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[?1049l\x1B[?25h");
        return err;
    };

    // Leave alternate screen and restore cursor
    try std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[?1049l\x1B[?25h");
    std.process.exit(0);
}
