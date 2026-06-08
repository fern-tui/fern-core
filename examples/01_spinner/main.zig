// SPDX-License-Identifier: MIT

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");

// Msg >>
// two variants. two possible futures.

const Msg = union(enum) {
    key: ansi.KeyEvent,
    spinner_tick: widget.spinner.TickMsg,
};

// State >>

const State = struct {
    spinner: widget.Spinner,
    quitting: bool = false,
};

// Styles >>

const SPIN_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_magenta });
const DIM_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_black });

// Handlers >>

// screen clearing demoted to main() -- the io instance has boundaries.
fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;

    var sp = widget.Spinner.initPreset(widget.spinner.DOT);
    sp.setStyle(SPIN_STYLE);
    return .{ .{ .spinner = sp }, sp.tick(Msg) };
}

// runs on every message.
// alloc is unused.
fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;

    switch (msg) {
        .key => |k| {
            if (isQuit(k)) {
                state.quitting = true;
                return .quit;
            }
        },
        .spinner_tick => |t| {
            const r = state.spinner.update(t, Msg);
            state.spinner = r.s;
            return r.cmd;
        },
    }
    return null;
}

// renders both pieces of the UI.
fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // This locks the render loop in place.
    try out.appendSlice(alloc, "   ");

    const frame = try state.spinner.view(alloc);
    defer alloc.free(frame);
    try out.appendSlice(alloc, frame);

    try out.appendSlice(alloc, " Loading forever...");

    const hint = try DIM_STYLE.render(alloc, "  press q to quit");
    defer alloc.free(hint);
    try out.appendSlice(alloc, hint);

    return out.toOwnedSlice(alloc);
}

// Helpers >>

// check for exit keys (esc, q, ctrl+c)
fn isQuit(k: ansi.KeyEvent) bool {
    switch (k.code) {
        .escape => return true,
        .char => |c| {
            if (c == 'q') return true;
            if (c == 'c' and k.mods.ctrl) return true;
        },
        else => {},
    }
    return false;
}

// main >>

// clears screen, spins forever, exits clean
pub fn main(init_ctx: std.process.Init) !void {
    // \x1B[2J: nuke everything. \x1B[4;1H: cursor sits at row 4.
    _ = std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[2J\x1B[4;1H") catch {};

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    try app.run(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, alloc);

    _ = std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\n") catch {};

    std.process.exit(0);
}
