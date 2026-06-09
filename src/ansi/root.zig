// SPDX-License-Identifier: MIT

// Public surface of fern/ansi

/// color value - .none, .ansi16, .ansi256, or .rgb
pub const Color = @import("color.zig").Color;

/// the 16 named ANSI colors
pub const Ansi16 = @import("color.zig").Ansi16;

/// 24-bit RGB color
pub const Rgb = @import("color.zig").Rgb;

/// terminal color capability: no_color, ansi16, ansi256, true_color
pub const ColorProfile = @import("color.zig").ColorProfile;

/// SGR attributes for a cell or span (bold, italic, colors, etc.)
pub const Attrs = @import("csi.zig").Attrs;

/// cursor shape: default, block, bar, underline, each with optional blink
pub const CursorShape = @import("csi.zig").CursorShape;

/// DEC private mode number (DECSET/DECRST target)
pub const Mode = @import("csi.zig").Mode;

/// which mouse events the terminal should report
pub const MouseTrackingMode = @import("csi.zig").MouseTrackingMode;

/// what to erase: below, above, all, or scrollback
pub const EraseDisplay = @import("csi.zig").EraseDisplay;

/// what to erase on the current line: to_end, to_start, or all
pub const EraseLine = @import("csi.zig").EraseLine;

/// any terminal event: key, mouse, resize, focus, paste, or a query response
pub const Event = @import("parse.zig").Event;

/// a key press (or release/repeat) with modifiers
pub const KeyEvent = @import("parse.zig").KeyEvent;

/// which key was pressed - char, function key, arrow, keypad, etc.
pub const KeyCode = @import("parse.zig").KeyCode;

/// modifier flags: shift, ctrl, alt, super, hyper, meta
pub const KeyMods = @import("parse.zig").KeyMods;

/// mouse button press, release, or motion with position and modifiers
pub const MouseEvent = @import("parse.zig").MouseEvent;

/// terminal resize: new cols and rows
pub const ResizeEvent = @import("parse.zig").ResizeEvent;

/// focus gained or lost
pub const FocusEvent = @import("parse.zig").FocusEvent;

/// text from a bracketed paste. caller owns the slice.
pub const PasteEvent = @import("parse.zig").PasteEvent;

/// row/col from a CPR response
pub const CursorPos = @import("parse.zig").CursorPos;

/// terminal color query response - slot number, r/g/b as 16-bit components
pub const ColorReport = @import("parse.zig").ColorReport;

/// DA1/DA2 response - up to 8 params
pub const DaResponse = @import("parse.zig").DaResponse;

/// DECRPM response: which mode and its current value
pub const ModeReport = @import("parse.zig").ModeReport;

/// streaming input parser - feed bytes in, get Events out
pub const Parser = @import("parse.zig").Parser;

/// display width of a single unicode codepoint (0, 1, or 2 cells)
pub const cpWidth = @import("width.zig").cpWidth;

/// display width of a utf-8 string in terminal cells
pub const strWidth = @import("width.zig").strWidth;

/// byte length - no unicode, no ANSI awareness
pub const rawWidth = @import("width.zig").rawWidth;

/// string utilities: width, stripping, padding, wrapping
pub const str = struct {
    /// display width in terminal cells
    pub const strWidth = @import("str.zig").strWidth;
    /// byte length
    pub const rawWidth = @import("str.zig").rawWidth;
    /// strip ANSI escape sequences, returns owned slice
    pub const stripAnsi = @import("str.zig").stripAnsi;
    /// truncate to max display width, returns owned slice
    pub const truncate = @import("str.zig").truncate;
    /// right-pad to width with spaces, returns owned slice
    pub const pad = @import("str.zig").pad;
    /// left-pad to width with spaces, returns owned slice
    pub const padLeft = @import("str.zig").padLeft;
    /// iterate over newline-separated lines
    pub const splitLines = @import("str.zig").splitLines;
    /// number of newline-separated lines
    pub const lineCount = @import("str.zig").lineCount;
    /// display width of the widest line
    pub const maxLineWidth = @import("str.zig").maxLineWidth;
    /// word-wrap to a column width, returns owned slice
    pub const wrap = @import("str.zig").wrap;
    /// expand tab characters to spaces, returns owned slice
    pub const expandTabs = @import("str.zig").expandTabs;
};

/// SGR text styling sequences
pub const sgr = struct {
    /// ESC[m - reset all attributes
    pub const reset = @import("csi.zig").sgrReset;
    /// bold
    pub const bold = @import("csi.zig").sgrBold;
    /// italic
    pub const italic = @import("csi.zig").sgrItalic;
    /// dim/faint
    pub const faint = @import("csi.zig").sgrFaint;
    /// underline (style set via Attrs.Underline)
    pub const underline = @import("csi.zig").sgrUnderline;
    /// blink
    pub const blink = @import("csi.zig").sgrBlink;
    /// swap fg and bg
    pub const reverse = @import("csi.zig").sgrReverse;
    /// invisible text (still occupies cells)
    pub const conceal = @import("csi.zig").sgrConceal;
    /// strikethrough
    pub const strike = @import("csi.zig").sgrStrike;
    /// set foreground color
    pub const fg = @import("csi.zig").sgrFg;
    /// set background color
    pub const bg = @import("csi.zig").sgrBg;
    /// set underline color
    pub const ul_color = @import("csi.zig").sgrUlColor;
    /// emit only the SGR params that changed from prev to next
    pub const diff = @import("csi.zig").sgrDiff;
};

/// cursor movement and visibility sequences
pub const cursor = struct {
    /// move up n rows
    pub const up = @import("csi.zig").cursorUp;
    /// move down n rows
    pub const down = @import("csi.zig").cursorDown;
    /// move right n columns
    pub const forward = @import("csi.zig").cursorForward;
    /// move left n columns
    pub const back = @import("csi.zig").cursorBack;
    /// move to start of line, n rows down
    pub const next_line = @import("csi.zig").cursorNextLine;
    /// move to start of line, n rows up
    pub const prev_line = @import("csi.zig").cursorPrevLine;
    /// absolute column on the current row
    pub const col = @import("csi.zig").cursorCol;
    /// absolute row and column
    pub const pos = @import("csi.zig").cursorPos;
    /// move to 1,1
    pub const home = @import("csi.zig").cursorHome;
    /// DECSC - save cursor position
    pub const save = @import("csi.zig").cursorSave;
    /// DECRC - restore saved position
    pub const restore = @import("csi.zig").cursorRestore;
    /// DECSCUSR - set cursor shape
    pub const shape = @import("csi.zig").cursorShape;
    /// CPR - request current cursor position
    pub const request = @import("csi.zig").cursorRequest;
    /// DECTCEM on - show cursor
    pub const show = @import("csi.zig").showCursor;
    /// DECTCEM off - hide cursor
    pub const hide = @import("csi.zig").hideCursor;
};

/// screen and terminal state sequences
pub const screen = struct {
    /// ED - erase part or all of the display
    pub const erase_display = @import("csi.zig").eraseDisplay;
    /// EL - erase part or all of the current line
    pub const erase_line = @import("csi.zig").eraseLine;
    /// scroll up n lines
    pub const scroll_up = @import("csi.zig").scrollUp;
    /// scroll down n lines
    pub const scroll_down = @import("csi.zig").scrollDown;
    /// DECSET 1049 - enter alternate screen
    pub const alt_enter = @import("csi.zig").altScreenEnter;
    /// DECRST 1049 - leave alternate screen
    pub const alt_leave = @import("csi.zig").altScreenLeave;
    /// synchronized output begin (mode 2026)
    pub const sync_begin = @import("csi.zig").syncOutputBegin;
    /// synchronized output end
    pub const sync_end = @import("csi.zig").syncOutputEnd;
    /// enable mouse tracking
    pub const mouse_enter = @import("csi.zig").mouseTrackingEnter;
    /// disable mouse tracking
    pub const mouse_leave = @import("csi.zig").mouseTrackingLeave;
    /// DECSET 2004 - enable bracketed paste
    pub const paste_enter = @import("csi.zig").bracketedPasteEnter;
    /// DECRST 2004 - disable bracketed paste
    pub const paste_leave = @import("csi.zig").bracketedPasteLeave;
    /// DECSET 1004 - enable focus reporting
    pub const focus_enter = @import("csi.zig").focusReportingEnter;
    /// DECRST 1004 - disable focus reporting
    pub const focus_leave = @import("csi.zig").focusReportingLeave;
};

/// OSC sequences: window title, clipboard, hyperlinks, terminal colors
pub const osc = struct {
    /// OSC 0 - set window title
    pub const set_title = @import("osc.zig").setTitle;
    /// OSC 1 - set icon name
    pub const set_icon_name = @import("osc.zig").setIconName;
    /// OSC 8 - start a hyperlink
    pub const hyperlink = @import("osc.zig").hyperlinkStart;
    /// OSC 8;; - end a hyperlink
    pub const hyperlink_end = @import("osc.zig").hyperlinkEnd;
    /// OSC 52 - write to clipboard (base64-encodes internally)
    pub const clipboard_set = @import("osc.zig").setClipboard;
    /// OSC 52;target;? - request clipboard content
    pub const clipboard_req = @import("osc.zig").requestClipboard;
    /// OSC 10 - set terminal foreground color
    pub const set_fg = @import("osc.zig").setFgColor;
    /// OSC 11 - set terminal background color
    pub const set_bg = @import("osc.zig").setBgColor;
    /// OSC 12 - set cursor color
    pub const set_cursor = @import("osc.zig").setCursorColor;
    /// OSC 110 - reset foreground to default
    pub const reset_fg = @import("osc.zig").resetFgColor;
    /// OSC 111 - reset background to default
    pub const reset_bg = @import("osc.zig").resetBgColor;
    /// OSC 112 - reset cursor color to default
    pub const reset_cursor = @import("osc.zig").resetCursorColor;
    /// OSC 10? - query foreground color
    pub const query_fg = @import("osc.zig").queryFgColor;
    /// OSC 11? - query background color
    pub const query_bg = @import("osc.zig").queryBgColor;
    /// system notification (OSC 9 or 777 depending on terminal)
    pub const notify = @import("osc.zig").notify;
};

/// terminal capability queries
pub const query = struct {
    /// XTGETTCAP "TN" - query terminal name
    pub const term_name = @import("csi.zig").queryTermName;
    /// DA1 - primary device attributes
    pub const primary_da = @import("csi.zig").queryPrimaryDa;
    /// DA2 - secondary device attributes
    pub const secondary_da = @import("csi.zig").querySecondaryDa;
    /// XTGETTCAP - query a termcap capability by name
    pub const termcap = @import("csi.zig").queryTermcap;
    /// OSC 11? - query background color
    pub const bg_color = @import("osc.zig").queryBgColor;
    /// OSC 10? - query foreground color
    pub const fg_color = @import("osc.zig").queryFgColor;
};
