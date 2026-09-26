// SPDX-License-Identifier: MIT
// zig build example-progress

const std = @import("std");
const fern = @import("fern");

const app = fern.app;
const widget = fern.widget;
const style = fern.style;
const ansi = fern.ansi;

const Msg = union(enum) {
    key: ansi.KeyEvent,
    progress_frame: widget.progress.FrameMsg,
    tick: void,
    resize: ansi.ResizeEvent,
};

const State = struct {
    progress: widget.Progress,
    done: bool = false,
    term_cols: u16 = 80,
    term_rows: u16 = 24,
};

fn tickCmd() app.Cmd(Msg) {
    const TickGen = struct {
        fn gen(_: u32, _: i64) Msg {
            return Msg{ .tick = {} };
        }
    };
    return app.Cmd(Msg){
        .every = .{
            .ns = std.time.ns_per_s,
            .id = 0,
            .gen = TickGen.gen,
        },
    };
}

const TITLE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } });

const DIM_STYLE = style.Style.init()
    .fg_(.{ .ansi16 = .bright_black });

const DONE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0x04, .g = 0xB5, .b = 0x75 } });

fn init(_: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    var p = widget.Progress.init();
    p.setWidth(44);

    return .{
        .{ .progress = p },
        tickCmd(),
    };
}

fn update(state: *State, msg: Msg, _: std.mem.Allocator) !?app.Cmd(Msg) {
    switch (msg) {
        .key => return .quit,

        .resize => |r| {
            state.term_cols = r.cols;
            state.term_rows = r.rows;
            return null;
        },

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

fn centerPad(out: *std.ArrayList(u8), alloc: std.mem.Allocator, term_cols: u16, content_w: usize) !void {
    const tc: usize = @intCast(term_cols);
    if (content_w < tc) {
        const pad = (tc - content_w) / 2;
        try out.appendNTimes(alloc, ' ', pad);
    }
}

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    const title = if (state.done)
        try DONE_STYLE.render(alloc, "> Download complete!")
    else
        try TITLE_STYLE.render(alloc, "> Downloading fern...");
    defer alloc.free(title);

    const bar = try state.progress.view(alloc);
    defer alloc.free(bar);

    const hint = try DIM_STYLE.render(alloc, "press any key to quit");
    defer alloc.free(hint);

    // Center block vertically
    const BLOCK_ROWS: usize = 5;
    const tr: usize = @intCast(state.term_rows);
    const top_pad: usize = if (tr > BLOCK_ROWS) (tr - BLOCK_ROWS) / 2 else 0;

    try out.appendNTimes(alloc, '\n', top_pad);

    // Title
    try centerPad(&out, alloc, state.term_cols, 44);
    try out.appendSlice(alloc, title);
    try out.appendSlice(alloc, "\n\n");

    // Progress bar
    try centerPad(&out, alloc, state.term_cols, 44);
    try out.appendSlice(alloc, bar);
    try out.appendSlice(alloc, "\n\n");

    // Hint
    try centerPad(&out, alloc, state.term_cols, 44);
    try out.appendSlice(alloc, hint);

    return out.toOwnedSlice(alloc);
}

pub fn main() !void {
    try app.runSimple(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, .{
        .alt_screen = true,
        .hide_cursor = true,
    });
}
