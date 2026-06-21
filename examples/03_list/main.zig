// SPDX-License-Identifier: MIT

// arrows or j/k to move, enter to select, q to quit.
// compact layout, dots paginator, no extra ui.
// zig build example-list

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");
const ITEMS = [_][]const u8{
    "Ramen",
    "Tomato Soup",
    "Hamburgers",
    "Cheeseburgers",
    "Currywurst",
    "Okonomiyaki",
    "Pasta",
};
const PAGE_SIZE: usize = 5;
const INDENT = "    ";
const Msg = union(enum) {
    key: ansi.KeyEvent,
};
const NONE: usize = ITEMS.len;
const State = struct {
    list: widget.List,
    chosen: usize = NONE,
};
const PROMPT_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } });
const DIM_STYLE = style.Style.init()
    .fg_(.{ .ansi16 = .bright_black });
const DONE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0x04, .g = 0xB5, .b = 0x75 } });

fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;

    var list = widget.List.init(&ITEMS, PAGE_SIZE);
    list.indent = INDENT;
    list.pag_display = .dots;

    return .{ .{ .list = list }, null };
}
fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;

    switch (msg) {
        .key => |k| {
            if (widget.key.isQuit(k)) return .quit;

            // Once chosen, any key quits.
            if (state.chosen != NONE) return .quit;

            switch (k.code) {
                .enter => state.chosen = state.list.selectedIndex(),
                else => state.list = state.list.update(k),
            }
        },
    }
    return null;
}
fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // Nuke the screen and park the cursor at home before painting.
    try out.appendSlice(alloc, "\x1B[2J\x1B[H");

    if (state.chosen != NONE) {
        try renderDone(&out, alloc, state.chosen);
    } else {
        try renderList(&out, alloc, &state.list);
    }

    return out.toOwnedSlice(alloc);
}

// Render the confirmation screen: item name with the program's only opinion.
fn renderDone(out: *std.ArrayList(u8), alloc: std.mem.Allocator, chosen: usize) !void {
    var buf: [128]u8 = undefined;
    const plain = try std.fmt.bufPrint(&buf, "{s}? Sounds good to me.", .{ITEMS[chosen]});

    const line = try DONE_STYLE.render(alloc, plain);
    defer alloc.free(line);

    try out.appendSlice(alloc, "\r\n");
    try out.appendSlice(alloc, INDENT);
    try out.appendSlice(alloc, line);
    try out.appendSlice(alloc, "\r\n");
}

// Render the interactive list: prompt, the List widget's rows with dots, help bar.
fn renderList(out: *std.ArrayList(u8), alloc: std.mem.Allocator, list: *const widget.List) !void {
    const prompt = try PROMPT_STYLE.render(alloc, "1: What do you want for dinner?");
    defer alloc.free(prompt);

    try out.appendSlice(alloc, "\r\n");
    try out.appendSlice(alloc, INDENT);
    try out.appendSlice(alloc, prompt);
    try out.appendSlice(alloc, "\r\n\r\n");

    // List.view() joins rows (and the dot indicator) with '\n'; the
    // renderer wants '\r\n' between lines, so re-join on the way out.
    {
        const body = try list.view(alloc);
        defer alloc.free(body);

        var lines = std.mem.splitScalar(u8, body, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) try out.appendSlice(alloc, "\r\n");
            first = false;
            try out.appendSlice(alloc, line);
        }
    }

    try out.appendSlice(alloc, "\r\n\r\n");

    {
        const help = try DIM_STYLE.render(
            alloc,
            INDENT ++ "↑/k up ✻ ↓/j down ✻ [enter ↵] select ✻ q quit",
        );
        defer alloc.free(help);
        try out.appendSlice(alloc, help);
    }

    try out.appendSlice(alloc, "\r\n");
}

pub fn main(init_ctx: std.process.Init) !void {
    _ = std.Io.File.stdout().writeStreamingAll(init_ctx.io, "\x1B[2J\x1B[H") catch {};

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
