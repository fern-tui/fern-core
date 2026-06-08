// SPDX-License-Identifier: MIT

// simple list: arrows or j/k to move, enter to select, q to quit.
// compact layout, dots paginator, no extra ui.
//
// run: zig build example-list

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

const Msg = union(enum) {
    key: ansi.KeyEvent,
};

// State >>

// NONE == ITEMS.len: sentinel meaning the user has not committed to a meal yet.
const NONE: usize = ITEMS.len;

const State = struct {
    cursor: usize = 0,
    pag: widget.Paginator,
    chosen: usize = NONE,
};

// Styles >>

// Bold white
const PROMPT_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } });

// Bold magenta
const SELECTED_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .ansi16 = .bright_magenta });

// Dim grey
const DIM_STYLE = style.Style.init()
    .fg_(.{ .ansi16 = .bright_black });

// Bold green 
const DONE_STYLE = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0x04, .g = 0xB5, .b = 0x75 } });

// init >>

fn init(alloc: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {
    _ = alloc;

    var pag = widget.Paginator.init();
    pag.display = .dots;
    pag.per_page = PAGE_SIZE;
    pag.setTotalPages(ITEMS.len);
    pag.active_dot = "\xe2\x97\x8f ";
    pag.inactive_dot = "\xe2\x97\x8b ";

    return .{ .{ .pag = pag }, null };
}

// update >>

fn update(state: *State, msg: Msg, alloc: std.mem.Allocator) !?app.Cmd(Msg) {
    _ = alloc;

    switch (msg) {
        .key => |k| {
            if (isQuit(k)) return .quit;

            // Once chosen, any key quits
            if (state.chosen != NONE) return .quit;

            switch (k.code) {
                .up => moveCursor(state, -1),
                .down => moveCursor(state, 1),
                .char => |c| {
                    if (c == 'k') moveCursor(state, -1);
                    if (c == 'j') moveCursor(state, 1);
                },
                .enter => state.chosen = state.cursor,
                else => {},
            }
        },
    }
    return null;
}

// move cursor and keep in bounds. sync paginator dots.
fn moveCursor(state: *State, delta: i2) void {
    if (delta < 0 and state.cursor > 0) {
        state.cursor -= 1;
    } else if (delta > 0 and state.cursor < ITEMS.len - 1) {
        state.cursor += 1;
    }
    // Dots follow the cursor.  Everyone follows someone.
    state.pag.page = state.cursor / PAGE_SIZE;
}

// view >>

const INDENT = "    ";

fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // Nuke the screen and park the cursor at home before painting.
    try out.appendSlice(alloc, "\x1B[2J\x1B[H");

    if (state.chosen != NONE) {
        try renderDone(&out, alloc, state.chosen);
    } else {
        try renderList(&out, alloc, state);
    }

    return out.toOwnedSlice(alloc);
}

// Render the confirmation screen: item name + the program's only opinion.
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

// Render the interactive list: prompt, numbered rows, paginator, help bar.
fn renderList(out: *std.ArrayList(u8), alloc: std.mem.Allocator, state: *const State) !void {
    const prompt = try PROMPT_STYLE.render(alloc, "1: What do you want for dinner?");
    defer alloc.free(prompt);

    try out.appendSlice(alloc, "\r\n");
    try out.appendSlice(alloc, INDENT);
    try out.appendSlice(alloc, prompt);
    try out.appendSlice(alloc, "\r\n\r\n");

    // item rows >
    // Only render the slice for the current page.
    const page_start = state.pag.page * PAGE_SIZE;
    const page_end = @min(page_start + PAGE_SIZE, ITEMS.len);

    var row: usize = page_start;
    while (row < page_end) : (row += 1) {
        try renderRow(out, alloc, row, state.cursor);
    }

    // paginator dots >
    try out.appendSlice(alloc, "\r\n");
    try out.appendSlice(alloc, INDENT);

    {
        const dots_plain = try state.pag.view(alloc);
        defer alloc.free(dots_plain);
        const dots = try DIM_STYLE.render(alloc, dots_plain);
        defer alloc.free(dots);
        try out.appendSlice(alloc, dots);
    }

    try out.appendSlice(alloc, "\r\n");

    // help bar >
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

// Render one list row.  Heap slices freed explicitly -- no defer-in-loop
fn renderRow(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    row: usize,
    cursor: usize,
) !void {
    const is_selected = (row == cursor);

    // Number prefix on the stack: "1. " .. "99. "  Stacks are free.
    var num_buf: [8]u8 = undefined;
    const num = try std.fmt.bufPrint(&num_buf, "{d}. ", .{row + 1});

    try out.appendSlice(alloc, INDENT);

    if (is_selected) {
        // "> " glyph -- allocate, stomp the terminal, free.
        {
            const glyph = try SELECTED_STYLE.render(alloc, "> ");
            defer alloc.free(glyph);
            try out.appendSlice(alloc, glyph);
        }

        // Number + name coloured in its own block; style leaks nowhere.
        var item_buf: [256]u8 = undefined;
        const item_plain = try std.fmt.bufPrint(&item_buf, "{s}{s}", .{ num, ITEMS[row] });
        {
            const item_col = try SELECTED_STYLE.render(alloc, item_plain);
            defer alloc.free(item_col);
            try out.appendSlice(alloc, item_col);
        }
    } else {
        // Unselected: plain text.  Two leading spaces align with "> " width.
        var item_buf: [256]u8 = undefined;
        const item_plain = try std.fmt.bufPrint(
            &item_buf,
            "  {s}{s}",
            .{ num, ITEMS[row] },
        );
        try out.appendSlice(alloc, item_plain);
    }

    try out.appendSlice(alloc, "\r\n");
}

// Helpers >>

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
