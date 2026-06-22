// SPDX-License-Identifier: MIT

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const key = @import("key.zig");

const ELLIPSIS = "\xe2\x80\xa6";

pub const Column = struct {
    title: []const u8 = "",
    width: u16 = 0,
    align_h: style.Pos = style.LEFT,
};

pub const Row = []const []const u8;

pub const KeyMap = struct {
    up: key.Binding = .{
        .codes = &.{ .up, .{ .char = 'k' } },
        .key_display = "↑/k",
        .desc = "up",
    },
    down: key.Binding = .{
        .codes = &.{ .down, .{ .char = 'j' } },
        .key_display = "↓/j",
        .desc = "down",
    },
    page_up: key.Binding = .{
        .codes = &.{ .page_up, .{ .char = 'b' } },
        .key_display = "pgup/b",
        .desc = "page up",
    },
    page_down: key.Binding = .{
        .codes = &.{ .page_down, .{ .char = 'f' }, .{ .char = ' ' } },
        .key_display = "pgdn/f",
        .desc = "page down",
    },
    half_page_up: key.Binding = .{
        .codes = &.{.{ .char = 'u' }},
        .mods = .{ .ctrl = true },
        .key_display = "ctrl+u",
        .desc = "half page up",
    },
    half_page_down: key.Binding = .{
        .codes = &.{.{ .char = 'd' }},
        .mods = .{ .ctrl = true },
        .key_display = "ctrl+d",
        .desc = "half page down",
    },
    goto_top: key.Binding = .{
        .codes = &.{ .home, .{ .char = 'g' } },
        .key_display = "g/home",
        .desc = "go to top",
    },
    goto_bottom: key.Binding = .{
        .codes = &.{ .end, .{ .char = 'G' } },
        .key_display = "G/end",
        .desc = "go to bottom",
    },
};

pub const Table = struct {
    columns: []const Column = &.{},
    rows: []const Row = &.{},

    cursor: usize = 0,
    offset: usize = 0,

    // display config
    height: u16 = 0,
    show_header: bool = true,
    cell_padding_x: u16 = 1,
    truncate_suffix: []const u8 = ELLIPSIS,
    empty_text: []const u8 = "No rows.",

    focus: bool = false,

    border_style: style.Border = style.NONE,
    show_column_dividers: bool = true,
    border_fg: ansi.Color = .none,

    header_style: style.Style = style.Style.init().bold_(true),
    cell_style: style.Style = style.Style.init(),
    selected_style: style.Style = style.Style.init().bold_(true).fg_(.{ .ansi16 = .bright_magenta }),

    keymap: KeyMap = .{},

    pub fn init(columns: []const Column, rows: []const Row, height: u16) Table {
        var t = Table{ .columns = columns, .height = height };
        t.setRows(rows);
        return t;
    }

    pub fn setColumns(self: *Table, new_columns: []const Column) void {
        self.columns = new_columns;
    }

    pub fn setRows(self: *Table, new_rows: []const Row) void {
        self.rows = new_rows;
        if (self.rows.len == 0) {
            self.cursor = 0;
            self.offset = 0;
            return;
        }
        self.cursor = @min(self.cursor, self.rows.len - 1);
        self.ensureCursorVisible();
    }

    pub fn setHeight(self: *Table, new_height: u16) void {
        self.height = new_height;
        self.ensureCursorVisible();
    }

    pub fn setCursor(self: *Table, n: usize) void {
        if (self.rows.len == 0) {
            self.cursor = 0;
            self.offset = 0;
            return;
        }
        self.cursor = @min(n, self.rows.len - 1);
        self.ensureCursorVisible();
    }

    pub fn moveUp(self: *Table, n: usize) void {
        self.setCursor(self.cursor -| n);
    }

    pub fn moveDown(self: *Table, n: usize) void {
        self.setCursor(self.cursor +| n);
    }

    pub fn gotoTop(self: *Table) void {
        self.setCursor(0);
    }

    pub fn gotoBottom(self: *Table) void {
        if (self.rows.len == 0) {
            self.cursor = 0;
            self.offset = 0;
            return;
        }
        self.setCursor(self.rows.len - 1);
    }

    pub fn focus_(self: *Table) void {
        self.focus = true;
    }

    pub fn blur(self: *Table) void {
        self.focus = false;
    }

    pub fn selectedRow(self: Table) ?Row {
        if (self.rows.len == 0 or self.cursor >= self.rows.len) return null;
        return self.rows[self.cursor];
    }

    pub fn visibleRowRange(self: Table) struct { usize, usize } {
        if (self.rows.len == 0) return .{ 0, 0 };
        const end = if (self.height == 0) self.rows.len else @min(self.offset + self.height, self.rows.len);
        return .{ self.offset, end };
    }

    pub fn update(self: Table, ev: ansi.KeyEvent) Table {
        var t = self;
        if (!t.focus or t.rows.len == 0) return t;

        const page: usize = @max(@as(usize, t.height), 1);
        const half_page: usize = @max(page / 2, 1);

        if (key.matches(ev, t.keymap.up)) {
            t.moveUp(1);
        } else if (key.matches(ev, t.keymap.down)) {
            t.moveDown(1);
        } else if (key.matches(ev, t.keymap.page_up)) {
            t.moveUp(page);
        } else if (key.matches(ev, t.keymap.page_down)) {
            t.moveDown(page);
        } else if (key.matches(ev, t.keymap.half_page_up)) {
            t.moveUp(half_page);
        } else if (key.matches(ev, t.keymap.half_page_down)) {
            t.moveDown(half_page);
        } else if (key.matches(ev, t.keymap.goto_top)) {
            t.gotoTop();
        } else if (key.matches(ev, t.keymap.goto_bottom)) {
            t.gotoBottom();
        }
        return t;
    }

    pub fn view(self: Table, allocator: std.mem.Allocator) ![]u8 {
        if (self.columns.len == 0) return allocator.dupe(u8, "");

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        const border_active = self.borderActive();
        const b = self.border_style;

        if (border_active and b.topSize() > 0) {
            try self.appendHorizontalRule(&out, allocator, b.top_left, b.mid_top, b.top_right);
            try out.append(allocator, '\n');
        }

        if (self.show_header) {
            try self.appendHeaderLine(&out, allocator, border_active);
            try out.append(allocator, '\n');
            if (border_active) {
                try self.appendHorizontalRule(&out, allocator, b.mid_left, b.middle, b.mid_right);
                try out.append(allocator, '\n');
            }
        }

        if (self.rows.len == 0) {
            if (border_active) {
                const left_glyph = try self.borderGlyph(allocator, b.left);
                defer allocator.free(left_glyph);
                try out.appendSlice(allocator, left_glyph);
            }
            try out.appendSlice(allocator, self.empty_text);
            if (border_active) {
                const right_glyph = try self.borderGlyph(allocator, b.right);
                defer allocator.free(right_glyph);
                try out.appendSlice(allocator, right_glyph);
            }
        } else {
            const range = self.visibleRowRange();
            const window = self.rows[range[0]..range[1]];
            for (window, 0..) |row, rel_idx| {
                const global_idx = range[0] + rel_idx;
                try self.appendDataLine(&out, allocator, row, global_idx == self.cursor, border_active);
                if (rel_idx < window.len - 1) try out.append(allocator, '\n');
            }
        }

        if (border_active and b.bottomSize() > 0) {
            try out.append(allocator, '\n');
            try self.appendHorizontalRule(&out, allocator, b.bottom_left, b.mid_bottom, b.bottom_right);
        }

        return out.toOwnedSlice(allocator);
    }

    // private helpers

    fn ensureCursorVisible(self: *Table) void {
        if (self.height == 0) {
            self.offset = 0;
            return;
        }
        if (self.cursor < self.offset) {
            self.offset = self.cursor;
        } else if (self.cursor >= self.offset + self.height) {
            self.offset = self.cursor + 1 - self.height;
        }
        self.offset = @min(self.offset, self.maxOffset());
    }

    fn maxOffset(self: Table) usize {
        if (self.height == 0) return 0;
        return self.rows.len -| self.height;
    }

    fn borderActive(self: Table) bool {
        return self.border_style.leftSize() > 0 or self.border_style.rightSize() > 0;
    }

    fn hasBorderColor(self: Table) bool {
        return switch (self.border_fg) {
            .none => false,
            else => true,
        };
    }

    fn borderGlyph(self: Table, allocator: std.mem.Allocator, glyph: []const u8) ![]u8 {
        if (!self.hasBorderColor()) return allocator.dupe(u8, glyph);
        return style.Style.init().fg_(self.border_fg).render(allocator, glyph);
    }

    fn appendHorizontalRule(
        self: Table,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        left: []const u8,
        junction: []const u8,
        right: []const u8,
    ) !void {
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(allocator);

        try line.appendSlice(allocator, left);

        var rendered_any = false;
        for (self.columns) |column| {
            if (column.width == 0) continue;
            if (rendered_any and self.show_column_dividers) try line.appendSlice(allocator, junction);
            rendered_any = true;

            const slot_width: u32 = @as(u32, column.width) + 2 * @as(u32, self.cell_padding_x);
            var n: u32 = 0;
            while (n < slot_width) : (n += 1) try line.appendSlice(allocator, self.border_style.top);
        }

        try line.appendSlice(allocator, right);

        if (self.hasBorderColor()) {
            const colored = try style.Style.init().fg_(self.border_fg).render(allocator, line.items);
            defer allocator.free(colored);
            try out.appendSlice(allocator, colored);
        } else {
            try out.appendSlice(allocator, line.items);
        }
    }

    fn appendCellContent(
        self: Table,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        texts: []const []const u8,
        border_active: bool,
    ) !void {
        const b = self.border_style;
        const divider: []const u8 = if (border_active) b.left else "";

        var rendered_any = false;
        for (self.columns, 0..) |column, i| {
            if (column.width == 0) continue;
            if (rendered_any and border_active and self.show_column_dividers) {
                try out.appendSlice(allocator, divider);
            }
            rendered_any = true;

            const text = if (i < texts.len) texts[i] else "";

            const truncated = try truncateCell(allocator, text, column.width, self.truncate_suffix);
            defer allocator.free(truncated);
            const aligned = try style.placeH(allocator, column.width, column.align_h, truncated);
            defer allocator.free(aligned);

            try out.appendNTimes(allocator, ' ', self.cell_padding_x);
            try out.appendSlice(allocator, aligned);
            try out.appendNTimes(allocator, ' ', self.cell_padding_x);
        }
    }

    fn coloredBorderGlyph(self: Table, allocator: std.mem.Allocator, glyph: []const u8) ![]u8 {
        if (!self.hasBorderColor()) return allocator.dupe(u8, glyph);
        return style.Style.init().fg_(self.border_fg).render(allocator, glyph);
    }

    fn appendRowLine(
        self: Table,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        texts: []const []const u8,
        row_style: style.Style,
        border_active: bool,
    ) !void {
        const b = self.border_style;

        if (border_active) {
            const left = try self.coloredBorderGlyph(allocator, b.left);
            defer allocator.free(left);
            try out.appendSlice(allocator, left);
        }

        var cells: std.ArrayList(u8) = .empty;
        defer cells.deinit(allocator);
        try self.appendCellContent(&cells, allocator, texts, border_active);
        const styled = try row_style.render(allocator, cells.items);
        defer allocator.free(styled);
        try out.appendSlice(allocator, styled);

        if (border_active) {
            const right = try self.coloredBorderGlyph(allocator, b.right);
            defer allocator.free(right);
            try out.appendSlice(allocator, right);
        }
    }

    fn appendHeaderLine(
        self: Table,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        border_active: bool,
    ) !void {
        const titles = try allocator.alloc([]const u8, self.columns.len);
        defer allocator.free(titles);
        for (self.columns, 0..) |column, i| titles[i] = column.title;
        try self.appendRowLine(out, allocator, titles, self.header_style, border_active);
    }

    fn appendDataLine(
        self: Table,
        out: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        row: Row,
        is_selected: bool,
        border_active: bool,
    ) !void {
        const row_style = if (is_selected) self.selected_style else self.cell_style;
        try self.appendRowLine(out, allocator, row, row_style, border_active);
    }
};

fn truncateCell(
    allocator: std.mem.Allocator,
    text: []const u8,
    width: u16,
    suffix: []const u8,
) ![]u8 {
    if (ansi.strWidth(text) <= @as(usize, width)) return allocator.dupe(u8, text);
    if (width == 0) return allocator.dupe(u8, "");

    const suffix_w: u16 = @intCast(ansi.strWidth(suffix));
    if (suffix_w >= width) return ansi.str.truncate(text, @as(usize, width), allocator);

    const head = try ansi.str.truncate(text, @as(usize, width - suffix_w), allocator);
    defer allocator.free(head);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, head);
    try out.appendSlice(allocator, suffix);
    return out.toOwnedSlice(allocator);
}

const testing = std.testing;

fn makeTable(columns: []const Column, rows: []const Row, height: u16) Table {
    return Table.init(columns, rows, height);
}

test "Table init defaults" {
    const t = Table.init(&.{}, &.{}, 0);
    try testing.expectEqual(@as(usize, 0), t.cursor);
    try testing.expectEqual(@as(usize, 0), t.offset);
    try testing.expectEqual(@as(usize, 0), t.columns.len);
    try testing.expectEqual(@as(usize, 0), t.rows.len);
    try testing.expect(!t.focus);
}

test "Table setRows clamps cursor when the new rows are shorter" {
    const cols = [_]Column{.{ .title = "Name", .width = 8 }};
    const cell = [_][]const u8{"x"};
    const rows3 = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows3, 5);
    t.setCursor(2);
    const rows1 = [_]Row{&cell};
    t.setRows(&rows1);
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table setRows resets cursor and offset when emptied" {
    const cols = [_]Column{.{ .title = "Name", .width = 8 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.setCursor(1);
    t.setRows(&.{});
    try testing.expectEqual(@as(usize, 0), t.cursor);
    try testing.expectEqual(@as(usize, 0), t.offset);
}

test "Table setColumns replaces columns without touching the cursor" {
    const cols1 = [_]Column{.{ .title = "A", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell };
    var t = makeTable(&cols1, &rows, 5);
    t.setCursor(1);
    const cols2 = [_]Column{ .{ .title = "B", .width = 4 }, .{ .title = "C", .width = 4 } };
    t.setColumns(&cols2);
    try testing.expectEqual(@as(usize, 2), t.columns.len);
    try testing.expectEqual(@as(usize, 1), t.cursor);
}

test "Table setHeight recalculates the visible window" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell, &cell, &cell, &cell, &cell, &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 3);
    t.setCursor(9);
    try testing.expectEqual(@as(usize, 7), t.offset);
    t.setHeight(5);
    try testing.expectEqual(@as(usize, 5), t.offset);
}

test "Table moveDown advances the cursor by one" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.moveDown(1);
    try testing.expectEqual(@as(usize, 1), t.cursor);
}

test "Table moveDown stops at the last row on overflow" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.moveDown(50);
    try testing.expectEqual(@as(usize, 1), t.cursor);
}

test "Table moveUp does not underflow below zero" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.setCursor(1);
    t.moveUp(50);
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table gotoTop jumps to the first row" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.setCursor(2);
    t.gotoTop();
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table gotoBottom jumps to the last row" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.gotoBottom();
    try testing.expectEqual(@as(usize, 2), t.cursor);
}

test "Table gotoBottom on empty rows is safe" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    var t = makeTable(&cols, &.{}, 5);
    t.gotoBottom();
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table moveDown does not scroll until the cursor reaches the window edge" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 3);
    t.moveDown(1);
    t.moveDown(1);
    try testing.expectEqual(@as(usize, 2), t.cursor);
    try testing.expectEqual(@as(usize, 0), t.offset);
    t.moveDown(1);
    try testing.expectEqual(@as(usize, 3), t.cursor);
    try testing.expectEqual(@as(usize, 1), t.offset);
}

test "Table update moves the cursor down when focused" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.focus_();
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 1), t.cursor);
}

test "Table update ignores key events while blurred" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table moveDown still works while blurred" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.moveDown(1);
    try testing.expectEqual(@as(usize, 1), t.cursor);
}

test "Table update ignores key events when there are no rows" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    var t = makeTable(&cols, &.{}, 5);
    t.focus_();
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 0), t.cursor);
}

test "Table update page_down moves by the configured height" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    var rows: [20]Row = undefined;
    for (0..20) |i| rows[i] = &cell;
    var t = makeTable(&cols, &rows, 4);
    t.focus_();
    const ev = ansi.KeyEvent{ .code = .page_down, .mods = .{} };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 4), t.cursor);
}

test "Table update half_page_down moves by half the configured height" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    var rows: [20]Row = undefined;
    for (0..20) |i| rows[i] = &cell;
    var t = makeTable(&cols, &rows, 8);
    t.focus_();
    const ev = ansi.KeyEvent{ .code = .{ .char = 'd' }, .mods = .{ .ctrl = true } };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 4), t.cursor);
}

test "Table update goto_bottom via G jumps to the last row" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell, &cell };
    var t = makeTable(&cols, &rows, 2);
    t.focus_();
    const ev = ansi.KeyEvent{ .code = .{ .char = 'G' }, .mods = .{} };
    t = t.update(ev);
    try testing.expectEqual(@as(usize, 3), t.cursor);
}

test "Table selectedRow returns null when there are no rows" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const t = makeTable(&cols, &.{}, 5);
    try testing.expect(t.selectedRow() == null);
}

test "Table selectedRow returns the row at the cursor" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const r0 = [_][]const u8{"first"};
    const r1 = [_][]const u8{"second"};
    const rows = [_]Row{ &r0, &r1 };
    var t = makeTable(&cols, &rows, 5);
    t.setCursor(1);
    const sel = t.selectedRow().?;
    try testing.expectEqualStrings("second", sel[0]);
}

test "Table visibleRowRange reflects the scroll window" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    var rows: [10]Row = undefined;
    for (0..10) |i| rows[i] = &cell;
    var t = makeTable(&cols, &rows, 4);
    t.setCursor(9);
    const range = t.visibleRowRange();
    try testing.expectEqual(@as(usize, 6), range[0]);
    try testing.expectEqual(@as(usize, 10), range[1]);
}

test "Table visibleRowRange with height zero shows every row" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    const cell = [_][]const u8{"x"};
    const rows = [_]Row{ &cell, &cell, &cell };
    const t = makeTable(&cols, &rows, 0);
    const range = t.visibleRowRange();
    try testing.expectEqual(@as(usize, 0), range[0]);
    try testing.expectEqual(@as(usize, 3), range[1]);
}

test "Table focus_ and blur toggle the focus flag" {
    const cols = [_]Column{.{ .title = "N", .width = 4 }};
    var t = makeTable(&cols, &.{}, 5);
    try testing.expect(!t.focus);
    t.focus_();
    try testing.expect(t.focus);
    t.blur();
    try testing.expect(!t.focus);
}

test "Table view with no columns returns an empty string" {
    const alloc = testing.allocator;
    const t = makeTable(&.{}, &.{}, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expectEqual(@as(usize, 0), v.len);
}

test "Table view shows empty_text when there are no rows" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 8 }};
    var t = makeTable(&cols, &.{}, 5);
    t.empty_text = "Nothing here.";
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Nothing here.") != null);
}

test "Table view renders the header and row content" {
    const alloc = testing.allocator;
    const cols = [_]Column{ .{ .title = "Name", .width = 8 }, .{ .title = "Age", .width = 4 } };
    const r0 = [_][]const u8{ "Ada", "32" };
    const rows = [_]Row{&r0};
    const t = makeTable(&cols, &rows, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Name") != null);
    try testing.expect(std.mem.indexOf(u8, v, "Age") != null);
    try testing.expect(std.mem.indexOf(u8, v, "Ada") != null);
    try testing.expect(std.mem.indexOf(u8, v, "32") != null);
}

test "Table view skips the header when show_header is false" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 8 }};
    const r0 = [_][]const u8{"Ada"};
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.show_header = false;
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Name") == null);
    try testing.expect(std.mem.indexOf(u8, v, "Ada") != null);
}

test "Table view hides columns with width zero" {
    const alloc = testing.allocator;
    const cols = [_]Column{ .{ .title = "Visible", .width = 8 }, .{ .title = "Hidden", .width = 0 } };
    const r0 = [_][]const u8{ "yes", "no" };
    const rows = [_]Row{&r0};
    const t = makeTable(&cols, &rows, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Visible") != null);
    try testing.expect(std.mem.indexOf(u8, v, "Hidden") == null);
}

test "Table view truncates long content with an ellipsis" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 5 }};
    const r0 = [_][]const u8{"Supercalifragilistic"};
    const rows = [_]Row{&r0};
    const t = makeTable(&cols, &rows, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, ELLIPSIS) != null);
    try testing.expect(std.mem.indexOf(u8, v, "Supercalifragilistic") == null);
}

test "Table view does not truncate content that fits exactly" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 7 }};
    const r0 = [_][]const u8{"Foooooo"};
    const rows = [_]Row{&r0};
    const t = makeTable(&cols, &rows, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "Foooooo") != null);
    try testing.expect(std.mem.indexOf(u8, v, ELLIPSIS) == null);
}

test "Table view renders only the rows within the scroll window" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "N", .width = 8 }};
    const first = [_][]const u8{"firstrow"};
    const filler = [_][]const u8{"x"};
    const last = [_][]const u8{"lastrowx"};
    var rows: [10]Row = undefined;
    rows[0] = &first;
    for (1..9) |i| rows[i] = &filler;
    rows[9] = &last;
    var t = makeTable(&cols, &rows, 3);
    t.setCursor(9);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "lastrowx") != null);
    try testing.expect(std.mem.indexOf(u8, v, "firstrow") == null);
}

test "Table view styles the selected row differently from other rows" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "N", .width = 8 }};
    const cell = [_][]const u8{"same"};
    const rows = [_]Row{ &cell, &cell };
    var t = makeTable(&cols, &rows, 5);
    t.show_header = false;

    t.setCursor(0);
    const v0 = try t.view(alloc);
    defer alloc.free(v0);

    t.setCursor(1);
    const v1 = try t.view(alloc);
    defer alloc.free(v1);

    try testing.expect(!std.mem.eql(u8, v0, v1));
}

test "Table view aligns column content according to align_h" {
    const alloc = testing.allocator;
    const r0 = [_][]const u8{"42"};
    const rows = [_]Row{&r0};

    const cols_left = [_]Column{.{ .title = "N", .width = 6, .align_h = style.LEFT }};
    var t_left = makeTable(&cols_left, &rows, 5);
    t_left.show_header = false;

    t_left.selected_style = style.Style.init();
    const v_left = try t_left.view(alloc);
    defer alloc.free(v_left);

    const cols_right = [_]Column{.{ .title = "N", .width = 6, .align_h = style.RIGHT }};
    var t_right = makeTable(&cols_right, &rows, 5);
    t_right.show_header = false;
    t_right.selected_style = style.Style.init();
    const v_right = try t_right.view(alloc);
    defer alloc.free(v_right);

    try testing.expect(!std.mem.eql(u8, v_left, v_right));
    try testing.expect(std.mem.startsWith(u8, v_left, " 42"));
    try testing.expect(std.mem.startsWith(u8, v_right, "     42"));
}

test "Table view with NONE border draws no box characters" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 5 }};
    const r0 = [_][]const u8{"Ada"};
    const rows = [_]Row{&r0};
    const t = makeTable(&cols, &rows, 5);
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x82") == null);
}

test "Table view with a border draws top, header divider, and bottom edges" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 5 }};
    const r0 = [_][]const u8{"Ada"};
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.border_style = style.NORMAL;
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x8c") != null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x9c") != null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x94") != null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x82") != null);
}

test "Table view with a border but no header skips the header divider" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 5 }};
    const r0 = [_][]const u8{"Ada"};
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.border_style = style.NORMAL;
    t.show_header = false;
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x9c") == null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x8c") != null);
}

test "Table view with show_column_dividers false draws an outer box but no inner verticals" {
    const alloc = testing.allocator;
    const cols = [_]Column{ .{ .title = "City", .width = 8 }, .{ .title = "Country", .width = 8 } };
    const r0 = [_][]const u8{ "Tokyo", "Japan" };
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.border_style = style.NORMAL;
    t.show_column_dividers = false;
    const v = try t.view(alloc);
    defer alloc.free(v);

    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x8c") != null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x82") != null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\xac") == null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\xbc") == null);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80") != null);
}

test "Table view with show_column_dividers true (default) draws inner verticals" {
    const alloc = testing.allocator;
    const cols = [_]Column{ .{ .title = "City", .width = 8 }, .{ .title = "Country", .width = 8 } };
    const r0 = [_][]const u8{ "Tokyo", "Japan" };
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.border_style = style.NORMAL;
    const v = try t.view(alloc);
    defer alloc.free(v);
    try testing.expect(std.mem.indexOf(u8, v, "\xe2\x94\xac") != null);
}

test "Table view with border_fg colors the border glyphs" {
    const alloc = testing.allocator;
    const cols = [_]Column{.{ .title = "Name", .width = 5 }};
    const r0 = [_][]const u8{"Ada"};
    const rows = [_]Row{&r0};
    var t = makeTable(&cols, &rows, 5);
    t.border_style = style.NORMAL;
    t.border_fg = .{ .ansi16 = .bright_black };

    const colored = try t.view(alloc);
    defer alloc.free(colored);

    t.border_fg = .none;
    const plain = try t.view(alloc);
    defer alloc.free(plain);

    try testing.expect(colored.len > plain.len);
    try testing.expect(!std.mem.eql(u8, colored, plain));
}

test "truncateCell leaves short text unchanged" {
    const alloc = testing.allocator;
    const out = try truncateCell(alloc, "hi", 10, ELLIPSIS);
    defer alloc.free(out);
    try testing.expectEqualStrings("hi", out);
}

test "truncateCell appends an ellipsis when content overflows" {
    const alloc = testing.allocator;
    const out = try truncateCell(alloc, "Supercalifragilistic", 5, ELLIPSIS);
    defer alloc.free(out);
    try testing.expect(std.mem.endsWith(u8, out, ELLIPSIS));
    try testing.expectEqual(@as(usize, 5), ansi.strWidth(out));
}

test "truncateCell falls back to plain truncation when width cannot fit the suffix" {
    const alloc = testing.allocator;
    const out = try truncateCell(alloc, "hello", 1, ELLIPSIS);
    defer alloc.free(out);
    try testing.expect(!std.mem.endsWith(u8, out, ELLIPSIS));
}

test "truncateCell with an empty suffix behaves like plain truncation" {
    const alloc = testing.allocator;
    const out = try truncateCell(alloc, "hello world", 5, "");
    defer alloc.free(out);
    try testing.expectEqualStrings("hello", out);
}
