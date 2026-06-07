// SPDX-License-Identifier: MIT
// ^ removing this line summons a lawyer. do not test it.

const std = @import("std");
const ansi = @import("fern_ansi"); // your terminal's therapist
const style = @import("fern_style"); // lipstick for stdout
const app = @import("fern_app"); // does literally everything
const widget = @import("fern_widget"); // spinning dots: the only UI you need

// ---------------------------------------------------------------------------
// Msg
// ---------------------------------------------------------------------------
// two variants. two possible futures. your last project had 47. grow up.

const Msg = union(enum) {
    key: ansi.KeyEvent,
    spinner_tick: widget.spinner.TickMsg,
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
// the entire mutable world in two fields. philosophers have written less.

const State = struct {
    spinner: widget.Spinner,
    quitting: bool = false, // default: cope. set true to stop coping.
};

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------
// the complete design system. no figma board was harmed.

// bright_magenta: for people who still care
const SPIN_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_magenta });

// bright_black: whispers "press q" at you
const DIM_STYLE = style.Style.init().fg_(.{ .ansi16 = .bright_black });

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// your origin story. called once. alloc shows up, does nothing, goes home.
// screen clearing demoted to main() -- the io instance has boundaries.
fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;

    // (Screen clearing logic moved to main() to access the Zig 0.16 io instance)

    var sp = widget.Spinner.initPreset(widget.spinner.DOT);
    sp.setStyle(SPIN_STYLE);

    return .{ .{ .spinner = sp }, sp.tick(Msg) };
}

// fires on every message. no weekends. no PTO.
// alloc is here in a supporting role. it contributes nothing.
fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;

    switch (msg) {
        .key => |k| {
            if (isQuit(k)) {
                state.quitting = true; // closure. finally.
                return .quit;
            }
        },
        .spinner_tick => |t| {
            const r = state.spinner.update(t, Msg);
            state.spinner = r.s;
            return r.cmd;
        },
    }
    return null; // nothing happened. as usual.
}

// renders both pieces of the UI.
// \r + \x1B[2K: scorched earth before every frame so we don't ghost.
fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // \r moves cursor to the start of the line.
    // \x1B[2K clears the entire line so we don't get ghosting.
    // This locks the render loop in place.
    try out.appendSlice(alloc, "   ");
    //try out.appendSlice(alloc, "\r\x1B[2K   ");

    const frame = try state.spinner.view(alloc);
    defer alloc.free(frame);
    try out.appendSlice(alloc, frame);

    try out.appendSlice(alloc, " Loading forever..."); // not loading anything. this is it.

    const hint = try DIM_STYLE.render(alloc, "  press q to quit");
    defer alloc.free(hint);
    try out.appendSlice(alloc, hint);

    return out.toOwnedSlice(alloc);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// detects whether the user is making their escape. (pun load-bearing.)
// accepts: esc, q, ctrl+c. not accepted: ctrl+alt+delete. wrong OS.
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

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

// clears screen, spins forever, exits clean. a perfect program.
pub fn main(init_ctx: std.process.Init) !void {
    // \x1B[2J: nuke everything. \x1B[4;1H: cursor sits at row 4.
    // catch {}: if the terminal says no, we pretend it didn't happen.
    _ = std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[2J\x1B[4;1H") catch {};

    // arena: one big slab, zero individual frees. deliberate. (also lazy.)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    try app.run(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, alloc);

    // Print a final newline before exiting to prevent the shell's '%' warning.
    // you know the '%'. it judges you. not today.
    _ = std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\n") catch {};

    std.process.exit(0); // 0 panics. 0 crashes. 0 things accomplished. flawless.
}
