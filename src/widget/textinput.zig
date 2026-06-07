// SPDX-License-Identifier: MIT

// textinput.zig - single-line text input widget.
//
// textinput:  Single line, horizontal scroll when width
// is set.  Supports password echo, character limit, and validation.
// No Cmd produced; all state is updated synchronously in update().
//
// Imports: std, fern_ansi, fern_style, key.zig.

const std = @import("std");
const ansi = @import("fern_ansi");
const style = @import("fern_style");
const key = @import("key.zig");

// ---------------------------------------------------------------------------
// EchoMode
// ---------------------------------------------------------------------------

pub const EchoMode = enum {
    normal, // display as typed
    password, // display echo_char for every character
    none, // display nothing
};

// ---------------------------------------------------------------------------
// KeyMap (mirrors bubbles/textinput)
// ---------------------------------------------------------------------------

pub const KeyMap = struct {
    char_forward: key.Binding = .{ .codes = &.{.right} },
    char_backward: key.Binding = .{ .codes = &.{.left} },
    word_forward: key.Binding = .{ .codes = &.{.right}, .mods = .{ .alt = true } },
    word_backward: key.Binding = .{ .codes = &.{.left}, .mods = .{ .alt = true } },
    delete_char_backward: key.Binding = .{ .codes = &.{.backspace} },
    delete_char_forward: key.Binding = .{ .codes = &.{.delete} },
    delete_word_backward: key.Binding = .{ .codes = &.{.backspace}, .mods = .{ .alt = true } },
    delete_after_cursor: key.Binding = .{ .codes = &.{.{ .char = 'k' }}, .mods = .{ .ctrl = true } },
    delete_before_cursor: key.Binding = .{ .codes = &.{.{ .char = 'u' }}, .mods = .{ .ctrl = true } },
    line_start: key.Binding = .{ .codes = &.{ .home, .{ .char = 'a' } }, .mods = .{} },
    line_end: key.Binding = .{ .codes = &.{ .end, .{ .char = 'e' } }, .mods = .{} },
};

/// Returns true if the key is a printable rune (not a control sequence).
fn isPrintable(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .char => |c| c >= 0x20,
        else => false,
    };
}

// ---------------------------------------------------------------------------
// ValidateFunc
// ---------------------------------------------------------------------------

pub const ValidateError = error{Invalid};
pub const ValidateFn = *const fn ([]const u32) ValidateError!void;

// ---------------------------------------------------------------------------
// Style set for focused / blurred states
// ---------------------------------------------------------------------------

pub const Styles = struct {
    focused: style.Style = style.Style.init(),
    blurred: style.Style = style.Style.init(),
    cursor: style.Style = style.Style.init().reverse_(true),
    placeholder: style.Style = style.Style.init()
        .fg_(.{ .ansi16 = .bright_black }), // bright black (dark gray)
};

// ---------------------------------------------------------------------------
// TextInput
// ---------------------------------------------------------------------------

pub const TextInput = struct {
    // --- config ---
    prompt: []const u8 = "> ",
    placeholder: []const u8 = "",
    echo_mode: EchoMode = .normal,
    echo_char: u21 = '*',
    char_limit: usize = 0, // 0 = unlimited
    width: u16 = 0, // 0 = unlimited
    keymap: KeyMap = .{},
    styles: Styles = .{},
    validate: ?ValidateFn = null,

    // --- state ---
    value: std.ArrayList(u32) = .empty, // codepoints
    pos: usize = 0,
    focus: bool = false,
    offset: usize = 0, // leftmost visible codepoint index (viewport scroll)
    err: ?ValidateError = null,

    // --- lifecycle ----------------------------------------------------------

    pub fn init() TextInput {
        return .{};
    }

    pub fn deinit(self: *TextInput, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }

    // --- focus --------------------------------------------------------------

    pub fn focus_(self: *TextInput) void {
        self.focus = true;
    }
    pub fn blur(self: *TextInput) void {
        self.focus = false;
    }

    // --- value access -------------------------------------------------------

    /// Write the current value as UTF-8 into buf.  Returns the written slice.
    pub fn valueUtf8(self: TextInput, buf: []u8) []u8 {
        var n: usize = 0;
        for (self.value.items) |cp| {
            const cp_len = std.unicode.utf8CodepointSequenceLength(@intCast(cp)) catch continue;
            if (n + cp_len > buf.len) break;
            _ = std.unicode.utf8Encode(@intCast(cp), buf[n..]) catch continue;
            n += cp_len;
        }
        return buf[0..n];
    }

    /// Heap-allocate the current value as UTF-8.  Caller frees.
    pub fn valueOwned(self: TextInput, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        for (self.value.items) |cp| {
            var cp_buf: [4]u8 = undefined;
            const cp_len = std.unicode.utf8Encode(@intCast(cp), &cp_buf) catch continue;
            try out.appendSlice(allocator, cp_buf[0..cp_len]);
        }
        return out.toOwnedSlice(allocator);
    }

    /// Set the input value from a UTF-8 string.
    pub fn setValue(
        self: *TextInput,
        allocator: std.mem.Allocator,
        text: []const u8,
    ) !void {
        self.value.clearRetainingCapacity();
        var utf8_view = try std.unicode.Utf8View.init(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |cp| {
            if (self.char_limit > 0 and self.value.items.len >= self.char_limit) break;
            try self.value.append(allocator, cp);
        }
        self.pos = self.value.items.len;
        self.offset = 0;
        self.runValidate();
    }

    pub fn reset(self: *TextInput, allocator: std.mem.Allocator) void {
        self.value.clearRetainingCapacity();
        _ = allocator;
        self.pos = 0;
        self.offset = 0;
        self.err = null;
    }

    // --- validation ---------------------------------------------------------

    fn runValidate(self: *TextInput) void {
        if (self.validate) |vfn| {
            self.err = if (vfn(self.value.items)) |_| null else |err| err;
        }
    }

    // --- update -------------------------------------------------------------

    /// Handle a KeyEvent.  Returns true if the value changed (useful for
    /// the caller to decide whether to re-validate or send a message).
    pub fn update(
        self: *TextInput,
        ev: ansi.KeyEvent,
        allocator: std.mem.Allocator,
    ) !bool {
        if (!self.focus) return false;

        if (isPrintable(ev)) {
            const cp = ev.code.char;
            if (self.char_limit == 0 or self.value.items.len < self.char_limit) {
                try self.value.insert(allocator, self.pos, cp);
                self.pos += 1;
                self.updateOffset();
                self.runValidate();
                return true;
            }
            return false;
        }

        if (key.matches(ev, self.keymap.char_forward)) {
            if (self.pos < self.value.items.len) {
                self.pos += 1;
                self.updateOffset();
            }
        } else if (key.matches(ev, self.keymap.char_backward)) {
            if (self.pos > 0) {
                self.pos -= 1;
                self.updateOffset();
            }
        } else if (key.matches(ev, self.keymap.line_start)) {
            self.pos = 0;
            self.offset = 0;
        } else if (key.matches(ev, self.keymap.line_end)) {
            self.pos = self.value.items.len;
            self.updateOffset();
        } else if (key.matches(ev, self.keymap.delete_char_backward)) {
            if (self.pos > 0) {
                _ = self.value.orderedRemove(self.pos - 1);
                self.pos -= 1;
                self.updateOffset();
                self.runValidate();
                return true;
            }
        } else if (key.matches(ev, self.keymap.delete_char_forward)) {
            if (self.pos < self.value.items.len) {
                _ = self.value.orderedRemove(self.pos);
                self.runValidate();
                return true;
            }
        } else if (key.matches(ev, self.keymap.delete_after_cursor)) {
            self.value.items.len = self.pos;
            self.runValidate();
            return true;
        } else if (key.matches(ev, self.keymap.delete_before_cursor)) {
            if (self.pos > 0) {
                const removed = self.pos;
                std.mem.copyForwards(u32, self.value.items[0..], self.value.items[removed..]);
                self.value.items.len -= removed;
                self.pos = 0;
                self.offset = 0;
                self.runValidate();
                return true;
            }
        } else if (key.matches(ev, self.keymap.word_backward)) {
            self.pos = wordStart(self.value.items, self.pos);
            self.updateOffset();
        } else if (key.matches(ev, self.keymap.word_forward)) {
            self.pos = wordEnd(self.value.items, self.pos);
            self.updateOffset();
        } else if (key.matches(ev, self.keymap.delete_word_backward)) {
            const new_pos = wordStart(self.value.items, self.pos);
            const removed = self.pos - new_pos;
            std.mem.copyForwards(u32, self.value.items[new_pos..], self.value.items[self.pos..]);
            self.value.items.len -= removed;
            self.pos = new_pos;
            self.updateOffset();
            self.runValidate();
            return true;
        }

        return false;
    }

    // --- offset (horizontal viewport) ---------------------------------------

    fn updateOffset(self: *TextInput) void {
        if (self.width == 0) return;
        const visible: usize = self.width;
        // Scroll right: cursor past right edge.
        if (self.pos >= self.offset + visible) {
            self.offset = self.pos -| visible + 1;
        }
        // Scroll left: cursor before left edge.
        if (self.pos < self.offset) {
            self.offset = self.pos;
        }
    }

    // --- view ---------------------------------------------------------------

    /// Render the text input.  Caller owns the returned slice.
    pub fn view(self: TextInput, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        // Prompt.
        try out.appendSlice(allocator, self.prompt);

        const cps = self.value.items;
        if (cps.len == 0 and !self.focus) {
            // Placeholder when unfocused and empty.
            if (self.placeholder.len > 0) {
                const ph = try self.styles.placeholder.render(allocator, self.placeholder);
                defer allocator.free(ph);
                try out.appendSlice(allocator, ph);
            }
            return out.toOwnedSlice(allocator);
        }

        // Determine visible slice.
        const vis_start = @min(self.offset, cps.len);
        const vis_end = if (self.width > 0)
            @min(vis_start + self.width, cps.len)
        else
            cps.len;

        // Write each codepoint.  Cursor position gets cursor style applied.
        for (cps[vis_start..vis_end], vis_start..) |cp, ci| {
            var cp_buf: [4]u8 = undefined;
            const display_cp: u21 = switch (self.echo_mode) {
                .normal => @intCast(cp),
                .password => self.echo_char,
                .none => ' ',
            };
            const cp_len = std.unicode.utf8Encode(display_cp, &cp_buf) catch continue;
            const cp_str = cp_buf[0..cp_len];

            if (self.focus and ci == self.pos) {
                // Cursor is ON this character.
                const cs = try self.styles.cursor.render(allocator, cp_str);
                defer allocator.free(cs);
                try out.appendSlice(allocator, cs);
            } else {
                try out.appendSlice(allocator, cp_str);
            }
        }

        // Cursor after last character (when focus and pos == len).
        if (self.focus and self.pos == cps.len and
            (self.width == 0 or self.pos < self.offset + self.width))
        {
            const cs = try self.styles.cursor.render(allocator, " ");
            defer allocator.free(cs);
            try out.appendSlice(allocator, cs);
        }

        return out.toOwnedSlice(allocator);
    }
};

// --- word navigation helpers ------------------------------------------------

fn wordStart(cps: []const u32, pos: usize) usize {
    if (pos == 0) return 0;
    var i = pos;
    // Skip trailing spaces.
    while (i > 0 and cps[i - 1] == ' ') i -= 1;
    // Skip word chars.
    while (i > 0 and cps[i - 1] != ' ') i -= 1;
    return i;
}

fn wordEnd(cps: []const u32, pos: usize) usize {
    var i = pos;
    // Skip leading spaces.
    while (i < cps.len and cps[i] == ' ') i += 1;
    // Skip word chars.
    while (i < cps.len and cps[i] != ' ') i += 1;
    return i;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TextInput init empty" {
    const ti = TextInput.init();
    try std.testing.expectEqual(@as(usize, 0), ti.value.items.len);
    try std.testing.expectEqual(@as(usize, 0), ti.pos);
}

test "TextInput setValue sets value and pos" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    try ti.setValue(allocator, "hello");
    try std.testing.expectEqual(@as(usize, 5), ti.value.items.len);
    try std.testing.expectEqual(@as(usize, 5), ti.pos);
}

test "TextInput char_limit is enforced" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    ti.char_limit = 3;
    try ti.setValue(allocator, "hello");
    try std.testing.expectEqual(@as(usize, 3), ti.value.items.len);
}

test "TextInput update inserts printable char when focused" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    ti.focus = true;
    const ev = ansi.KeyEvent{ .code = .{ .char = 'a' }, .mods = .{} };
    _ = try ti.update(ev, allocator);
    try std.testing.expectEqual(@as(usize, 1), ti.value.items.len);
    try std.testing.expectEqual(@as(u32, 'a'), ti.value.items[0]);
}

test "TextInput update does nothing when blurred" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    ti.focus = false;
    const ev = ansi.KeyEvent{ .code = .{ .char = 'a' }, .mods = .{} };
    _ = try ti.update(ev, allocator);
    try std.testing.expectEqual(@as(usize, 0), ti.value.items.len);
}

test "TextInput backspace removes last char" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    ti.focus = true;
    try ti.setValue(allocator, "ab");
    const ev = ansi.KeyEvent{ .code = .backspace, .mods = .{} };
    _ = try ti.update(ev, allocator);
    try std.testing.expectEqual(@as(usize, 1), ti.value.items.len);
    try std.testing.expectEqual(@as(u32, 'a'), ti.value.items[0]);
}

test "TextInput wordStart finds start of word" {
    const cps: []const u32 = &.{ 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o' };
    try std.testing.expectEqual(@as(usize, 6), wordStart(cps, 8));
}

test "TextInput wordEnd finds end of word" {
    const cps: []const u32 = &.{ 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o' };
    try std.testing.expectEqual(@as(usize, 5), wordEnd(cps, 0));
}

test "TextInput reset clears value" {
    const allocator = std.testing.allocator;
    var ti = TextInput.init();
    defer ti.deinit(allocator);
    try ti.setValue(allocator, "hello");
    ti.reset(allocator);
    try std.testing.expectEqual(@as(usize, 0), ti.value.items.len);
}
