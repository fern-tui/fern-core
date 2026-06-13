// SPDX-License-Identifier: MIT

// minimal fern app. a spinner that runs until you press q.
// shows the runSimple entry point
// zig build example-minimal
const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");
const Msg = union(enum) {
    key: ansi.KeyEvent,
    spinner_tick: widget.spinner.TickMsg,
};
const State = struct { spinner: widget.Spinner };
const SPIN_STYLE = style.Style.init().fg_(.{ .ansi16 = .cyan });

fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;
    var sp = widget.Spinner.initPreset(widget.spinner.DOT);
    sp.setStyle(SPIN_STYLE);
    return .{ .{ .spinner = sp }, sp.tick(Msg) };
}
fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;
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
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    try out.appendSlice(alloc, "   ");
    const frame = try state.spinner.view(alloc);
    defer alloc.free(frame);
    try out.appendSlice(alloc, frame);
    try out.appendSlice(alloc, " Loading...  press q to quit");
    return out.toOwnedSlice(alloc);
}

pub fn main(_: std.process.Init) !void {
    try app.runSimple(State, Msg, .{ .init = init, .update = update, .view = view }, .{});
}
