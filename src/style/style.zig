// SPDX-License-Identifier: MIT

// style.zig - Style builder and render pipeline
//
// Style is a value type; all setters return a new Style.
// render() owns all intermediate memory via an ArenaAllocator.
// The caller owns the final []u8 and frees it with allocator.free().

const std = @import("std");
const ansi = @import("fern_ansi");
const border = @import("border.zig");

const Border = border.Border;
const NONE = border.NONE;

// Import Pos and alignment constants from layout.zig.
// Defined there to avoid a cycle; re-exported through root.zig.
const layout = @import("layout.zig");
const Pos = layout.Pos;
const LEFT = layout.LEFT;
const RIGHT = layout.RIGHT;
const TOP = layout.TOP;
const BOTTOM = layout.BOTTOM;
const CENTER = layout.CENTER;

pub const TAB_WIDTH_DEFAULT: i16 = 4;

// Underline style mirrors ansi.Attrs.Underline so callers need only import
// this module.
pub const Underline = ansi.Attrs.Underline;

// --- Props bitmask (private) -------------------------------------------------
//
// Tracks which Style fields were explicitly set.
// inherit() uses this to distinguish "not set" from "explicitly zero".

const Props = packed struct(u64) {
    bold: bool = false,
    italic: bool = false,
    faint: bool = false,
    reverse: bool = false,
    blink: bool = false,
    strike: bool = false,
    underline_spaces: bool = false,
    strike_spaces: bool = false,
    color_ws: bool = false,
    underline: bool = false,
    fg: bool = false,
    bg: bool = false,
    ul_color: bool = false,
    width: bool = false,
    height: bool = false,
    align_h: bool = false,
    align_v: bool = false,
    pad_top: bool = false,
    pad_right: bool = false,
    pad_bottom: bool = false,
    pad_left: bool = false,
    margin_top: bool = false,
    margin_right: bool = false,
    margin_bottom: bool = false,
    margin_left: bool = false,
    margin_bg: bool = false,
    border_style: bool = false,
    border_top: bool = false,
    border_right: bool = false,
    border_bottom: bool = false,
    border_left: bool = false,
    border_top_fg: bool = false,
    border_right_fg: bool = false,
    border_bottom_fg: bool = false,
    border_left_fg: bool = false,
    border_top_bg: bool = false,
    border_right_bg: bool = false,
    border_bottom_bg: bool = false,
    border_left_bg: bool = false,
    inline_mode: bool = false,
    max_width: bool = false,
    max_height: bool = false,
    tab_width: bool = false,
    _pad: u21 = 0, // 43 bools + 21 bits = 64
};

comptime {
    std.debug.assert(@bitSizeOf(Props) == 64);
}

// --- Style struct ------------------------------------------------------------

pub const Style = struct {

    // --- bitmask (private) ---------------------------------------------------
    _props: Props = .{},

    // --- text attributes -----------------------------------------------------
    bold: bool = false,
    italic: bool = false,
    faint: bool = false,
    reverse: bool = false,
    blink: bool = false,
    strike: bool = false,
    underline_style: Underline = .none,
    underline_spaces: bool = false,
    strike_spaces: bool = false,
    // color_ws true: padding and margin spaces inherit the bg color
    color_ws: bool = true,

    // --- colors --------------------------------------------------------------
    fg: ansi.Color = .none,
    bg: ansi.Color = .none,
    ul_color: ansi.Color = .none,

    // --- sizing --------------------------------------------------------------
    width: u16 = 0, // 0 = auto
    height: u16 = 0, // 0 = auto
    max_width: u16 = 0, // 0 = no limit
    max_height: u16 = 0, // 0 = no limit

    // --- alignment -----------------------------------------------------------
    align_h: Pos = LEFT,
    align_v: Pos = TOP,

    // --- padding (inside border) ---------------------------------------------
    pad_top: u16 = 0,
    pad_right: u16 = 0,
    pad_bottom: u16 = 0,
    pad_left: u16 = 0,

    // --- margin (outside border) ---------------------------------------------
    margin_top: u16 = 0,
    margin_right: u16 = 0,
    margin_bottom: u16 = 0,
    margin_left: u16 = 0,
    margin_bg: ansi.Color = .none,

    // --- border --------------------------------------------------------------
    border_style: Border = NONE,
    border_top: bool = false,
    border_right: bool = false,
    border_bottom: bool = false,
    border_left: bool = false,
    border_top_fg: ansi.Color = .none,
    border_right_fg: ansi.Color = .none,
    border_bottom_fg: ansi.Color = .none,
    border_left_fg: ansi.Color = .none,
    border_top_bg: ansi.Color = .none,
    border_right_bg: ansi.Color = .none,
    border_bottom_bg: ansi.Color = .none,
    border_left_bg: ansi.Color = .none,

    // --- misc ----------------------------------------------------------------
    inline_mode: bool = false,
    // tab_width: -1 = leave tabs, 0 = strip, >0 = expand to N spaces
    tab_width: i16 = TAB_WIDTH_DEFAULT,

    // --- lifecycle -----------------------------------------------------------

    pub fn init() Style {
        return .{};
    }

    // --- setters (value-receiver; each returns a new Style) ------------------

    pub fn bold_(self: Style, on: bool) Style {
        var s = self;
        s.bold = on;
        s._props.bold = true;
        return s;
    }

    pub fn italic_(self: Style, on: bool) Style {
        var s = self;
        s.italic = on;
        s._props.italic = true;
        return s;
    }

    pub fn faint_(self: Style, on: bool) Style {
        var s = self;
        s.faint = on;
        s._props.faint = true;
        return s;
    }

    pub fn reverse_(self: Style, on: bool) Style {
        var s = self;
        s.reverse = on;
        s._props.reverse = true;
        return s;
    }

    pub fn blink_(self: Style, on: bool) Style {
        var s = self;
        s.blink = on;
        s._props.blink = true;
        return s;
    }

    pub fn strike_(self: Style, on: bool) Style {
        var s = self;
        s.strike = on;
        s._props.strike = true;
        return s;
    }

    // .none disables underline entirely.
    pub fn underline_(self: Style, style: Underline) Style {
        var s = self;
        s.underline_style = style;
        s._props.underline = true;
        return s;
    }

    pub fn underlineSpaces(self: Style, on: bool) Style {
        var s = self;
        s.underline_spaces = on;
        s._props.underline_spaces = true;
        return s;
    }

    pub fn strikeSpaces(self: Style, on: bool) Style {
        var s = self;
        s.strike_spaces = on;
        s._props.strike_spaces = true;
        return s;
    }

    pub fn colorWhitespace(self: Style, on: bool) Style {
        var s = self;
        s.color_ws = on;
        s._props.color_ws = true;
        return s;
    }

    pub fn fg_(self: Style, c: ansi.Color) Style {
        var s = self;
        s.fg = c;
        s._props.fg = true;
        return s;
    }

    pub fn bg_(self: Style, c: ansi.Color) Style {
        var s = self;
        s.bg = c;
        s._props.bg = true;
        return s;
    }

    pub fn ulColor(self: Style, c: ansi.Color) Style {
        var s = self;
        s.ul_color = c;
        s._props.ul_color = true;
        return s;
    }

    pub fn width_(self: Style, w: u16) Style {
        var s = self;
        s.width = w;
        s._props.width = true;
        return s;
    }

    pub fn height_(self: Style, h: u16) Style {
        var s = self;
        s.height = h;
        s._props.height = true;
        return s;
    }

    pub fn maxWidth(self: Style, w: u16) Style {
        var s = self;
        s.max_width = w;
        s._props.max_width = true;
        return s;
    }

    pub fn maxHeight(self: Style, h: u16) Style {
        var s = self;
        s.max_height = h;
        s._props.max_height = true;
        return s;
    }

    pub fn alignH(self: Style, p: Pos) Style {
        var s = self;
        s.align_h = p;
        s._props.align_h = true;
        return s;
    }

    pub fn alignV(self: Style, p: Pos) Style {
        var s = self;
        s.align_v = p;
        s._props.align_v = true;
        return s;
    }

    pub fn padding_(self: Style, top: u16, right: u16, bottom: u16, left: u16) Style {
        var s = self;
        s.pad_top = top;
        s._props.pad_top = true;
        s.pad_right = right;
        s._props.pad_right = true;
        s.pad_bottom = bottom;
        s._props.pad_bottom = true;
        s.pad_left = left;
        s._props.pad_left = true;
        return s;
    }

    pub fn padTop(self: Style, n: u16) Style {
        var s = self;
        s.pad_top = n;
        s._props.pad_top = true;
        return s;
    }

    pub fn padRight(self: Style, n: u16) Style {
        var s = self;
        s.pad_right = n;
        s._props.pad_right = true;
        return s;
    }

    pub fn padBottom(self: Style, n: u16) Style {
        var s = self;
        s.pad_bottom = n;
        s._props.pad_bottom = true;
        return s;
    }

    pub fn padLeft(self: Style, n: u16) Style {
        var s = self;
        s.pad_left = n;
        s._props.pad_left = true;
        return s;
    }

    pub fn margin_(self: Style, top: u16, right: u16, bottom: u16, left: u16) Style {
        var s = self;
        s.margin_top = top;
        s._props.margin_top = true;
        s.margin_right = right;
        s._props.margin_right = true;
        s.margin_bottom = bottom;
        s._props.margin_bottom = true;
        s.margin_left = left;
        s._props.margin_left = true;
        return s;
    }

    pub fn marginTop(self: Style, n: u16) Style {
        var s = self;
        s.margin_top = n;
        s._props.margin_top = true;
        return s;
    }

    pub fn marginRight(self: Style, n: u16) Style {
        var s = self;
        s.margin_right = n;
        s._props.margin_right = true;
        return s;
    }

    pub fn marginBottom(self: Style, n: u16) Style {
        var s = self;
        s.margin_bottom = n;
        s._props.margin_bottom = true;
        return s;
    }

    pub fn marginLeft(self: Style, n: u16) Style {
        var s = self;
        s.margin_left = n;
        s._props.margin_left = true;
        return s;
    }

    pub fn marginBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.margin_bg = c;
        s._props.margin_bg = true;
        return s;
    }

    // Sets the border style without enabling any side.
    pub fn border_(self: Style, b: Border) Style {
        var s = self;
        s.border_style = b;
        s._props.border_style = true;
        return s;
    }

    // Sets the border style and enables all four sides.
    pub fn borderAll(self: Style, b: Border) Style {
        var s = self;
        s.border_style = b;
        s._props.border_style = true;
        s.border_top = true;
        s._props.border_top = true;
        s.border_right = true;
        s._props.border_right = true;
        s.border_bottom = true;
        s._props.border_bottom = true;
        s.border_left = true;
        s._props.border_left = true;
        return s;
    }

    pub fn borderTop_(self: Style, on: bool) Style {
        var s = self;
        s.border_top = on;
        s._props.border_top = true;
        return s;
    }

    pub fn borderRight_(self: Style, on: bool) Style {
        var s = self;
        s.border_right = on;
        s._props.border_right = true;
        return s;
    }

    pub fn borderBottom_(self: Style, on: bool) Style {
        var s = self;
        s.border_bottom = on;
        s._props.border_bottom = true;
        return s;
    }

    pub fn borderLeft_(self: Style, on: bool) Style {
        var s = self;
        s.border_left = on;
        s._props.border_left = true;
        return s;
    }

    // Sets fg color for all four border sides simultaneously.
    pub fn borderFg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_top_fg = c;
        s._props.border_top_fg = true;
        s.border_right_fg = c;
        s._props.border_right_fg = true;
        s.border_bottom_fg = c;
        s._props.border_bottom_fg = true;
        s.border_left_fg = c;
        s._props.border_left_fg = true;
        return s;
    }

    pub fn borderTopFg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_top_fg = c;
        s._props.border_top_fg = true;
        return s;
    }

    pub fn borderRightFg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_right_fg = c;
        s._props.border_right_fg = true;
        return s;
    }

    pub fn borderBottomFg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_bottom_fg = c;
        s._props.border_bottom_fg = true;
        return s;
    }

    pub fn borderLeftFg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_left_fg = c;
        s._props.border_left_fg = true;
        return s;
    }

    // Sets bg color for all four border sides simultaneously.
    pub fn borderBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_top_bg = c;
        s._props.border_top_bg = true;
        s.border_right_bg = c;
        s._props.border_right_bg = true;
        s.border_bottom_bg = c;
        s._props.border_bottom_bg = true;
        s.border_left_bg = c;
        s._props.border_left_bg = true;
        return s;
    }

    pub fn borderTopBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_top_bg = c;
        s._props.border_top_bg = true;
        return s;
    }

    pub fn borderRightBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_right_bg = c;
        s._props.border_right_bg = true;
        return s;
    }

    pub fn borderBottomBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_bottom_bg = c;
        s._props.border_bottom_bg = true;
        return s;
    }

    pub fn borderLeftBg(self: Style, c: ansi.Color) Style {
        var s = self;
        s.border_left_bg = c;
        s._props.border_left_bg = true;
        return s;
    }

    pub fn inlineMode(self: Style, on: bool) Style {
        var s = self;
        s.inline_mode = on;
        s._props.inline_mode = true;
        return s;
    }

    pub fn tabWidth_(self: Style, w: i16) Style {
        var s = self;
        s.tab_width = w;
        s._props.tab_width = true;
        return s;
    }

    // --- inherit -------------------------------------------------------------
    //
    // Copy each explicitly-set property from parent onto self, only when self
    // does not already have that property set.
    // Margins and padding are NOT inherited (matches lipgloss behaviour).
    // If parent has bg set and self does not have margin_bg set, margin_bg
    // is set to parent's bg.
    pub fn inherit(self: Style, parent: Style) Style {
        var s = self;

        if (!s._props.bold and parent._props.bold) {
            s.bold = parent.bold;
            s._props.bold = true;
        }
        if (!s._props.italic and parent._props.italic) {
            s.italic = parent.italic;
            s._props.italic = true;
        }
        if (!s._props.faint and parent._props.faint) {
            s.faint = parent.faint;
            s._props.faint = true;
        }
        if (!s._props.reverse and parent._props.reverse) {
            s.reverse = parent.reverse;
            s._props.reverse = true;
        }
        if (!s._props.blink and parent._props.blink) {
            s.blink = parent.blink;
            s._props.blink = true;
        }
        if (!s._props.strike and parent._props.strike) {
            s.strike = parent.strike;
            s._props.strike = true;
        }
        if (!s._props.underline and parent._props.underline) {
            s.underline_style = parent.underline_style;
            s._props.underline = true;
        }
        if (!s._props.underline_spaces and parent._props.underline_spaces) {
            s.underline_spaces = parent.underline_spaces;
            s._props.underline_spaces = true;
        }
        if (!s._props.strike_spaces and parent._props.strike_spaces) {
            s.strike_spaces = parent.strike_spaces;
            s._props.strike_spaces = true;
        }
        if (!s._props.color_ws and parent._props.color_ws) {
            s.color_ws = parent.color_ws;
            s._props.color_ws = true;
        }
        if (!s._props.fg and parent._props.fg) {
            s.fg = parent.fg;
            s._props.fg = true;
        }
        if (!s._props.bg and parent._props.bg) {
            s.bg = parent.bg;
            s._props.bg = true;
        }
        if (!s._props.ul_color and parent._props.ul_color) {
            s.ul_color = parent.ul_color;
            s._props.ul_color = true;
        }
        if (!s._props.width and parent._props.width) {
            s.width = parent.width;
            s._props.width = true;
        }
        if (!s._props.height and parent._props.height) {
            s.height = parent.height;
            s._props.height = true;
        }
        if (!s._props.max_width and parent._props.max_width) {
            s.max_width = parent.max_width;
            s._props.max_width = true;
        }
        if (!s._props.max_height and parent._props.max_height) {
            s.max_height = parent.max_height;
            s._props.max_height = true;
        }
        if (!s._props.align_h and parent._props.align_h) {
            s.align_h = parent.align_h;
            s._props.align_h = true;
        }
        if (!s._props.align_v and parent._props.align_v) {
            s.align_v = parent.align_v;
            s._props.align_v = true;
        }
        if (!s._props.border_style and parent._props.border_style) {
            s.border_style = parent.border_style;
            s._props.border_style = true;
        }
        if (!s._props.border_top and parent._props.border_top) {
            s.border_top = parent.border_top;
            s._props.border_top = true;
        }
        if (!s._props.border_right and parent._props.border_right) {
            s.border_right = parent.border_right;
            s._props.border_right = true;
        }
        if (!s._props.border_bottom and parent._props.border_bottom) {
            s.border_bottom = parent.border_bottom;
            s._props.border_bottom = true;
        }
        if (!s._props.border_left and parent._props.border_left) {
            s.border_left = parent.border_left;
            s._props.border_left = true;
        }
        if (!s._props.border_top_fg and parent._props.border_top_fg) {
            s.border_top_fg = parent.border_top_fg;
            s._props.border_top_fg = true;
        }
        if (!s._props.border_right_fg and parent._props.border_right_fg) {
            s.border_right_fg = parent.border_right_fg;
            s._props.border_right_fg = true;
        }
        if (!s._props.border_bottom_fg and parent._props.border_bottom_fg) {
            s.border_bottom_fg = parent.border_bottom_fg;
            s._props.border_bottom_fg = true;
        }
        if (!s._props.border_left_fg and parent._props.border_left_fg) {
            s.border_left_fg = parent.border_left_fg;
            s._props.border_left_fg = true;
        }
        if (!s._props.border_top_bg and parent._props.border_top_bg) {
            s.border_top_bg = parent.border_top_bg;
            s._props.border_top_bg = true;
        }
        if (!s._props.border_right_bg and parent._props.border_right_bg) {
            s.border_right_bg = parent.border_right_bg;
            s._props.border_right_bg = true;
        }
        if (!s._props.border_bottom_bg and parent._props.border_bottom_bg) {
            s.border_bottom_bg = parent.border_bottom_bg;
            s._props.border_bottom_bg = true;
        }
        if (!s._props.border_left_bg and parent._props.border_left_bg) {
            s.border_left_bg = parent.border_left_bg;
            s._props.border_left_bg = true;
        }
        if (!s._props.inline_mode and parent._props.inline_mode) {
            s.inline_mode = parent.inline_mode;
            s._props.inline_mode = true;
        }
        if (!s._props.tab_width and parent._props.tab_width) {
            s.tab_width = parent.tab_width;
            s._props.tab_width = true;
        }

        // Propagate parent bg into child margin_bg when neither bg nor margin_bg
        // is set on child.  Consistent with lipgloss whitespace-colour inheritance.
        if (!self._props.margin_bg and parent._props.bg and !self._props.bg) {
            s.margin_bg = parent.bg;
            s._props.margin_bg = true;
        }

        return s;
    }

    // --- border size getters (pub: widget/ needs them) -----------------------

    // Total width consumed by borders (left + right, in cells).
    pub fn borderHSize(self: Style) u16 {
        var w: u16 = 0;
        if (self.border_left) w += self.border_style.leftSize();
        if (self.border_right) w += self.border_style.rightSize();
        return w;
    }

    // Total height consumed by borders (top + bottom, either 0 or 2).
    pub fn borderVSize(self: Style) u16 {
        var h: u16 = 0;
        if (self.border_top) h += self.border_style.topSize();
        if (self.border_bottom) h += self.border_style.bottomSize();
        return h;
    }

    // --- render --------------------------------------------------------------
    //
    // Caller owns the returned slice.  Free with allocator.free().
    // Returns error.OutOfMemory if any intermediate allocation fails.
    pub fn render(
        self: Style,
        allocator: std.mem.Allocator,
        text: []const u8,
    ) error{ OutOfMemory, WriteFailed }![]u8 {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tmp = arena.allocator();

        var s: []const u8 = text;

        // Stage 1: tab conversion
        s = try convertTabs(tmp, s, self.tab_width);

        // Stage 2: CR/LF normalisation
        s = try normalizeCRLF(tmp, s);

        // Stage 3: fast path -- no styling set at all
        if (@as(u64, @bitCast(self._props)) == 0) {
            return allocator.dupe(u8, s);
        }

        // Stage 4: inline mode strips newlines
        if (self.inline_mode) {
            s = try stripNewlines(tmp, s);
        }

        // Stage 5: effective width and height after border consumption
        const border_h: u16 = self.borderHSize();
        const border_v: u16 = self.borderVSize();
        const eff_width: u16 = if (self.width > 0) self.width -| border_h else 0;
        const eff_height: u16 = if (self.height > 0) self.height -| border_v else 0;

        // Stage 6: word wrap
        if (!self.inline_mode and eff_width > 0) {
            const wrap_at = eff_width -| self.pad_left -| self.pad_right;
            if (wrap_at > 0) {
                s = try ansi.str.wrap(s, wrap_at, tmp);
            }
        }

        // Stage 7: SGR text styling
        s = try applyAttrs(tmp, s, self);

        // Stage 8: padding
        if (!self.inline_mode) {
            s = try applyPadding(tmp, s, self);
        }

        // Stage 9: vertical alignment
        if (!self.inline_mode and eff_height > 0) {
            s = try applyAlignV(tmp, s, self.align_v, eff_height);
        }

        // Stage 10: horizontal alignment
        if (!self.inline_mode) {
            s = try applyAlignH(tmp, s, self, eff_width);
        }

        // Stage 11: border
        if (!self.inline_mode) {
            s = try applyBorder(tmp, s, self);
        }

        // Stage 12: margin
        if (!self.inline_mode) {
            s = try applyMargins(tmp, s, self);
        }

        // Stage 13: max_width truncation
        if (self.max_width > 0) {
            s = try applyMaxWidth(tmp, s, self.max_width);
        }

        // Stage 14: max_height truncation
        if (self.max_height > 0) {
            s = try applyMaxHeight(tmp, s, self.max_height);
        }

        return allocator.dupe(u8, s);
    }
};

// --- render pipeline stages (private) ----------------------------------------

// Stage 1: expand, strip, or leave tabs according to tab_width.
fn convertTabs(
    allocator: std.mem.Allocator,
    str: []const u8,
    tab_width: i16,
) error{OutOfMemory}![]const u8 {
    if (tab_width < 0) return str;
    if (tab_width == 0) {
        return std.mem.replaceOwned(u8, allocator, str, "\t", "");
    }
    // Positive: expand each tab to tab_width spaces.
    var spaces: [256]u8 = undefined;
    const n: usize = @intCast(tab_width);
    @memset(spaces[0..n], ' ');
    return std.mem.replaceOwned(u8, allocator, str, "\t", spaces[0..n]);
}

// Stage 2: normalise all line endings to '\n'.
fn normalizeCRLF(
    allocator: std.mem.Allocator,
    str: []const u8,
) error{OutOfMemory}![]const u8 {
    const step1 = try std.mem.replaceOwned(u8, allocator, str, "\r\n", "\n");
    return std.mem.replaceOwned(u8, allocator, step1, "\r", "\n");
}

// Stage 4: remove all newlines for inline mode.
fn stripNewlines(
    allocator: std.mem.Allocator,
    str: []const u8,
) error{OutOfMemory}![]const u8 {
    return std.mem.replaceOwned(u8, allocator, str, "\n", "");
}

// Build an ansi.Attrs from Style fields.
fn styleToAttrs(self: Style) ansi.Attrs {
    return ansi.Attrs{
        .bold = self.bold,
        .italic = self.italic,
        .faint = self.faint,
        .reverse = self.reverse,
        .blink = if (self.blink) .slow else .none,
        .strike = self.strike,
        .underline = self.underline_style,
        .fg = self.fg,
        .bg = self.bg,
        .ul_color = self.ul_color,
    };
}

// Stage 7: apply SGR sequences around each line.
// The slow path (underline or strike without space extension) splits the line
// into space and non-space runs so whitespace avoids the decoration.
fn applyAttrs(
    allocator: std.mem.Allocator,
    str: []const u8,
    self: Style,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    const attrs = styleToAttrs(self);
    const has_ul = self.underline_style != .none;
    const has_strike = self.strike;
    const slow_path = (has_ul and !self.underline_spaces) or
        (has_strike and !self.strike_spaces);

    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const zero_attrs = ansi.Attrs{};

    for (lines, 0..) |ln, li| {
        if (slow_path) {
            // Iterate codepoints; emit space runs and non-space runs with
            // different attribute sets.
            var space_attrs = attrs;
            space_attrs.underline = .none;
            space_attrs.strike = false;

            var view = std.unicode.Utf8View.init(ln) catch {
                // Malformed UTF-8 in content is treated as raw bytes.
                try emitLine(&out, allocator, ln, attrs, zero_attrs);
                if (li < lines.len - 1) try out.append(allocator, '\n');
                continue;
            };
            var it = view.iterator();
            var in_space = false;
            var run_start: usize = 0;
            var byte_pos: usize = 0;

            while (it.nextCodepointSlice()) |cp_bytes| {
                const is_space = (cp_bytes.len == 1 and
                    (cp_bytes[0] == 0x20 or cp_bytes[0] == 0xA0));
                if (byte_pos == 0) in_space = is_space;

                if (is_space != in_space) {
                    // Flush the previous run.
                    const run = ln[run_start..byte_pos];
                    const a = if (in_space) space_attrs else attrs;
                    try emitLine(&out, allocator, run, a, zero_attrs);
                    run_start = byte_pos;
                    in_space = is_space;
                }
                byte_pos += cp_bytes.len;
            }
            // Flush final run.
            if (run_start < ln.len) {
                const run = ln[run_start..];
                const a = if (in_space) space_attrs else attrs;
                try emitLine(&out, allocator, run, a, zero_attrs);
            }
        } else {
            // Common path: wrap the entire line with open/close SGR.
            try emitLine(&out, allocator, ln, attrs, zero_attrs);
        }

        if (li < lines.len - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// Emit open SGR + bytes + close SGR into out.
// If attrs is zero no sequences are emitted (avoids noise for plain text).
fn emitLine(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    bytes: []const u8,
    attrs: ansi.Attrs,
    zero: ansi.Attrs,
) error{ OutOfMemory, WriteFailed }!void {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try ansi.sgr.diff(&aw.writer, zero, attrs, .true_color);
    const open = aw.writer.buffered();
    try out.appendSlice(allocator, open);
    try out.appendSlice(allocator, bytes);
    if (open.len > 0) {
        // Only emit a reset when we actually opened something.
        var rw: std.Io.Writer.Allocating = .init(allocator);
        defer rw.deinit();
        try ansi.sgr.reset(&rw.writer);
        try out.appendSlice(allocator, rw.writer.buffered());
    }
}

// Stage 8: add padding inside the border.
fn applyPadding(
    allocator: std.mem.Allocator,
    str: []const u8,
    self: Style,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    const has_bg = self.color_ws and self.bg != .none;

    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    // Maximum visible width across all content lines (needed for blank rows).
    var max_w: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > max_w) max_w = lw;
    }
    const padded_w = max_w + self.pad_left + self.pad_right;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    // Top blank lines.
    for (0..self.pad_top) |_| {
        try appendBlankLine(&out, allocator, padded_w, self.bg, has_bg);
        try out.append(allocator, '\n');
    }

    // Content lines with left/right padding.
    for (lines, 0..) |ln, i| {
        if (self.pad_left > 0) {
            try appendPadSpaces(&out, allocator, self.pad_left, self.bg, has_bg);
        }
        try out.appendSlice(allocator, ln);
        if (self.pad_right > 0) {
            try appendPadSpaces(&out, allocator, self.pad_right, self.bg, has_bg);
        }
        if (i < lines.len - 1) try out.append(allocator, '\n');
    }

    // Bottom blank lines.
    for (0..self.pad_bottom) |_| {
        try out.append(allocator, '\n');
        try appendBlankLine(&out, allocator, padded_w, self.bg, has_bg);
    }

    return out.toOwnedSlice(allocator);
}

// Append n space bytes, optionally wrapped with bg color SGR.
fn appendPadSpaces(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    n: u16,
    bg: ansi.Color,
    color: bool,
) error{ OutOfMemory, WriteFailed }!void {
    if (color) {
        const open_attrs = ansi.Attrs{ .bg = bg };
        const zero_attrs = ansi.Attrs{};
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        try ansi.sgr.diff(&aw.writer, zero_attrs, open_attrs, .true_color);
        try out.appendSlice(allocator, aw.writer.buffered());
    }
    try out.appendNTimes(allocator, ' ', n);
    if (color) {
        var rw: std.Io.Writer.Allocating = .init(allocator);
        defer rw.deinit();
        try ansi.sgr.reset(&rw.writer);
        try out.appendSlice(allocator, rw.writer.buffered());
    }
}

// Append a blank line of cell width w.
fn appendBlankLine(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    w: u16,
    bg: ansi.Color,
    color: bool,
) error{ OutOfMemory, WriteFailed }!void {
    try appendPadSpaces(out, allocator, w, bg, color);
}

// Stage 9: vertical alignment within eff_height.
fn applyAlignV(
    allocator: std.mem.Allocator,
    str: []const u8,
    align_v: Pos,
    eff_height: u16,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    const line_count = lines.len;
    if (line_count >= eff_height) return str;

    const gap: usize = eff_height - line_count;
    const p = std.math.clamp(align_v, 0.0, 1.0);
    const top_gap = gap - @as(usize, @intFromFloat(
        @round(@as(f32, @floatFromInt(gap)) * p),
    ));
    const bot_gap = gap - top_gap;

    // Width for blank lines: max visible width in current str.
    var blank_w: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > blank_w) blank_w = lw;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (0..top_gap) |_| {
        try out.appendNTimes(allocator, ' ', blank_w);
        try out.append(allocator, '\n');
    }
    try out.appendSlice(allocator, str);
    for (0..bot_gap) |_| {
        try out.append(allocator, '\n');
        try out.appendNTimes(allocator, ' ', blank_w);
    }

    return out.toOwnedSlice(allocator);
}

// Stage 10: horizontal alignment.
fn applyAlignH(
    allocator: std.mem.Allocator,
    str: []const u8,
    self: Style,
    eff_width: u16,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    var max_lw: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > max_lw) max_lw = lw;
    }

    const effective_w: u16 = if (eff_width > 0) eff_width else max_lw;
    const has_bg = self.color_ws and self.bg != .none;
    const p = std.math.clamp(self.align_h, 0.0, 1.0);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (lines, 0..) |ln, i| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        const gap_i: i32 = @as(i32, effective_w) - @as(i32, lw);
        if (gap_i <= 0) {
            try out.appendSlice(allocator, ln);
        } else {
            const gap: u16 = @intCast(gap_i);
            if (p == LEFT) {
                try out.appendSlice(allocator, ln);
                try appendPadSpaces(&out, allocator, gap, self.bg, has_bg);
            } else if (p == RIGHT) {
                try appendPadSpaces(&out, allocator, gap, self.bg, has_bg);
                try out.appendSlice(allocator, ln);
            } else {
                const right: u16 = @intCast(@as(
                    usize,
                    @intFromFloat(@round(@as(f32, @floatFromInt(gap)) * p)),
                ));
                const left: u16 = gap - right;
                try appendPadSpaces(&out, allocator, left, self.bg, has_bg);
                try out.appendSlice(allocator, ln);
                try appendPadSpaces(&out, allocator, right, self.bg, has_bg);
            }
        }
        if (i < lines.len - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// Splits str by '\n' and returns (lines, max visible width).
// Allocates with the provided allocator.
fn getLinesMeta(
    allocator: std.mem.Allocator,
    str: []const u8,
) error{OutOfMemory}!struct { lines: [][]const u8, max_width: u16 } {
    const lines = try ansi.str.splitLines(str, allocator);
    var max_w: u16 = 0;
    for (lines) |ln| {
        const lw: u16 = @intCast(ansi.strWidth(ln));
        if (lw > max_w) max_w = lw;
    }
    return .{ .lines = lines, .max_width = max_w };
}

// Build the top or bottom border row by repeating the fill glyph.
// total_width is the full width of the content area (border included for H).
fn renderHorizEdge(
    allocator: std.mem.Allocator,
    left: []const u8,
    fill: []const u8,
    right: []const u8,
    total_width: u16,
) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, left);

    const left_w: u16 = @intCast(ansi.rawWidth(left));
    const right_w: u16 = @intCast(ansi.rawWidth(right));
    const avail = total_width -| left_w -| right_w;

    const fill_str: []const u8 = if (fill.len == 0) " " else fill;

    var view = std.unicode.Utf8View.init(fill_str) catch {
        // Fallback: fill with spaces if fill is malformed UTF-8.
        try out.appendNTimes(allocator, ' ', avail);
        try out.appendSlice(allocator, right);
        return out.toOwnedSlice(allocator);
    };

    var filled: u16 = 0;
    var it = view.iterator();
    while (filled < avail) {
        const cp_bytes = it.nextCodepointSlice() orelse blk: {
            // Ring: reset the iterator and grab the first codepoint again.
            it = view.iterator();
            break :blk it.nextCodepointSlice() orelse break;
        };
        const cp = std.unicode.utf8Decode(cp_bytes) catch break;
        const cp_w: u16 = @intCast(ansi.cpWidth(cp));
        if (filled + cp_w > avail) break;
        try out.appendSlice(allocator, cp_bytes);
        filled += cp_w;
    }

    try out.appendSlice(allocator, right);
    return out.toOwnedSlice(allocator);
}

// Wrap a border glyph with fg/bg SGR if either is set.
// Both .none: returns a dupe of part (no sequences).
fn wrapBorderPart(
    allocator: std.mem.Allocator,
    part: []const u8,
    fg: ansi.Color,
    bg_color: ansi.Color,
) error{ OutOfMemory, WriteFailed }![]u8 {
    if (fg == .none and bg_color == .none) {
        return allocator.dupe(u8, part);
    }
    const col_attrs = ansi.Attrs{ .fg = fg, .bg = bg_color };
    const zero = ansi.Attrs{};

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try ansi.sgr.diff(&aw.writer, zero, col_attrs, .true_color);

    var rw: std.Io.Writer.Allocating = .init(allocator);
    defer rw.deinit();
    try ansi.sgr.reset(&rw.writer);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, aw.writer.buffered());
    try buf.appendSlice(allocator, part);
    try buf.appendSlice(allocator, rw.writer.buffered());
    return buf.toOwnedSlice(allocator);
}

// Stage 11: apply border around the content block.
fn applyBorder(
    allocator: std.mem.Allocator,
    str: []const u8,
    self: Style,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    // Decide which sides are active.
    // If border_style is set but none of the per-side flags are explicitly set,
    // enable all four sides.  Otherwise use the explicit flags.
    const explicit_sides = self._props.border_top or self._props.border_right or
        self._props.border_bottom or self._props.border_left;

    const top_on = if (explicit_sides) self.border_top else self._props.border_style;
    const right_on = if (explicit_sides) self.border_right else self._props.border_style;
    const bottom_on = if (explicit_sides) self.border_bottom else self._props.border_style;
    const left_on = if (explicit_sides) self.border_left else self._props.border_style;

    if (!top_on and !right_on and !bottom_on and !left_on) return str;

    const meta = try getLinesMeta(allocator, str);
    defer allocator.free(meta.lines);

    const content_w = meta.max_width;
    var total_w: u16 = content_w;
    if (left_on) total_w += self.border_style.leftSize();
    if (right_on) total_w += self.border_style.rightSize();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    // Top border row.
    if (top_on) {
        const left_str = if (left_on) self.border_style.top_left else "";
        const right_str = if (right_on) self.border_style.top_right else "";
        const edge = try renderHorizEdge(
            allocator,
            left_str,
            self.border_style.top,
            right_str,
            total_w,
        );
        defer allocator.free(edge);
        const wrapped = try wrapBorderPart(
            allocator,
            edge,
            self.border_top_fg,
            self.border_top_bg,
        );
        defer allocator.free(wrapped);
        try out.appendSlice(allocator, wrapped);
        try out.append(allocator, '\n');
    }

    // Content rows.
    for (meta.lines, 0..) |ln, i| {
        if (left_on) {
            const lp = try wrapBorderPart(
                allocator,
                self.border_style.left,
                self.border_left_fg,
                self.border_left_bg,
            );
            defer allocator.free(lp);
            try out.appendSlice(allocator, lp);
        }
        try out.appendSlice(allocator, ln);
        if (right_on) {
            const rp = try wrapBorderPart(
                allocator,
                self.border_style.right,
                self.border_right_fg,
                self.border_right_bg,
            );
            defer allocator.free(rp);
            try out.appendSlice(allocator, rp);
        }
        if (i < meta.lines.len - 1) try out.append(allocator, '\n');
    }

    // Bottom border row.
    if (bottom_on) {
        const left_str = if (left_on) self.border_style.bottom_left else "";
        const right_str = if (right_on) self.border_style.bottom_right else "";
        const edge = try renderHorizEdge(
            allocator,
            left_str,
            self.border_style.bottom,
            right_str,
            total_w,
        );
        defer allocator.free(edge);
        const wrapped = try wrapBorderPart(
            allocator,
            edge,
            self.border_bottom_fg,
            self.border_bottom_bg,
        );
        defer allocator.free(wrapped);
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, wrapped);
    }

    return out.toOwnedSlice(allocator);
}

// Stage 12: add margin outside the border.
fn applyMargins(
    allocator: std.mem.Allocator,
    str: []const u8,
    self: Style,
) error{ OutOfMemory, WriteFailed }![]const u8 {
    const has_mbg = self.margin_bg != .none;

    const meta = try getLinesMeta(allocator, str);
    defer allocator.free(meta.lines);
    const content_w = meta.max_width + self.margin_left + self.margin_right;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    // Top margin.
    for (0..self.margin_top) |_| {
        try appendMbgSpaces(&out, allocator, content_w, self.margin_bg, has_mbg);
        try out.append(allocator, '\n');
    }

    // Content with left/right margin.
    for (meta.lines, 0..) |ln, i| {
        if (self.margin_left > 0) {
            try appendMbgSpaces(&out, allocator, self.margin_left, self.margin_bg, has_mbg);
        }
        try out.appendSlice(allocator, ln);
        if (self.margin_right > 0) {
            try appendMbgSpaces(&out, allocator, self.margin_right, self.margin_bg, has_mbg);
        }
        if (i < meta.lines.len - 1) try out.append(allocator, '\n');
    }

    // Bottom margin.
    for (0..self.margin_bottom) |_| {
        try out.append(allocator, '\n');
        try appendMbgSpaces(&out, allocator, content_w, self.margin_bg, has_mbg);
    }

    return out.toOwnedSlice(allocator);
}

// Append n spaces optionally coloured with margin_bg.
fn appendMbgSpaces(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    n: u16,
    mbg: ansi.Color,
    color: bool,
) error{ OutOfMemory, WriteFailed }!void {
    if (color) {
        const open_attrs = ansi.Attrs{ .bg = mbg };
        const zero_attrs = ansi.Attrs{};
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        try ansi.sgr.diff(&aw.writer, zero_attrs, open_attrs, .true_color);
        try out.appendSlice(allocator, aw.writer.buffered());
    }
    try out.appendNTimes(allocator, ' ', n);
    if (color) {
        var rw: std.Io.Writer.Allocating = .init(allocator);
        defer rw.deinit();
        try ansi.sgr.reset(&rw.writer);
        try out.appendSlice(allocator, rw.writer.buffered());
    }
}

// Stage 13: truncate each line to at most max_width visible cells.
fn applyMaxWidth(
    allocator: std.mem.Allocator,
    str: []const u8,
    max_w: u16,
) error{OutOfMemory}![]const u8 {
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (lines, 0..) |ln, i| {
        const trunc = try ansi.str.truncate(ln, max_w, allocator);
        defer allocator.free(trunc);
        try out.appendSlice(allocator, trunc);
        if (i < lines.len - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// Stage 14: keep only the first max_h lines.
fn applyMaxHeight(
    allocator: std.mem.Allocator,
    str: []const u8,
    max_h: u16,
) error{OutOfMemory}![]const u8 {
    const lines = try ansi.str.splitLines(str, allocator);
    defer allocator.free(lines);

    const keep = @min(lines.len, @as(usize, max_h));

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (lines[0..keep], 0..) |ln, i| {
        try out.appendSlice(allocator, ln);
        if (i < keep - 1) try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

// --- tests -------------------------------------------------------------------

test "Style init returns zero-props style" {
    const s = Style.init();
    try std.testing.expectEqual(@as(u64, 0), @as(u64, @bitCast(s._props)));
}

test "Style bold setter marks bold prop and sets bold field" {
    const s = Style.init().bold_(true);
    try std.testing.expectEqual(true, s._props.bold);
    try std.testing.expectEqual(true, s.bold);
}

test "Style render with no props returns input unchanged" {
    const allocator = std.testing.allocator;
    const s = Style.init();
    const r = try s.render(allocator, "hello");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("hello", r);
}

test "Style render inline mode strips newlines" {
    const allocator = std.testing.allocator;
    const s = Style.init().inlineMode(true);
    const r = try s.render(allocator, "a\nb\nc");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("abc", r);
}

test "Style render width pads single-line text to width on the right" {
    const allocator = std.testing.allocator;
    const s = Style.init().width_(10);
    const r = try s.render(allocator, "hi");
    defer allocator.free(r);
    try std.testing.expectEqual(@as(usize, 10), ansi.strWidth(r));
}

test "Style render width with alignH RIGHT pads on the left" {
    const allocator = std.testing.allocator;
    const s = Style.init().width_(10).alignH(RIGHT);
    const r = try s.render(allocator, "hi");
    defer allocator.free(r);
    // Left portion should be spaces before "hi".
    try std.testing.expectEqual(true, std.mem.startsWith(u8, r, " "));
}

test "Style render padding adds correct space on each side" {
    const allocator = std.testing.allocator;
    const s = Style.init().padLeft(2).padRight(2).padTop(1).padBottom(1);
    const r = try s.render(allocator, "x");
    defer allocator.free(r);
    const lines = try ansi.str.splitLines(r, allocator);
    defer allocator.free(lines);
    // top blank, content with padding, bottom blank
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(@as(usize, 5), ansi.strWidth(lines[1]));
}

test "Style render border wraps content in ROUNDED border" {
    const allocator = std.testing.allocator;
    const s = Style.init().borderAll(border.ROUNDED);
    const r = try s.render(allocator, "hi");
    defer allocator.free(r);
    const lines = try ansi.str.splitLines(r, allocator);
    defer allocator.free(lines);
    // 3 lines: top border, content, bottom border
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    // Top-left corner of ROUNDED is U+256D (\xe2\x95\xad).
    try std.testing.expectEqual(
        true,
        std.mem.startsWith(u8, lines[0], "\xe2\x95\xad"),
    );
}

test "Style render border per-side top only" {
    const allocator = std.testing.allocator;
    const s = Style.init().border_(border.NORMAL).borderTop_(true);
    const r = try s.render(allocator, "hi");
    defer allocator.free(r);
    const lines = try ansi.str.splitLines(r, allocator);
    defer allocator.free(lines);
    // top border + content, no bottom border
    try std.testing.expectEqual(@as(usize, 2), lines.len);
}

test "Style render max_width truncates each line" {
    const allocator = std.testing.allocator;
    const s = Style.init().maxWidth(3);
    const r = try s.render(allocator, "hello\nworld");
    defer allocator.free(r);
    const lines = try ansi.str.splitLines(r, allocator);
    defer allocator.free(lines);
    try std.testing.expectEqual(true, ansi.strWidth(lines[0]) <= 3);
    try std.testing.expectEqual(true, ansi.strWidth(lines[1]) <= 3);
}

test "Style render max_height truncates excess lines" {
    const allocator = std.testing.allocator;
    const s = Style.init().maxHeight(2);
    const r = try s.render(allocator, "a\nb\nc\nd");
    defer allocator.free(r);
    const lines = try ansi.str.splitLines(r, allocator);
    defer allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 2), lines.len);
}

test "Style render tab_width expands tabs to spaces" {
    const allocator = std.testing.allocator;
    const s = Style.init().tabWidth_(4);
    const r = try s.render(allocator, "\thello");
    defer allocator.free(r);
    try std.testing.expectEqual(true, std.mem.startsWith(u8, r, "    "));
}

test "Style render tab_width -1 leaves tabs unchanged" {
    const allocator = std.testing.allocator;
    const s = Style.init().tabWidth_(-1);
    const r = try s.render(allocator, "\thello");
    defer allocator.free(r);
    try std.testing.expectEqual(true, std.mem.startsWith(u8, r, "\t"));
}

test "Style inherit copies unset fg from parent" {
    const parent = Style.init().fg_(.{ .ansi16 = .red });
    const child = Style.init().inherit(parent);
    try std.testing.expectEqual(ansi.Color{ .ansi16 = .red }, child.fg);
    try std.testing.expectEqual(true, child._props.fg);
}

test "Style inherit does not overwrite child fg with parent fg" {
    const parent = Style.init().fg_(.{ .ansi16 = .red });
    const child = Style.init().fg_(.{ .ansi16 = .blue }).inherit(parent);
    try std.testing.expectEqual(ansi.Color{ .ansi16 = .blue }, child.fg);
}

test "Style inherit does not copy margin from parent" {
    const parent = Style.init().marginLeft(10);
    const child = Style.init().inherit(parent);
    try std.testing.expectEqual(@as(u16, 0), child.margin_left);
    try std.testing.expectEqual(false, child._props.margin_left);
}

test "Style inherit does not copy padding from parent" {
    const parent = Style.init().padLeft(5);
    const child = Style.init().inherit(parent);
    try std.testing.expectEqual(@as(u16, 0), child.pad_left);
}

test "Style inherit copies parent bg into child margin_bg when neither is set" {
    const parent = Style.init().bg_(.{ .ansi16 = .blue });
    const child = Style.init().inherit(parent);
    try std.testing.expectEqual(ansi.Color{ .ansi16 = .blue }, child.margin_bg);
}
