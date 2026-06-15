// SPDX-License-Identifier: MIT

// textinput: single TextInput field.
// zig build example-textinput

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");

const Msg = union(enum) {
    key: ansi.KeyEvent,
};

const State = struct {
    input: widget.TextInput,
};

fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;
    var input = widget.TextInput.init();
    input.placeholder = "Pikachu";
    input.focus_();
    return .{ .{ .input = input }, null };
}

fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    switch (msg) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |ch| {
                    if (ch == 'c' and k.mods.ctrl) return .quit;
                    _ = try state.input.update(k, alloc);
                },
                else => _ = try state.input.update(k, alloc),
            }
        },
    }
    return null;
}

const DIM = style.Style.init().fg_(.{ .ansi16 = .bright_black });

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.appendSlice(alloc, "\x1B[2J\x1B[H");
    try out.appendSlice(alloc, "\r\n   What's your favorite Pokémon?\r\n\r\n   ");

    {
        const inp = try state.input.view(alloc);
        defer alloc.free(inp);
        try out.appendSlice(alloc, inp);
    }

    try out.appendSlice(alloc, "\r\n\r\n");

    {
        const help = try DIM.render(alloc, "   (esc to quit)");
        defer alloc.free(help);
        try out.appendSlice(alloc, help);
    }

    return out.toOwnedSlice(alloc);
}

pub fn main() !void {
    try app.runSimple(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, .{});
}
