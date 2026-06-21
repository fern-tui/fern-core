// SPDX-License-Identifier: MIT

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const key = @import("key.zig");
const paginator = @import("paginator.zig");

pub const Display = paginator.DisplayType;

pub const KeyMap = struct {
    up: key.Binding = .{
        .codes = &.{ .up, .{ .char = 'k' } },
        .key_display = "up/k",
        .desc = "move up",
    },
    down: key.Binding = .{
        .codes = &.{ .down, .{ .char = 'j' } },
        .key_display = "down/j",
        .desc = "move down",
    },
    prev_page: key.Binding = .{
        .codes = &.{ .page_up, .left, .{ .char = 'h' } },
        .key_display = "pgup/h",
        .desc = "prev page",
    },
    next_page: key.Binding = .{
        .codes = &.{ .page_down, .right, .{ .char = 'l' } },
        .key_display = "pgdn/l",
        .desc = "next page",
    },
    goto_start: key.Binding = .{
        .codes = &.{ .home, .{ .char = 'g' } },
        .key_display = "g/home",
        .desc = "go to first item",
    },
    goto_end: key.Binding = .{
        .codes = &.{ .end, .{ .char = 'G' } },
        .key_display = "G/end",
        .desc = "go to last item",
    },
};

pub const List = struct {
    selected_style: style.Style = style.Style.init()
        .bold_(true)
        .fg_(.{ .ansi16 = .bright_magenta }),

    items: []const []const u8 = &.{},

    cursor: usize = 0,
    pag: paginator.Paginator = .{},
    pag_display: paginator.DisplayType = .dots,

    width: u16 = 0,
    height: u16 = 0,

    indent: []const u8 = "  ",
    row_spacing: u8 = 0,
    empty_text: []const u8 = "No items.",

    filter_text: ?[]const u8 = null,

    keymap: KeyMap = .{},

    pub fn init(items: []const []const u8, per_page: usize) List {
        var l = List{};
        l.pag.per_page = per_page;
        l.setItems(items);
        return l;
    }

    /// Caller keeps items alive; List holds a non-owning view.
    pub fn setItems(self: *List, new_items: []const []const u8) void {
        self.items = new_items;
        self.cursor = 0;
        self.recalcPerPage();
        self.pag.setTotalPages(self.visibleCount());
        self.syncPage();
    }

    pub fn setHeight(self: *List, new_height: u16) void {
        self.height = new_height;
        self.recalcPerPage();
        self.pag.setTotalPages(self.visibleCount());
        self.syncPage();
    }

    pub fn select(self: *List, index: usize) void {
        const count = self.visibleCount();
        if (count == 0) {
            self.cursor = 0;
        } else {
            self.cursor = @min(index, count - 1);
        }
        self.syncPage();
    }

    /// Maps visible cursor back to raw index when a filter is active.
    pub fn selectedIndex(self: List) usize {
        if (self.items.len == 0) return 0;
        const ft = self.filter_text orelse return self.cursor;
        if (ft.len == 0) return self.cursor;
        var matched: usize = 0;
        for (self.items, 0..) |item, raw_idx| {
            if (std.mem.indexOf(u8, item, ft) != null) {
                if (matched == self.cursor) return raw_idx;
                matched += 1;
            }
        }
        return 0;
    }

    pub fn update(self: List, ev: ansi.KeyEvent) List {
        var l = self;
        const count = l.visibleCount();
        if (count == 0) return l;

        if (key.matches(ev, l.keymap.up)) {
            if (l.cursor > 0) l.cursor -= 1;
            l.syncPage();
        } else if (key.matches(ev, l.keymap.down)) {
            if (l.cursor < count - 1) l.cursor += 1;
            l.syncPage();
        } else if (key.matches(ev, l.keymap.goto_start)) {
            l.cursor = 0;
            l.syncPage();
        } else if (key.matches(ev, l.keymap.goto_end)) {
            l.cursor = count - 1;
            l.syncPage();
        } else if (key.matches(ev, l.keymap.prev_page)) {
            l.pag.prevPage();
            const page_last = l.pageLastCursor();
            const page_first = l.pag.page * l.pag.per_page;
            if (l.cursor > page_last) l.cursor = page_last;
            if (l.cursor < page_first) l.cursor = page_first;
        } else if (key.matches(ev, l.keymap.next_page)) {
            l.pag.nextPage();
            const page_first = l.pag.page * l.pag.per_page;
            const page_last = l.pageLastCursor();
            if (l.cursor < page_first) l.cursor = page_first;
            if (l.cursor > page_last) l.cursor = page_last;
        }
        return l;
    }

    /// Caller frees the returned slice.
    pub fn view(self: List, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        const vis_items = try self.buildVisible(allocator);
        defer allocator.free(vis_items);

        if (vis_items.len == 0) {
            try out.appendSlice(allocator, self.indent);
            try out.appendSlice(allocator, self.empty_text);
            return out.toOwnedSlice(allocator);
        }

        const start, const end = self.pag.sliceBounds(vis_items.len);
        const page_items = vis_items[start..end];

        for (page_items, 0..) |item, page_rel| {
            const global_idx = start + page_rel;
            const is_selected = (global_idx == self.cursor);

            try self.renderRow(&out, allocator, start + page_rel + 1, item, is_selected);

            if (self.row_spacing > 0 and page_rel < page_items.len - 1) {
                var sp: u8 = 0;
                while (sp < self.row_spacing) : (sp += 1) {
                    try out.appendSlice(allocator, "\r\n");
                }
            }
        }

        if (self.pag.total_pages > 1) {
            try out.appendSlice(allocator, "\r\n");
            try out.appendSlice(allocator, self.indent);
            try self.appendPaginatorView(&out, allocator);
        }

        return out.toOwnedSlice(allocator);
    }

    fn renderRow(
        self: List,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        number: usize,
        item: []const u8,
        is_selected: bool,
    ) !void {
        var num_buf: [12]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&num_buf, "{d}. ", .{number});

        var row: std.ArrayList(u8) = .empty;
        defer row.deinit(allocator);

        try row.appendSlice(allocator, if (is_selected) "> " else "  ");
        try row.appendSlice(allocator, num_str);

        if (self.width > 0) {
            const prefix_width = ansi.str.strWidth(self.indent) +
                2 +
                ansi.str.strWidth(num_str);
            const budget: usize = if (@as(usize, self.width) > prefix_width)
                @as(usize, self.width) - prefix_width
            else
                0;
            if (budget > 0) {
                const truncated = try ansi.str.truncate(item, budget, allocator);
                defer allocator.free(truncated);
                try row.appendSlice(allocator, truncated);
            }
        } else {
            try row.appendSlice(allocator, item);
        }

        try out.appendSlice(allocator, self.indent);
        if (is_selected) {
            const styled = try self.selected_style.render(allocator, row.items);
            defer allocator.free(styled);
            try out.appendSlice(allocator, styled);
        } else {
            try out.appendSlice(allocator, row.items);
        }
        try out.appendSlice(allocator, "\r\n");
    }

    fn appendPaginatorView(
        self: List,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
    ) !void {
        var pag_copy = self.pag;
        pag_copy.display = self.pag_display;

        if (self.width > 0 and pag_copy.display == .dots) {
            const dot_width = ansi.str.strWidth(pag_copy.active_dot);
            const total_dot_width = dot_width * pag_copy.total_pages;
            const indent_width = ansi.str.strWidth(self.indent);
            if (total_dot_width + indent_width > @as(usize, self.width)) {
                pag_copy.display = .arabic;
            }
        }

        const pag_str = try pag_copy.view(allocator);
        defer allocator.free(pag_str);
        try out.appendSlice(allocator, pag_str);
        try out.appendSlice(allocator, "\r\n");
    }

    pub fn visibleCount(self: List) usize {
        const ft = self.filter_text orelse return self.items.len;
        if (ft.len == 0) return self.items.len;
        var n: usize = 0;
        for (self.items) |item| {
            if (std.mem.indexOf(u8, item, ft) != null) n += 1;
        }
        return n;
    }

    fn buildVisible(self: List, allocator: std.mem.Allocator) ![]const []const u8 {
        const ft = self.filter_text orelse {
            const out = try allocator.alloc([]const u8, self.items.len);
            @memcpy(out, self.items);
            return out;
        };
        if (ft.len == 0) {
            const out = try allocator.alloc([]const u8, self.items.len);
            @memcpy(out, self.items);
            return out;
        }
        var buf: std.ArrayList([]const u8) = .empty;
        defer buf.deinit(allocator);
        for (self.items) |item| {
            if (std.mem.indexOf(u8, item, ft) != null) {
                try buf.append(allocator, item);
            }
        }
        return buf.toOwnedSlice(allocator);
    }

    fn recalcPerPage(self: *List) void {
        if (self.height > 0) {
            self.pag.per_page = @as(usize, self.height);
        }
    }

    fn syncPage(self: *List) void {
        if (self.pag.per_page == 0) return;
        self.pag.page = self.cursor / self.pag.per_page;
        if (self.pag.total_pages > 0 and self.pag.page >= self.pag.total_pages) {
            self.pag.page = self.pag.total_pages - 1;
        }
    }

    fn pageLastCursor(self: List) usize {
        const count = self.visibleCount();
        if (count == 0) return 0;
        const page_end = @min(
            (self.pag.page + 1) * self.pag.per_page,
            count,
        );
        return page_end - 1;
    }
};

const testing = std.testing;

fn makeList(items: []const []const u8, per_page: usize) List {
    return List.init(items, per_page);
}

test "List init defaults" {
    const l = List.init(&.{}, 0);
    try testing.expectEqual(@as(usize, 0), l.cursor);
    try testing.expectEqual(@as(usize, 0), l.items.len);
}

test "List setItems resets cursor and paginates" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    const l = makeList(&items, 3);
    try testing.expectEqual(@as(usize, 0), l.cursor);
    try testing.expectEqual(@as(usize, 2), l.pag.total_pages);
}

test "List update up does not go below 0" {
    const items = [_][]const u8{"only"};
    var l = makeList(&items, 5);
    const ev = ansi.KeyEvent{ .code = .up, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 0), l.cursor);
}

test "List update down moves cursor" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = makeList(&items, 5);
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 1), l.cursor);
}

test "List update down stops at last item" {
    const items = [_][]const u8{ "a", "b" };
    var l = makeList(&items, 5);
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    l = l.update(ev);
    l = l.update(ev);
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 1), l.cursor);
}

test "List update goto_start jumps to first" {
    const items = [_][]const u8{ "a", "b", "c", "d" };
    var l = makeList(&items, 5);
    l.cursor = 3;
    l.syncPage();
    const ev = ansi.KeyEvent{ .code = .home, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 0), l.cursor);
}

test "List update goto_end jumps to last" {
    const items = [_][]const u8{ "a", "b", "c", "d" };
    var l = makeList(&items, 5);
    const ev = ansi.KeyEvent{ .code = .end, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 3), l.cursor);
}

test "List update G char jumps to last" {
    const items = [_][]const u8{ "x", "y", "z" };
    var l = makeList(&items, 5);
    const ev = ansi.KeyEvent{ .code = .{ .char = 'G' }, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 2), l.cursor);
}

test "List update next_page advances page and clamps cursor" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var l = makeList(&items, 2);
    const ev = ansi.KeyEvent{ .code = .page_down, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 1), l.pag.page);
    try testing.expect(l.cursor >= 2 and l.cursor <= 3);
}

test "List update prev_page wraps cursor to page" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var l = makeList(&items, 2);
    l.select(4);
    const ev = ansi.KeyEvent{ .code = .page_up, .mods = .{} };
    l = l.update(ev);
    try testing.expectEqual(@as(usize, 1), l.pag.page);
    try testing.expect(l.cursor >= 2 and l.cursor <= 3);
}

test "List select clamps within range" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = makeList(&items, 5);
    l.select(100);
    try testing.expectEqual(@as(usize, 2), l.cursor);
}

test "List select zero-item list is safe" {
    var l = List.init(&.{}, 0);
    l.select(5);
    try testing.expectEqual(@as(usize, 0), l.cursor);
}

test "List visibleCount with filter" {
    const items = [_][]const u8{ "apple", "banana", "apricot", "cherry" };
    var l = makeList(&items, 10);
    l.filter_text = "ap";
    try testing.expectEqual(@as(usize, 2), l.visibleCount());
}

test "List visibleCount null filter returns all" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = makeList(&items, 10);
    try testing.expectEqual(@as(usize, 3), l.visibleCount());
}

test "List view empty returns empty_text" {
    const alloc = testing.allocator;
    var l = List.init(&.{}, 0);
    l.empty_text = "Nothing here.";
    const v = try l.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Nothing here.") != null);
}

test "List view renders items" {
    const alloc = testing.allocator;
    const items = [_][]const u8{ "Ramen", "Pasta" };
    var l = makeList(&items, 5);
    const v = try l.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Ramen") != null);
    try testing.expect(std.mem.indexOf(u8, v, "Pasta") != null);
}

test "List setHeight recalculates per_page" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g" };
    var l = List.init(&.{}, 0);
    l.setItems(&items);
    l.setHeight(3);
    try testing.expectEqual(@as(usize, 3), l.pag.per_page);
}

test "List syncPage keeps page consistent with cursor" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var l = makeList(&items, 2);
    l.select(4);
    try testing.expectEqual(@as(usize, 2), l.pag.page);
}
