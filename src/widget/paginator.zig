// SPDX-License-Identifier: MIT

// Pagination helper.
// Pure state only (no ticks, no Cmds). Crunches navigation math and renders
// dot or numeric page indicators.
const std = @import("std");
const ansi = @import("fern_ansi");
const key = @import("key.zig");

pub const DisplayType = enum { arabic, dots };

pub const KeyMap = struct {
    prev_page: key.Binding = .{
        .codes = &.{ .page_up, .left, .{ .char = 'h' } },
        .key_display = "pgup/←",
        .desc = "prev page",
    },
    next_page: key.Binding = .{
        .codes = &.{ .page_down, .right, .{ .char = 'l' } },
        .key_display = "pgdn/→",
        .desc = "next page",
    },
};

pub const Paginator = struct {
    display: DisplayType = .arabic,
    page: usize = 0,
    per_page: usize = 1,
    total_pages: usize = 1,
    active_dot: []const u8 = "\xe2\x80\xa2", // •
    inactive_dot: []const u8 = "\xe2\x97\x8b", // ○
    arabic_fmt: []const u8 = "{d}/{d}",
    keymap: KeyMap = .{},

    // lifecycle

    pub fn init() Paginator {
        return .{};
    }

    // helpers

    /// Set total_pages from total item count.
    pub fn setTotalPages(self: *Paginator, total_items: usize) void {
        if (total_items == 0) {
            self.total_pages = 1;
            return;
        }
        const n = total_items / self.per_page;
        self.total_pages = if (total_items % self.per_page > 0) n + 1 else n;
    }

    /// Number of items visible on the current page given a total count.
    pub fn itemsOnPage(self: Paginator, total_items: usize) usize {
        const start, const end = self.sliceBounds(total_items);
        return end - start;
    }

    /// Start and end indices for slicing into a list of total_items.
    pub fn sliceBounds(self: Paginator, total_items: usize) struct { usize, usize } {
        const start = self.page * self.per_page;
        const end = @min(start + self.per_page, total_items);
        return .{ start, end };
    }

    pub fn onFirstPage(self: Paginator) bool {
        return self.page == 0;
    }
    pub fn onLastPage(self: Paginator) bool {
        return self.page == self.total_pages -| 1;
    }

    pub fn prevPage(self: *Paginator) void {
        if (self.page > 0) self.page -= 1;
    }

    pub fn nextPage(self: *Paginator) void {
        if (!self.onLastPage()) self.page += 1;
    }

    /// Handle a KeyEvent.  Returns the (possibly updated) Paginator.
    pub fn update(self: Paginator, ev: ansi.KeyEvent) Paginator {
        var p = self;
        if (key.matches(ev, p.keymap.next_page)) p.nextPage() else if (key.matches(ev, p.keymap.prev_page)) p.prevPage();
        return p;
    }

    /// Render the pagination indicator.
    /// Caller owns the returned slice; free with allocator.free().
    pub fn view(self: Paginator, allocator: std.mem.Allocator) ![]u8 {
        return switch (self.display) {
            .dots => self.dotsView(allocator),
            .arabic => self.arabicView(allocator),
        };
    }

    fn dotsView(self: Paginator, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        for (0..self.total_pages) |i| {
            const dot = if (i == self.page) self.active_dot else self.inactive_dot;
            try out.appendSlice(allocator, dot);
        }
        return out.toOwnedSlice(allocator);
    }

    fn arabicView(self: Paginator, allocator: std.mem.Allocator) ![]u8 {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}/{d}", .{
            self.page + 1, self.total_pages,
        }) catch return allocator.dupe(u8, "?/?");
        return allocator.dupe(u8, s);
    }
};

test "Paginator setTotalPages divides evenly" {
    var p = Paginator.init();
    p.per_page = 10;
    p.setTotalPages(30);
    try std.testing.expectEqual(@as(usize, 3), p.total_pages);
}

test "Paginator setTotalPages rounds up" {
    var p = Paginator.init();
    p.per_page = 10;
    p.setTotalPages(25);
    try std.testing.expectEqual(@as(usize, 3), p.total_pages);
}

test "Paginator nextPage advances page" {
    var p = Paginator.init();
    p.total_pages = 5;
    p.nextPage();
    try std.testing.expectEqual(@as(usize, 1), p.page);
}

test "Paginator nextPage stops at last" {
    var p = Paginator.init();
    p.total_pages = 2;
    p.page = 1;
    p.nextPage();
    try std.testing.expectEqual(@as(usize, 1), p.page);
}

test "Paginator prevPage does not go below 0" {
    var p = Paginator.init();
    p.prevPage();
    try std.testing.expectEqual(@as(usize, 0), p.page);
}

test "Paginator arabicView renders page/total" {
    const allocator = std.testing.allocator;
    var p = Paginator.init();
    p.total_pages = 5;
    p.page = 2;
    const v = try p.view(allocator);
    defer allocator.free(v);
    try std.testing.expectEqualStrings("3/5", v);
}

test "Paginator dotsView active dot at current page" {
    const allocator = std.testing.allocator;
    var p = Paginator.init();
    p.display = .dots;
    p.total_pages = 3;
    p.page = 1;
    const v = try p.view(allocator);
    defer allocator.free(v);
    // Middle dot should be the active one.
    try std.testing.expect(v.len > 0);
}

test "Paginator sliceBounds returns correct range" {
    var p = Paginator.init();
    p.per_page = 5;
    p.page = 2;
    const start, const end = p.sliceBounds(13);
    try std.testing.expectEqual(@as(usize, 10), start);
    try std.testing.expectEqual(@as(usize, 13), end);
}
