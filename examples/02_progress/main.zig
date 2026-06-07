// SPDX-License-Identifier: MIT

// examples/02_progress/main.zig
//
// Animated progress bar. Increments 25% per second via a tick command.
// Spring-based easing + per-cell RGB gradient because plain bars are sad.
//
// zig build example-progress

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");

// ---------------------------------------------------------------------------
// Msg
// ---------------------------------------------------------------------------
// three variants. the universe expanded by one since last time.

const Msg = union(enum) {
    key: ansi.KeyEvent,
    progress_frame: widget.progress.FrameMsg,
    tick: void, // fires every second to bump the percent
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
// a progress bar and a done flag. the whole plot.

const State = struct {
    progress: widget.Progress,
    done: bool = false,
};

// ---------------------------------------------------------------------------
// Tick command -- fires after 1 second, produces Msg.tick
// ---------------------------------------------------------------------------
// a timer that knocks on the door every second and says "psst. increment."

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

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------
// three colors. a complete emotional journey.

const TITLE_STYLE = style.Style.init()
    .bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }); // white: hope

const DIM_STYLE = style.Style.init()
    .fg_(.{ .ansi16 = .bright_black }); // dark: apathy

const DONE_STYLE = style.Style.init()
    .bold_(true)
    .fg_(.{ .rgb = .{ .r = 0x04, .g = 0xB5, .b = 0x75 } }); // green: relief

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// alloc ghosts us again. wider bar gives the gradient room to breathe.
fn initState(alloc: std.mem.Allocator) !State {
    _ = alloc;
    var p = widget.Progress.init();
    // Wider bar gives the gradient more room to breathe.
    p.setWidth(44);
    return .{ .progress = p };
}

fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;
    switch (msg) {
        .key => return .quit,

        .tick => {
            if (state.done) return null; // already finished. stop knocking.
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

// Append the CSI absolute-position sequence ESC[row;colH (1-based).
// row and col are 0-based internally; we add 1 before writing.
fn appendPos(out: *std.ArrayList(u8), alloc: std.mem.Allocator, row: usize, col: usize) !void {
    var buf: [32]u8 = undefined;
    const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}H", .{ row + 1, col + 1 });
    try out.appendSlice(alloc, seq);
}

// Return the column offset (0-based) that centers a string of visible_width
// cells inside a terminal that is term_cols wide.
// Clamps to 0 so we never return a negative value on tiny terminals.
fn centerCol(term_cols: u16, visible_width: usize) usize {
    const tc: usize = @intCast(term_cols);
    if (visible_width >= tc) return 0;
    return (tc - visible_width) / 2;
}

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // Full clear + cursor home -- avoids partial-line flicker.
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

    // Measure visible widths (ANSI escapes are skipped by strWidth).
    const bar_w = ansi.strWidth(bar);

    // The block is 6 visible rows tall:
    //   row 0  title          (left-aligned to bar's left edge)
    //   row 1  (blank)
    //   row 2  progress bar   (horizontally centred)
    //   row 3  (blank)
    //   row 4  (blank)
    //   row 5  hint           (bar_col + 4, one extra row below bar gap)
    const BLOCK_ROWS: usize = 6;
    const tr: usize = @intCast(term_rows);
    // Start row centres the block; clamp so it never goes negative.
    const start_row: usize = if (tr > BLOCK_ROWS) (tr - BLOCK_ROWS) / 2 else 0;

    // bar_col is the shared left-edge anchor for title and bar.
    const bar_col: usize = centerCol(term_cols, bar_w);

    // Title -- flush with the bar's left edge.
    try appendPos(&out, alloc, start_row, bar_col);
    try out.appendSlice(alloc, title);

    // Progress bar -- centred (bar_col is its natural left edge).
    try appendPos(&out, alloc, start_row + 2, bar_col);
    try out.appendSlice(alloc, bar);

    // Hint -- 4 cells inset from bar's left edge, one extra row below.
    const hint_col: usize = bar_col + 8;
    try appendPos(&out, alloc, start_row + 5, hint_col);
    try out.appendSlice(alloc, hint);

    return out.toOwnedSlice(alloc);
}

// ---------------------------------------------------------------------------
// App wrapper
// ---------------------------------------------------------------------------
// thin shim so app.run gets the right function signatures. very honest work.

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
        // something went wrong. restore the terminal before we crash out.
        try std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[?1049l\x1B[?25h");
        return err;
    };

    // Leave alternate screen and restore cursor. do not skip this line.
    try std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[?1049l\x1B[?25h");
    std.process.exit(0); // 4 ticks. 1 bar. 0 regrets.
}
