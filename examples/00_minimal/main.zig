// SPDX-License-Identifier: MIT
//
// Minimal Fern application: an animated DOT spinner.
// Demonstrates the `app.runSimple` entry point and the TEA (Elm) architecture loop.
//
// Run:
//   zig build example-minimal

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

// Cyan spinner accent
const SPIN_STYLE = style.Style.init().fg_(.{ .ansi16 = .cyan });

fn init(_: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    var sp = widget.Spinner.initPreset(widget.spinner.DOT);
    sp.setStyle(SPIN_STYLE);
    return .{ .{ .spinner = sp }, sp.tick(Msg) };
}

fn update(state: *State, msg: Msg, _: std.mem.Allocator) !?app.Cmd(Msg) {
    return switch (msg) {
        .key => |k| if (widget.key.isQuit(k)) .quit else null,
        .spinner_tick => |t| blk: {
            const r = state.spinner.update(t, Msg);
            state.spinner = r.s;
            break :blk r.cmd;
        },
    };
}

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    const frame = try state.spinner.view(alloc);
    defer alloc.free(frame);

    return std.fmt.allocPrint(alloc, "   {s} Loading...  press q to quit", .{frame});
}

pub fn main() !void {
    try app.runSimple(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, .{});
}
