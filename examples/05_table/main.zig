// SPDX-License-Identifier: MIT

// zig build example-table

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const app = @import("fern_app");
const widget = @import("fern_widget");

const PURPLE: ansi.Color = .{ .rgb = .{ .r = 0x6B, .g = 0x28, .b = 0xFF } };
const BORDER_GRAY: ansi.Color = .{ .rgb = .{ .r = 0x44, .g = 0x44, .b = 0x44 } };

const COLUMNS = [_]widget.table.Column{
    .{ .title = "Rank",       .width = 4,  .align_h = style.RIGHT },
    .{ .title = "City",       .width = 10, .align_h = style.LEFT  },
    .{ .title = "Country",    .width = 10, .align_h = style.LEFT  },
    .{ .title = "Population", .width = 10, .align_h = style.RIGHT },
};
const ROWS = [_]widget.table.Row{
    &[_][]const u8{ "01",  "Tokyo",       "Japan",      "37,274,000" },
    &[_][]const u8{ "02",  "Delhi",       "India",      "32,065,760" },
    &[_][]const u8{ "03",  "Shanghai",    "China",      "28,516,904" },
    &[_][]const u8{ "04",  "Dhaka",       "Bangladesh", "22,478,116" },
    &[_][]const u8{ "05",  "Sao Paulo",   "Brazil",     "22,429,800" },
    &[_][]const u8{ "06",  "Mexico City", "Mexico",     "22,085,140" },
    &[_][]const u8{ "07",  "Cairo",       "Egypt",      "21,750,020" },
    &[_][]const u8{ "08",  "Mumbai",      "India",      "20,667,656" },
    &[_][]const u8{ "09",  "Beijing",     "China",      "20,035,455" },
    &[_][]const u8{ "10",  "Osaka",       "Japan",      "19,165,340" },
    &[_][]const u8{ "11",  "Karachi",     "Pakistan",   "16,839,950" },
    &[_][]const u8{ "12",  "Istanbul",    "Turkey",     "15,636,243" },
};
const Msg = union(enum) {
    key: ansi.KeyEvent,
};
const State = struct {
    table: widget.Table,
};

fn init(_: std.mem.Allocator) !struct { State, ?app.Cmd(Msg) } {

    var t = widget.Table.init(&COLUMNS, &ROWS, 6);
    t.border_style = style.NORMAL;
    t.border_fg = BORDER_GRAY;
    t.show_column_dividers = false;

    // header.
    t.header_style = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } });

    t.selected_style = style.Style.init().bold_(true)
    .fg_(.{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } })
    .bg_(PURPLE);

    t.focus_();

    return .{ .{ .table = t }, null };
}
fn update(state: *State, msg: Msg, _: std.mem.Allocator) !?app.Cmd(Msg) {

    switch (msg) {
        .key => |k| {
            if (widget.key.isQuit(k)) return .quit;
            state.table = state.table.update(k);
        },
    }
    return null;
}
fn view(state: *const State, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.appendSlice(alloc, "\x1B[2J\x1B[H");

    {
        const body = try state.table.view(alloc);
        defer alloc.free(body);

        var lines = std.mem.splitScalar(u8, body, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) try out.appendSlice(alloc, "\r\n");
            first = false;
            try out.appendSlice(alloc, "  ");
            try out.appendSlice(alloc, line);
        }
    }

    try out.appendSlice(alloc, "\r\n");

    return out.toOwnedSlice(alloc);
}

pub fn main() !void {
    try app.runSimple(State, Msg, .{
        .init = init,
        .update = update,
        .view = view,
    }, .{});
}
