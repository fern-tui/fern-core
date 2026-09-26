// SPDX-License-Identifier: MIT
//
// Standalone animated spinner example demonstrating styled text and hidden cursor.
//
// Run:
//   zig build example-spinner

const std = @import("std");
const fern = @import("fern");

const app = fern.app;
const widget = fern.widget;
const style = fern.style;

const Msg = union(enum) {
    key: fern.ansi.KeyEvent,
    spinner_tick: widget.spinner.TickMsg,
};

const State = struct {
    spinner: widget.Spinner,
};

const SPIN_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_magenta });
const DIM_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_black });

fn init(_: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    var sp = widget.Spinner.initPreset(widget.spinner.DOT);
    sp.setStyle(SPIN_STYLE);
    return .{ .{ .spinner = sp }, sp.tick(Msg) };
}

fn update(state: *State, msg: Msg, _: std.mem.Allocator) !?app.Cmd(Msg) {
    switch (msg) {
        .key => |k| {
            if (widget.key.isQuit(k)) return .quit;
        },
        .spinner_tick => |t| {
            const r = state.spinner.update(t, Msg);
            state.spinner = r.s;
            return r.cmd;
        },
    }
    return null;
}

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    const frame = try state.spinner.view(alloc);
    defer alloc.free(frame);

    const hint = try DIM_STYLE.render(alloc, "press q to quit");
    defer alloc.free(hint);

    return std.fmt.allocPrint(alloc, "   {s} Loading forever...  {s}", .{ frame, hint });
}

pub fn main() !void {
    // runSimple automatically manages the arena, terminal state, and clean exit.
    try app.runSimple(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, .{
        .alt_screen = true,
        .hide_cursor = true,
    });
}
