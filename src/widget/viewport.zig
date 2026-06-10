// SPDX-License-Identifier: MIT

// viewport:  Displays a subset of content lines within
// a fixed width x height window.  Supports vertical scrolling via keystrokes
// or programmatic scroll commands.  No Cmd; pure state.
const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const key = @import("key.zig");

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
        .desc = "go to end",
    },
};

pub const Viewport = struct {
    width: u16 = 0,
    height: u16 = 0,
    y_offset: usize = 0,
    fill_height: bool = false,
    soft_wrap: bool = true,
    style_: style.Style = style.Style.init(),
    keymap: KeyMap = .{},

    // Internal: lines of the current content, split at newlines.
    // Owned by the caller's allocator via setContent(); Viewport holds a
    // reference and does not free them.
    lines: []const []const u8 = &.{},

    // lifecycle
    pub fn init(width: u16, height: u16) Viewport {
        return .{ .width = width, .height = height };
    }

    /// Split content into lines and store them.
    /// Caller must keep content alive while Viewport uses it.
    /// lines slice is allocated with allocator; caller owns it.
    pub fn setContent(
        self: *Viewport,
        content: []const u8,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}![]const []const u8 {
        const ls = try ansi.str.splitLines(content, allocator);
        self.lines = ls;
        // Clamp scroll offset after content change.
        self.clampOffset();
        return ls;
    }

    // scroll queries

    pub fn totalLineCount(self: Viewport) usize {
        return self.lines.len;
    }

    pub fn visibleLineCount(self: Viewport) usize {
        return @min(self.height, self.lines.len -| self.y_offset);
    }

    pub fn atTop(self: Viewport) bool {
        return self.y_offset == 0;
    }
    pub fn atBottom(self: Viewport) bool {
        return self.y_offset >= self.maxOffset();
    }

    pub fn scrollPercent(self: Viewport) f32 {
        const max = self.maxOffset();
        if (max == 0) return 1.0;
        return @as(f32, @floatFromInt(self.y_offset)) / @as(f32, @floatFromInt(max));
    }

    fn maxOffset(self: Viewport) usize {
        return self.lines.len -| self.height;
    }

    // programmatic scroll

    pub fn scrollUp(self: *Viewport, n: usize) void {
        if (self.y_offset < n) {
            self.y_offset = 0;
        } else {
            self.y_offset -= n;
        }
    }

    pub fn scrollDown(self: *Viewport, n: usize) void {
        self.y_offset = @min(self.y_offset + n, self.maxOffset());
    }

    pub fn gotoTop(self: *Viewport) void {
        self.y_offset = 0;
    }
    pub fn gotoBottom(self: *Viewport) void {
        self.y_offset = self.maxOffset();
    }

    pub fn setYOffset(self: *Viewport, n: usize) void {
        self.y_offset = @min(n, self.maxOffset());
    }

    fn clampOffset(self: *Viewport) void {
        self.y_offset = @min(self.y_offset, self.maxOffset());
    }

    // update

    /// Handle a KeyEvent; returns the updated Viewport (pure value).
    pub fn update(self: Viewport, ev: ansi.KeyEvent) Viewport {
        var vp = self;
        const half: usize = @max(1, vp.height / 2);
        if (key.matches(ev, vp.keymap.up)) vp.scrollUp(1) else if (key.matches(ev, vp.keymap.down)) vp.scrollDown(1) else if (key.matches(ev, vp.keymap.page_up)) vp.scrollUp(vp.height) else if (key.matches(ev, vp.keymap.page_down)) vp.scrollDown(vp.height) else if (key.matches(ev, vp.keymap.half_page_up)) vp.scrollUp(half) else if (key.matches(ev, vp.keymap.half_page_down)) vp.scrollDown(half) else if (key.matches(ev, vp.keymap.goto_top)) vp.gotoTop() else if (key.matches(ev, vp.keymap.goto_bottom)) vp.gotoBottom();
        return vp;
    }

    /// Render the visible portion of content.
    /// Returns a heap-allocated string; caller frees with allocator.free().
    pub fn view(self: Viewport, allocator: std.mem.Allocator) ![]u8 {
        if (self.lines.len == 0) {
            if (!self.fill_height) return allocator.dupe(u8, "");
            return renderBlankLines(allocator, self.height, self.width);
        }

        const start = @min(self.y_offset, self.lines.len);
        const end = @min(start + self.height, self.lines.len);
        const slice = self.lines[start..end];

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        for (slice, 0..) |ln, i| {
            // Soft-wrap or hard truncate to width.
            if (self.soft_wrap and self.width > 0) {
                const wrapped = try ansi.str.wrap(ln, self.width, allocator);
                defer allocator.free(wrapped);
                try out.appendSlice(allocator, wrapped);
            } else if (self.width > 0) {
                const truncated = try ansi.str.truncate(ln, self.width, allocator);
                defer allocator.free(truncated);
                try out.appendSlice(allocator, truncated);
            } else {
                try out.appendSlice(allocator, ln);
            }
            if (i < slice.len - 1) try out.append(allocator, '\n');
        }

        // Fill remaining height with blank lines when requested.
        if (self.fill_height and slice.len < self.height) {
            const blank_count = self.height - slice.len;
            for (0..blank_count) |_| {
                try out.append(allocator, '\n');
                if (self.width > 0) {
                    try out.appendNTimes(allocator, ' ', self.width);
                }
            }
        }

        const rendered = try out.toOwnedSlice(allocator);
        if (self.style_._props.border_style or
            self.style_._props.pad_left or
            self.style_._props.pad_right or
            self.style_._props.pad_top or
            self.style_._props.pad_bottom)
        {
            const styled = try self.style_.render(allocator, rendered);
            allocator.free(rendered);
            return styled;
        }
        return rendered;
    }
};

fn renderBlankLines(
    allocator: std.mem.Allocator,
    height: u16,
    width: u16,
) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (0..height) |i| {
        if (width > 0) try out.appendNTimes(allocator, ' ', width);
        if (i < @as(usize, height) - 1) try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

test "Viewport init defaults" {
    const vp = Viewport.init(80, 24);
    try std.testing.expectEqual(@as(u16, 80), vp.width);
    try std.testing.expectEqual(@as(u16, 24), vp.height);
    try std.testing.expect(vp.atTop());
}

test "Viewport scrollDown clamps at bottom" {
    var vp = Viewport.init(80, 5);
    vp.lines = &.{ "a", "b", "c" };
    vp.scrollDown(100);
    try std.testing.expect(vp.atBottom());
}

test "Viewport scrollUp clamps at top" {
    var vp = Viewport.init(80, 5);
    vp.lines = &.{ "a", "b", "c", "d", "e", "f", "g" };
    vp.scrollDown(3);
    vp.scrollUp(100);
    try std.testing.expectEqual(@as(usize, 0), vp.y_offset);
}

test "Viewport view returns correct visible lines" {
    const allocator = std.testing.allocator;
    var vp = Viewport.init(80, 3);
    const content = "line1\nline2\nline3\nline4\nline5";
    const ls = try vp.setContent(content, allocator);
    defer allocator.free(ls);
    vp.y_offset = 1;
    const v = try vp.view(allocator);
    defer allocator.free(v);
    try std.testing.expect(std.mem.startsWith(u8, v, "line2"));
}

test "Viewport atBottom true when y_offset == maxOffset" {
    var vp = Viewport.init(80, 3);
    vp.lines = &.{ "a", "b", "c", "d", "e" };
    vp.y_offset = 2;
    try std.testing.expect(vp.atBottom());
}

test "Viewport scrollPercent 0 at top" {
    var vp = Viewport.init(80, 3);
    vp.lines = &.{ "a", "b", "c", "d", "e" };
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vp.scrollPercent(), 0.001);
}

test "Viewport scrollPercent 1 at bottom" {
    var vp = Viewport.init(80, 3);
    vp.lines = &.{ "a", "b", "c", "d", "e" };
    vp.gotoBottom();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), vp.scrollPercent(), 0.001);
}
