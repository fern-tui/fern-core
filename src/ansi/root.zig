// SPDX-License-Identifier: MIT

// root.zig - fern.ansi public surface
//
// Users: const ansi = @import("fern_ansi");
// Import graph: root -> color, csi, osc, parse, width, str (no cycles)

pub const Color = @import("color.zig").Color;
pub const Ansi16 = @import("color.zig").Ansi16;
pub const Rgb = @import("color.zig").Rgb;
pub const ColorProfile = @import("color.zig").ColorProfile;

pub const Attrs = @import("csi.zig").Attrs;
pub const CursorShape = @import("csi.zig").CursorShape;
pub const Mode = @import("csi.zig").Mode;
pub const MouseTrackingMode = @import("csi.zig").MouseTrackingMode;
pub const EraseDisplay = @import("csi.zig").EraseDisplay;
pub const EraseLine = @import("csi.zig").EraseLine;

pub const Event = @import("parse.zig").Event;
pub const KeyEvent = @import("parse.zig").KeyEvent;
pub const KeyCode = @import("parse.zig").KeyCode;
pub const KeyMods = @import("parse.zig").KeyMods;
pub const MouseEvent = @import("parse.zig").MouseEvent;
pub const ResizeEvent = @import("parse.zig").ResizeEvent;
pub const FocusEvent = @import("parse.zig").FocusEvent;
pub const PasteEvent = @import("parse.zig").PasteEvent;
pub const CursorPos = @import("parse.zig").CursorPos;
pub const ColorReport = @import("parse.zig").ColorReport;
pub const DaResponse = @import("parse.zig").DaResponse;
pub const ModeReport = @import("parse.zig").ModeReport;
pub const Parser = @import("parse.zig").Parser;

pub const cpWidth = @import("width.zig").cpWidth;
pub const strWidth = @import("width.zig").strWidth;
pub const rawWidth = @import("width.zig").rawWidth;

pub const str = struct {
    pub const strWidth = @import("str.zig").strWidth;
    pub const rawWidth = @import("str.zig").rawWidth;
    pub const stripAnsi = @import("str.zig").stripAnsi;
    pub const truncate = @import("str.zig").truncate;
    pub const pad = @import("str.zig").pad;
    pub const padLeft = @import("str.zig").padLeft;
    pub const splitLines = @import("str.zig").splitLines;
    pub const lineCount = @import("str.zig").lineCount;
    pub const maxLineWidth = @import("str.zig").maxLineWidth;
    pub const wrap = @import("str.zig").wrap;
    pub const expandTabs = @import("str.zig").expandTabs;
};

pub const sgr = struct {
    pub const reset = @import("csi.zig").sgrReset;
    pub const bold = @import("csi.zig").sgrBold;
    pub const italic = @import("csi.zig").sgrItalic;
    pub const faint = @import("csi.zig").sgrFaint;
    pub const underline = @import("csi.zig").sgrUnderline;
    pub const blink = @import("csi.zig").sgrBlink;
    pub const reverse = @import("csi.zig").sgrReverse;
    pub const conceal = @import("csi.zig").sgrConceal;
    pub const strike = @import("csi.zig").sgrStrike;
    pub const fg = @import("csi.zig").sgrFg;
    pub const bg = @import("csi.zig").sgrBg;
    pub const ul_color = @import("csi.zig").sgrUlColor;
    pub const diff = @import("csi.zig").sgrDiff;
};

pub const cursor = struct {
    pub const up = @import("csi.zig").cursorUp;
    pub const down = @import("csi.zig").cursorDown;
    pub const forward = @import("csi.zig").cursorForward;
    pub const back = @import("csi.zig").cursorBack;
    pub const next_line = @import("csi.zig").cursorNextLine;
    pub const prev_line = @import("csi.zig").cursorPrevLine;
    pub const col = @import("csi.zig").cursorCol;
    pub const pos = @import("csi.zig").cursorPos;
    pub const home = @import("csi.zig").cursorHome;
    pub const save = @import("csi.zig").cursorSave;
    pub const restore = @import("csi.zig").cursorRestore;
    pub const shape = @import("csi.zig").cursorShape;
    pub const request = @import("csi.zig").cursorRequest;
    pub const show = @import("csi.zig").showCursor;
    pub const hide = @import("csi.zig").hideCursor;
};

pub const screen = struct {
    pub const erase_display = @import("csi.zig").eraseDisplay;
    pub const erase_line = @import("csi.zig").eraseLine;
    pub const scroll_up = @import("csi.zig").scrollUp;
    pub const scroll_down = @import("csi.zig").scrollDown;
    pub const alt_enter = @import("csi.zig").altScreenEnter;
    pub const alt_leave = @import("csi.zig").altScreenLeave;
    pub const sync_begin = @import("csi.zig").syncOutputBegin;
    pub const sync_end = @import("csi.zig").syncOutputEnd;
    pub const mouse_enter = @import("csi.zig").mouseTrackingEnter;
    pub const mouse_leave = @import("csi.zig").mouseTrackingLeave;
    pub const paste_enter = @import("csi.zig").bracketedPasteEnter;
    pub const paste_leave = @import("csi.zig").bracketedPasteLeave;
    pub const focus_enter = @import("csi.zig").focusReportingEnter;
    pub const focus_leave = @import("csi.zig").focusReportingLeave;
};

pub const osc = struct {
    pub const set_title = @import("osc.zig").setTitle;
    pub const set_icon_name = @import("osc.zig").setIconName;
    pub const hyperlink = @import("osc.zig").hyperlinkStart;
    pub const hyperlink_end = @import("osc.zig").hyperlinkEnd;
    pub const clipboard_set = @import("osc.zig").setClipboard;
    pub const clipboard_req = @import("osc.zig").requestClipboard;
    pub const set_fg = @import("osc.zig").setFgColor;
    pub const set_bg = @import("osc.zig").setBgColor;
    pub const set_cursor = @import("osc.zig").setCursorColor;
    pub const reset_fg = @import("osc.zig").resetFgColor;
    pub const reset_bg = @import("osc.zig").resetBgColor;
    pub const reset_cursor = @import("osc.zig").resetCursorColor;
    pub const query_fg = @import("osc.zig").queryFgColor;
    pub const query_bg = @import("osc.zig").queryBgColor;
    pub const notify = @import("osc.zig").notify;
};

pub const query = struct {
    pub const term_name = @import("csi.zig").queryTermName;
    pub const primary_da = @import("csi.zig").queryPrimaryDa;
    pub const secondary_da = @import("csi.zig").querySecondaryDa;
    pub const termcap = @import("csi.zig").queryTermcap;
    pub const bg_color = @import("osc.zig").queryBgColor;
    pub const fg_color = @import("osc.zig").queryFgColor;
};
