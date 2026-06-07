// SPDX-License-Identifier: MIT

// csi.zig - CSI sequence generation: SGR, cursor, erase, scroll, modes
//
// Deps: color.zig
// All write functions use duck-typed Writer (anytype with writeAll).
// Zero heap allocation. Stack-only.

const std = @import("std");
const color = @import("color.zig");

pub const Color = color.Color;
pub const ColorProfile = color.ColorProfile;
pub const Ansi16 = color.Ansi16;

// SGR attribute set for a single terminal cell or style span.
pub const Attrs = struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: Underline = .none,
    blink: Blink = .none,
    reverse: bool = false,
    conceal: bool = false,
    strike: bool = false,
    fg: Color = .none,
    bg: Color = .none,
    ul_color: Color = .none,

    pub const Underline = enum(u8) {
        none = 0,
        single = 1,
        double = 2,
        curly = 3,
        dotted = 4,
        dashed = 5,
    };

    pub const Blink = enum { none, slow, rapid };

    pub fn any(self: Attrs) bool {
        return self.bold or self.faint or self.italic or
            self.reverse or self.conceal or self.strike or
            self.underline != .none or self.blink != .none or
            self.fg != .none or self.bg != .none or self.ul_color != .none;
    }

    pub fn eql(a: Attrs, b: Attrs) bool {
        return a.bold == b.bold and
            a.faint == b.faint and
            a.italic == b.italic and
            a.underline == b.underline and
            a.blink == b.blink and
            a.reverse == b.reverse and
            a.conceal == b.conceal and
            a.strike == b.strike and
            std.meta.eql(a.fg, b.fg) and
            std.meta.eql(a.bg, b.bg) and
            std.meta.eql(a.ul_color, b.ul_color);
    }

    // Merge b onto a: any non-default field in b overrides a.
    pub fn merge(a: Attrs, b: Attrs) Attrs {
        return .{
            .bold = if (b.bold) b.bold else a.bold,
            .faint = if (b.faint) b.faint else a.faint,
            .italic = if (b.italic) b.italic else a.italic,
            .underline = if (b.underline != .none) b.underline else a.underline,
            .blink = if (b.blink != .none) b.blink else a.blink,
            .reverse = if (b.reverse) b.reverse else a.reverse,
            .conceal = if (b.conceal) b.conceal else a.conceal,
            .strike = if (b.strike) b.strike else a.strike,
            .fg = if (b.fg != .none) b.fg else a.fg,
            .bg = if (b.bg != .none) b.bg else a.bg,
            .ul_color = if (b.ul_color != .none) b.ul_color else a.ul_color,
        };
    }
};

pub const CursorShape = enum {
    default,
    blinking_block,
    block,
    blinking_under,
    underline,
    blinking_bar,
    bar,
};

pub const EraseDisplay = enum {
    below,
    above,
    all,
    scrollback,
};

pub const EraseLine = enum {
    to_end,
    to_start,
    all,
};

pub const Mode = enum(u16) {
    cursor_visible = 25,
    alt_screen = 1049,
    alt_screen_basic = 47,
    mouse_x10 = 9,
    mouse_normal = 1000,
    mouse_button = 1002,
    mouse_any = 1003,
    mouse_sgr = 1006,
    mouse_urxvt = 1015,
    mouse_pixels = 1016,
    bracketed_paste = 2004,
    focus_events = 1004,
    line_wrap = 7,
    synchronized_output = 2026,
    unicode_core = 2027,
    in_band_resize = 2048,
    color_scheme_updates = 2031,
};

pub const MouseTrackingMode = enum {
    none,
    x10,
    normal,
    button,
    any,
};

// Inline decimal encoder — avoids std.fmt on hot path.
fn writeU16(w: anytype, n: u16) !void {
    var buf: [5]u8 = undefined;
    var i: u8 = 5;
    var v = n;
    if (v == 0) {
        try w.writeAll("0");
        return;
    }
    while (v > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    try w.writeAll(buf[i..]);
}

fn writeU8(w: anytype, n: u8) !void {
    try writeU16(w, n);
}

// ----------------------------------------------------------------------------
// SGR
// ----------------------------------------------------------------------------

pub fn sgrReset(w: anytype) !void {
    try w.writeAll("\x1b[0m");
}

pub fn sgrBold(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[1m" else "\x1b[22m");
}

pub fn sgrFaint(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[2m" else "\x1b[22m");
}

pub fn sgrItalic(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[3m" else "\x1b[23m");
}

pub fn sgrUnderline(w: anytype, style: Attrs.Underline) !void {
    switch (style) {
        .none => try w.writeAll("\x1b[24m"),
        .single => try w.writeAll("\x1b[4m"),
        .double => try w.writeAll("\x1b[21m"),
        .curly => try w.writeAll("\x1b[4:3m"),
        .dotted => try w.writeAll("\x1b[4:4m"),
        .dashed => try w.writeAll("\x1b[4:5m"),
    }
}

pub fn sgrBlink(w: anytype, b: Attrs.Blink) !void {
    switch (b) {
        .none => try w.writeAll("\x1b[25m"),
        .slow => try w.writeAll("\x1b[5m"),
        .rapid => try w.writeAll("\x1b[6m"),
    }
}

pub fn sgrReverse(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[7m" else "\x1b[27m");
}

pub fn sgrConceal(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[8m" else "\x1b[28m");
}

pub fn sgrStrike(w: anytype, on: bool) !void {
    try w.writeAll(if (on) "\x1b[9m" else "\x1b[29m");
}

pub fn sgrFg(w: anytype, c: Color) !void {
    switch (c) {
        .none => try w.writeAll("\x1b[39m"),
        .ansi16 => |v| {
            const n = @intFromEnum(v);
            try w.writeAll("\x1b[");
            if (n < 8) {
                try writeU8(w, @as(u8, 30) + @as(u8, n));
            } else {
                try writeU8(w, @as(u8, 90) + (@as(u8, n) - 8));
            }
            try w.writeAll("m");
        },
        .ansi256 => |n| {
            try w.writeAll("\x1b[38;5;");
            try writeU8(w, n);
            try w.writeAll("m");
        },
        .rgb => |v| {
            try w.writeAll("\x1b[38;2;");
            try writeU8(w, v.r);
            try w.writeAll(";");
            try writeU8(w, v.g);
            try w.writeAll(";");
            try writeU8(w, v.b);
            try w.writeAll("m");
        },
    }
}

pub fn sgrBg(w: anytype, c: Color) !void {
    switch (c) {
        .none => try w.writeAll("\x1b[49m"),
        .ansi16 => |v| {
            const n = @intFromEnum(v);
            try w.writeAll("\x1b[");
            if (n < 8) {
                try writeU8(w, @as(u8, 40) + @as(u8, n));
            } else {
                try writeU8(w, @as(u8, 100) + (@as(u8, n) - 8));
            }
            try w.writeAll("m");
        },
        .ansi256 => |n| {
            try w.writeAll("\x1b[48;5;");
            try writeU8(w, n);
            try w.writeAll("m");
        },
        .rgb => |v| {
            try w.writeAll("\x1b[48;2;");
            try writeU8(w, v.r);
            try w.writeAll(";");
            try writeU8(w, v.g);
            try w.writeAll(";");
            try writeU8(w, v.b);
            try w.writeAll("m");
        },
    }
}

pub fn sgrUlColor(w: anytype, c: Color) !void {
    switch (c) {
        .none => try w.writeAll("\x1b[59m"),
        .rgb => |v| {
            try w.writeAll("\x1b[58;2;");
            try writeU8(w, v.r);
            try w.writeAll(";");
            try writeU8(w, v.g);
            try w.writeAll(";");
            try writeU8(w, v.b);
            try w.writeAll("m");
        },
        .ansi256 => |n| {
            try w.writeAll("\x1b[58;5;");
            try writeU8(w, n);
            try w.writeAll("m");
        },
        .ansi16 => {
            // ul_color with ansi16 is not a VTE extension; emit reset
            try w.writeAll("\x1b[59m");
        },
    }
}

// Emit only the sequences needed to transition from prev to next.
// Pass Attrs{} as prev for first render (emits all non-default fields).
pub fn sgrDiff(w: anytype, prev: Attrs, next: Attrs, profile: ColorProfile) !void {
    if (Attrs.eql(prev, next)) return;

    // Full reset is cheaper when many attrs change or we need to turn off
    // something that has no off sequence without conflict.
    // Heuristic: reset if next has no attrs set at all.
    if (!next.any()) {
        try sgrReset(w);
        return;
    }

    // bold/faint share ESC[22m for off; reset if switching between them
    if ((prev.bold != next.bold) or (prev.faint != next.faint)) {
        if (next.bold) {
            try sgrBold(w, true);
        } else if (next.faint) {
            try sgrFaint(w, true);
        } else {
            try w.writeAll("\x1b[22m");
        }
    }

    if (prev.italic != next.italic) try sgrItalic(w, next.italic);
    if (prev.underline != next.underline) try sgrUnderline(w, next.underline);
    if (prev.blink != next.blink) try sgrBlink(w, next.blink);
    if (prev.reverse != next.reverse) try sgrReverse(w, next.reverse);
    if (prev.conceal != next.conceal) try sgrConceal(w, next.conceal);
    if (prev.strike != next.strike) try sgrStrike(w, next.strike);

    if (!Color.eql(prev.fg, next.fg, profile)) {
        try sgrFg(w, next.fg.downgrade(profile));
    }
    if (!Color.eql(prev.bg, next.bg, profile)) {
        try sgrBg(w, next.bg.downgrade(profile));
    }
    if (!Color.eql(prev.ul_color, next.ul_color, profile)) {
        try sgrUlColor(w, next.ul_color.downgrade(profile));
    }
}

// ----------------------------------------------------------------------------
// Cursor movement
// ----------------------------------------------------------------------------

pub fn cursorUp(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("A");
}

pub fn cursorDown(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("B");
}

pub fn cursorForward(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("C");
}

pub fn cursorBack(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("D");
}

pub fn cursorNextLine(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("E");
}

pub fn cursorPrevLine(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, if (n == 0) 1 else n);
    try w.writeAll("F");
}

pub fn cursorCol(w: anytype, col: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, col);
    try w.writeAll("G");
}

pub fn cursorPos(w: anytype, row: u16, col: u16) !void {
    // ESC[H is the canonical home (1;1)
    if (row == 1 and col == 1) {
        try w.writeAll("\x1b[H");
        return;
    }
    try w.writeAll("\x1b[");
    try writeU16(w, row);
    try w.writeAll(";");
    try writeU16(w, col);
    try w.writeAll("H");
}

pub fn cursorHome(w: anytype) !void {
    try w.writeAll("\x1b[H");
}

pub fn cursorSave(w: anytype) !void {
    try w.writeAll("\x1b[s");
}

pub fn cursorRestore(w: anytype) !void {
    try w.writeAll("\x1b[u");
}

pub fn cursorSaveDec(w: anytype) !void {
    try w.writeAll("\x1b7");
}

pub fn cursorRestoreDec(w: anytype) !void {
    try w.writeAll("\x1b8");
}

pub fn cursorRequest(w: anytype) !void {
    try w.writeAll("\x1b[6n");
}

pub fn cursorShape(w: anytype, shape: CursorShape) !void {
    const n: u8 = switch (shape) {
        .default => 0,
        .blinking_block => 1,
        .block => 2,
        .blinking_under => 3,
        .underline => 4,
        .blinking_bar => 5,
        .bar => 6,
    };
    try w.writeAll("\x1b[");
    try writeU8(w, n);
    try w.writeAll(" q");
}

// ----------------------------------------------------------------------------
// Erase
// ----------------------------------------------------------------------------

pub fn eraseDisplay(w: anytype, mode: EraseDisplay) !void {
    const n: u8 = switch (mode) {
        .below => 0,
        .above => 1,
        .all => 2,
        .scrollback => 3,
    };
    try w.writeAll("\x1b[");
    try writeU8(w, n);
    try w.writeAll("J");
}

pub fn eraseLine(w: anytype, mode: EraseLine) !void {
    const n: u8 = switch (mode) {
        .to_end => 0,
        .to_start => 1,
        .all => 2,
    };
    try w.writeAll("\x1b[");
    try writeU8(w, n);
    try w.writeAll("K");
}

// ----------------------------------------------------------------------------
// Scroll / insert / delete
// ----------------------------------------------------------------------------

pub fn scrollUp(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("S");
}

pub fn scrollDown(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("T");
}

pub fn insertLines(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("L");
}

pub fn deleteLines(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("M");
}

pub fn insertChars(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("@");
}

pub fn deleteChars(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("P");
}

pub fn eraseChars(w: anytype, n: u16) !void {
    try w.writeAll("\x1b[");
    try writeU16(w, n);
    try w.writeAll("X");
}

// ----------------------------------------------------------------------------
// DEC private modes
// ----------------------------------------------------------------------------

pub fn modeSet(w: anytype, mode: Mode) !void {
    try w.writeAll("\x1b[?");
    try writeU16(w, @intFromEnum(mode));
    try w.writeAll("h");
}

pub fn modeReset(w: anytype, mode: Mode) !void {
    try w.writeAll("\x1b[?");
    try writeU16(w, @intFromEnum(mode));
    try w.writeAll("l");
}

pub fn modeQuery(w: anytype, mode: Mode) !void {
    try w.writeAll("\x1b[?");
    try writeU16(w, @intFromEnum(mode));
    try w.writeAll("$p");
}

pub fn showCursor(w: anytype) !void {
    try modeSet(w, .cursor_visible);
}
pub fn hideCursor(w: anytype) !void {
    try modeReset(w, .cursor_visible);
}
pub fn altScreenEnter(w: anytype) !void {
    try modeSet(w, .alt_screen);
}
pub fn altScreenLeave(w: anytype) !void {
    try modeReset(w, .alt_screen);
}

pub fn mouseTrackingEnter(w: anytype, mode: MouseTrackingMode) !void {
    switch (mode) {
        .none => {},
        .x10 => try modeSet(w, .mouse_x10),
        .normal => try modeSet(w, .mouse_normal),
        .button => try modeSet(w, .mouse_button),
        .any => {
            try modeSet(w, .mouse_any);
            try modeSet(w, .mouse_sgr);
        },
    }
}

pub fn mouseTrackingLeave(w: anytype) !void {
    try modeReset(w, .mouse_any);
    try modeReset(w, .mouse_button);
    try modeReset(w, .mouse_normal);
    try modeReset(w, .mouse_x10);
    try modeReset(w, .mouse_sgr);
}

pub fn bracketedPasteEnter(w: anytype) !void {
    try modeSet(w, .bracketed_paste);
}
pub fn bracketedPasteLeave(w: anytype) !void {
    try modeReset(w, .bracketed_paste);
}
pub fn focusReportingEnter(w: anytype) !void {
    try modeSet(w, .focus_events);
}
pub fn focusReportingLeave(w: anytype) !void {
    try modeReset(w, .focus_events);
}
pub fn syncOutputBegin(w: anytype) !void {
    try modeSet(w, .synchronized_output);
}
pub fn syncOutputEnd(w: anytype) !void {
    try modeReset(w, .synchronized_output);
}

// ----------------------------------------------------------------------------
// Terminal capability queries
// ----------------------------------------------------------------------------

pub fn queryTermName(w: anytype) !void {
    try w.writeAll("\x1b[>q");
}
pub fn queryPrimaryDa(w: anytype) !void {
    try w.writeAll("\x1b[0c");
}
pub fn querySecondaryDa(w: anytype) !void {
    try w.writeAll("\x1b[>0c");
}

pub fn queryTermcap(w: anytype, cap: []const u8) !void {
    try w.writeAll("\x1bP+q");
    // hex-encode cap name
    for (cap) |b| {
        var hi: u8 = b >> 4;
        var lo: u8 = b & 0x0F;
        hi = if (hi < 10) '0' + hi else 'A' + (hi - 10);
        lo = if (lo < 10) '0' + lo else 'A' + (lo - 10);
        try w.writeAll(&.{ hi, lo });
    }
    try w.writeAll("\x1b\\");
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

// Simple stack-allocated writer for tests. std.io.fixedBufferStream is gone
// in 0.16; our write fns only need .writeAll so this suffices.
fn BufW(comptime cap: usize) type {
    return struct {
        buf: [cap]u8 = undefined,
        len: usize = 0,

        pub fn writeAll(self: *@This(), s: []const u8) error{NoSpaceLeft}!void {
            if (self.len + s.len > cap) return error.NoSpaceLeft;
            @memcpy(self.buf[self.len .. self.len + s.len], s);
            self.len += s.len;
        }

        pub fn written(self: *const @This()) []const u8 {
            return self.buf[0..self.len];
        }
    };
}

test "sgrReset emits ESC[0m" {
    var w: BufW(8) = .{};
    try sgrReset(&w);
    try std.testing.expectEqualStrings("\x1b[0m", w.written());
}

test "sgrFg rgb emits correct sequence" {
    var w: BufW(32) = .{};
    try sgrFg(&w, .{ .rgb = .{ .r = 255, .g = 87, .b = 51 } });
    try std.testing.expectEqualStrings("\x1b[38;2;255;87;51m", w.written());
}

test "sgrFg ansi16 bright_red emits ESC[91m" {
    var w: BufW(16) = .{};
    try sgrFg(&w, .{ .ansi16 = .bright_red });
    try std.testing.expectEqualStrings("\x1b[91m", w.written());
}

test "sgrBg ansi256 100 emits ESC[48;5;100m" {
    var w: BufW(16) = .{};
    try sgrBg(&w, .{ .ansi256 = 100 });
    try std.testing.expectEqualStrings("\x1b[48;5;100m", w.written());
}

test "sgrFg none emits ESC[39m" {
    var w: BufW(8) = .{};
    try sgrFg(&w, .none);
    try std.testing.expectEqualStrings("\x1b[39m", w.written());
}

test "sgrBold on emits ESC[1m" {
    var w: BufW(8) = .{};
    try sgrBold(&w, true);
    try std.testing.expectEqualStrings("\x1b[1m", w.written());
}

test "sgrBold off emits ESC[22m" {
    var w: BufW(8) = .{};
    try sgrBold(&w, false);
    try std.testing.expectEqualStrings("\x1b[22m", w.written());
}

test "sgrUnderline curly emits ESC[4:3m" {
    var w: BufW(8) = .{};
    try sgrUnderline(&w, .curly);
    try std.testing.expectEqualStrings("\x1b[4:3m", w.written());
}

test "cursorPos 5 10 emits ESC[5;10H" {
    var w: BufW(16) = .{};
    try cursorPos(&w, 5, 10);
    try std.testing.expectEqualStrings("\x1b[5;10H", w.written());
}

test "cursorPos 1 1 emits ESC[H" {
    var w: BufW(8) = .{};
    try cursorPos(&w, 1, 1);
    try std.testing.expectEqualStrings("\x1b[H", w.written());
}

test "modeSet alt_screen emits ESC[?1049h" {
    var w: BufW(16) = .{};
    try modeSet(&w, .alt_screen);
    try std.testing.expectEqualStrings("\x1b[?1049h", w.written());
}

test "modeReset alt_screen emits ESC[?1049l" {
    var w: BufW(16) = .{};
    try modeReset(&w, .alt_screen);
    try std.testing.expectEqualStrings("\x1b[?1049l", w.written());
}

test "syncOutputBegin emits ESC[?2026h" {
    var w: BufW(16) = .{};
    try syncOutputBegin(&w);
    try std.testing.expectEqualStrings("\x1b[?2026h", w.written());
}
