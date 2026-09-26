// SPDX-License-Identifier: MIT

//! Public API surface for fern/ansi.
//!
//! Exposes parsing, encoding, color degradation, string manipulation, and
//! rendering sequences for terminal UI handling.

/// Base color variants: `.none`, `.ansi16`, `.ansi256`, or `.rgb`.
pub const Color = @import("color.zig").Color;

/// The 16 baseline ANSI color identifiers.
pub const Ansi16 = @import("color.zig").Ansi16;

/// 24-bit RGB true color representation.
pub const Rgb = @import("color.zig").Rgb;

/// Terminal capability identifiers: `no_color`, `ansi16`, `ansi256`, `true_color`.
pub const ColorProfile = @import("color.zig").ColorProfile;

/// SGR attributes applied to a single display cell (e.g., bold, italics, colors).
pub const Attrs = @import("csi.zig").Attrs;

/// Geometric styling definition of the active cursor state.
pub const CursorShape = @import("csi.zig").CursorShape;

/// Standard DEC Private modes identifier block.
pub const Mode = @import("csi.zig").Mode;

/// Operational tracking depth constraints on mouse interactions.
pub const MouseTrackingMode = @import("csi.zig").MouseTrackingMode;

/// Target direction for Erase in Display (ED) sequences.
pub const EraseDisplay = @import("csi.zig").EraseDisplay;

/// Target direction for Erase in Line (EL) sequences.
pub const EraseLine = @import("csi.zig").EraseLine;

/// Base event representation capturing keypresses, mouse actions, and terminal reports.
pub const Event = @import("parse.zig").Event;

/// State definition encapsulating physical keyboard stroke conditions.
pub const KeyEvent = @import("parse.zig").KeyEvent;

/// Physical hardware key mapping definitions.
pub const KeyCode = @import("parse.zig").KeyCode;

/// Binary modifier flags evaluating `shift`, `ctrl`, `alt`, `super`, `hyper`, `meta`.
pub const KeyMods = @import("parse.zig").KeyMods;

/// State definition encapsulating physical mouse actions and positioning parameters.
pub const MouseEvent = @import("parse.zig").MouseEvent;

/// Dimensions reported following a window or interface area resize.
pub const ResizeEvent = @import("parse.zig").ResizeEvent;

/// Window interface focus transitions.
pub const FocusEvent = @import("parse.zig").FocusEvent;

/// Content retrieved from a bracketed paste invocation block.
/// The text slice is owned by the caller.
pub const PasteEvent = @import("parse.zig").PasteEvent;

/// Two-dimensional coordinate vector matching a valid terminal row/col point.
pub const CursorPos = @import("parse.zig").CursorPos;

/// Values extracted via an OSC window system properties inquiry.
pub const ColorReport = @import("parse.zig").ColorReport;

/// Output array from a Device Attributes check.
pub const DaResponse = @import("parse.zig").DaResponse;

/// Results evaluated during DECRPM checks determining sequence capability sets.
pub const ModeReport = @import("parse.zig").ModeReport;

/// Stateful sequence parser for resolving raw serial byte-streams to discrete `Event` models.
pub const Parser = @import("parse.zig").Parser;

/// Resolves total visible dimension space needed to display a single unicode codepoint.
pub const cpWidth = @import("width.zig").cpWidth;

/// Resolves total visible dimension space needed to display a full UTF-8 encoded string.
pub const strWidth = @import("width.zig").strWidth;

/// Checks unmodified byte-length constraints without evaluating layout widths.
pub const rawWidth = @import("width.zig").rawWidth;

/// Provides tools for text wrapping, layout rendering, length bounds checks, and truncation.
pub const str = struct {
    /// Evaluates display width in terminal cells.
    pub const strWidth = @import("str.zig").strWidth;
    /// Evaluates raw byte length.
    pub const rawWidth = @import("str.zig").rawWidth;
    /// Strips ANSI escape sequences. Returns an allocated slice that caller must free.
    pub const stripAnsi = @import("str.zig").stripAnsi;
    /// Truncates to maximum display width. Returns an allocated slice that caller must free.
    pub const truncate = @import("str.zig").truncate;
    /// Right-pads to the specified width with spaces. Returns an allocated slice that caller must free.
    pub const pad = @import("str.zig").pad;
    /// Left-pads to the specified width with spaces. Returns an allocated slice that caller must free.
    pub const padLeft = @import("str.zig").padLeft;
    /// Iterates over newline-separated lines. Returns an allocated slice of strings.
    pub const splitLines = @import("str.zig").splitLines;
    /// Counts the number of newline-separated lines.
    pub const lineCount = @import("str.zig").lineCount;
    /// Returns the display width of the widest line in a multi-line string.
    pub const maxLineWidth = @import("str.zig").maxLineWidth;
    /// Word-wraps text to a specific column width. Returns an allocated slice that caller must free.
    pub const wrap = @import("str.zig").wrap;
    /// Expands tab characters to spaces. Returns an allocated slice that caller must free.
    pub const expandTabs = @import("str.zig").expandTabs;
};

/// Emits Control Sequence Introducer styles matching target rendering attributes.
pub const sgr = struct {
    /// ESC[m - resets all active attributes.
    pub const reset = @import("csi.zig").sgrReset;
    /// Configures bold typography definitions.
    pub const bold = @import("csi.zig").sgrBold;
    /// Configures italic typography definitions.
    pub const italic = @import("csi.zig").sgrItalic;
    /// Configures dim or faint typography definitions.
    pub const faint = @import("csi.zig").sgrFaint;
    /// Configures underline styling variables.
    pub const underline = @import("csi.zig").sgrUnderline;
    /// Establishes slow and rapid visual blink timing sets.
    pub const blink = @import("csi.zig").sgrBlink;
    /// Swaps the foreground and background colors.
    pub const reverse = @import("csi.zig").sgrReverse;
    /// Triggers invisible output text formatting (text still occupies cells).
    pub const conceal = @import("csi.zig").sgrConceal;
    /// Enables strikethrough configuration variables.
    pub const strike = @import("csi.zig").sgrStrike;
    /// Sets foreground color.
    pub const fg = @import("csi.zig").sgrFg;
    /// Sets background color.
    pub const bg = @import("csi.zig").sgrBg;
    /// Sets the underline stroke color.
    pub const ul_color = @import("csi.zig").sgrUlColor;
    /// Emits only the SGR parameters that changed from `prev` to `next`.
    pub const diff = @import("csi.zig").sgrDiff;
};

/// Cursor movement and visibility sequences.
pub const cursor = struct {
    /// Moves the cursor up `n` rows.
    pub const up = @import("csi.zig").cursorUp;
    /// Moves the cursor down `n` rows.
    pub const down = @import("csi.zig").cursorDown;
    /// Moves the cursor right `n` columns.
    pub const forward = @import("csi.zig").cursorForward;
    /// Moves the cursor left `n` columns.
    pub const back = @import("csi.zig").cursorBack;
    /// Moves to the start of the line, `n` rows down.
    pub const next_line = @import("csi.zig").cursorNextLine;
    /// Moves to the start of the line, `n` rows up.
    pub const prev_line = @import("csi.zig").cursorPrevLine;
    /// Sets the absolute column on the current row.
    pub const col = @import("csi.zig").cursorCol;
    /// Sets the absolute row and column.
    pub const pos = @import("csi.zig").cursorPos;
    /// Moves to origin (1,1).
    pub const home = @import("csi.zig").cursorHome;
    /// DECSC - saves the current cursor position.
    pub const save = @import("csi.zig").cursorSave;
    /// DECRC - restores the saved cursor position.
    pub const restore = @import("csi.zig").cursorRestore;
    /// DECSCUSR - sets the active cursor shape.
    pub const shape = @import("csi.zig").cursorShape;
    /// CPR - requests the current cursor position from the terminal.
    pub const request = @import("csi.zig").cursorRequest;
    /// DECTCEM on - makes the cursor visible.
    pub const show = @import("csi.zig").showCursor;
    /// DECTCEM off - hides the cursor.
    pub const hide = @import("csi.zig").hideCursor;
};

/// Screen clear operations and terminal state sequences.
pub const screen = struct {
    /// ED - erases part or all of the display buffer.
    pub const erase_display = @import("csi.zig").eraseDisplay;
    /// EL - erases part or all of the current line.
    pub const erase_line = @import("csi.zig").eraseLine;
    /// Scrolls the viewport up `n` lines.
    pub const scroll_up = @import("csi.zig").scrollUp;
    /// Scrolls the viewport down `n` lines.
    pub const scroll_down = @import("csi.zig").scrollDown;
    /// DECSET 1049 - enters the alternate screen buffer.
    pub const alt_enter = @import("csi.zig").altScreenEnter;
    /// DECRST 1049 - leaves the alternate screen buffer.
    pub const alt_leave = @import("csi.zig").altScreenLeave;
    /// DECSET 2026 - begins synchronized output rendering.
    pub const sync_begin = @import("csi.zig").syncOutputBegin;
    /// DECRST 2026 - ends synchronized output rendering.
    pub const sync_end = @import("csi.zig").syncOutputEnd;
    /// Enables terminal mouse tracking.
    pub const mouse_enter = @import("csi.zig").mouseTrackingEnter;
    /// Disables terminal mouse tracking.
    pub const mouse_leave = @import("csi.zig").mouseTrackingLeave;
    /// DECSET 2004 - enables bracketed paste mode.
    pub const paste_enter = @import("csi.zig").bracketedPasteEnter;
    /// DECRST 2004 - disables bracketed paste mode.
    pub const paste_leave = @import("csi.zig").bracketedPasteLeave;
    /// DECSET 1004 - enables focus reporting.
    pub const focus_enter = @import("csi.zig").focusReportingEnter;
    /// DECRST 1004 - disables focus reporting.
    pub const focus_leave = @import("csi.zig").focusReportingLeave;
};

/// Operating System Command (OSC) sequence generators.
pub const osc = struct {
    /// OSC 0 - sets the host window title.
    pub const set_title = @import("osc.zig").setTitle;
    /// OSC 1 - sets the host icon name.
    pub const set_icon_name = @import("osc.zig").setIconName;
    /// OSC 8 - starts a clickable hyperlink span.
    pub const hyperlink = @import("osc.zig").hyperlinkStart;
    /// OSC 8;; - ends a clickable hyperlink span.
    pub const hyperlink_end = @import("osc.zig").hyperlinkEnd;
    /// OSC 52 - pushes data to the host clipboard (handles base64 encoding internally).
    pub const clipboard_set = @import("osc.zig").setClipboard;
    /// OSC 52;target;? - requests the host clipboard content.
    pub const clipboard_req = @import("osc.zig").requestClipboard;
    /// OSC 10 - sets the global terminal foreground color.
    pub const set_fg = @import("osc.zig").setFgColor;
    /// OSC 11 - sets the global terminal background color.
    pub const set_bg = @import("osc.zig").setBgColor;
    /// OSC 12 - sets the cursor color.
    pub const set_cursor = @import("osc.zig").setCursorColor;
    /// OSC 110 - resets the global foreground to default.
    pub const reset_fg = @import("osc.zig").resetFgColor;
    /// OSC 111 - resets the global background to default.
    pub const reset_bg = @import("osc.zig").resetBgColor;
    /// OSC 112 - resets the cursor color to default.
    pub const reset_cursor = @import("osc.zig").resetCursorColor;
    /// OSC 10? - queries the global foreground color.
    pub const query_fg = @import("osc.zig").queryFgColor;
    /// OSC 11? - queries the global background color.
    pub const query_bg = @import("osc.zig").queryBgColor;
    /// Triggers a native system notification (supports both OSC 9 and 777 formats).
    pub const notify = @import("osc.zig").notify;
};

/// Terminal capability querying endpoints.
pub const query = struct {
    /// XTGETTCAP "TN" - queries the terminal name.
    pub const term_name = @import("csi.zig").queryTermName;
    /// DA1 - requests primary device attributes.
    pub const primary_da = @import("csi.zig").queryPrimaryDa;
    /// DA2 - requests secondary device attributes.
    pub const secondary_da = @import("csi.zig").querySecondaryDa;
    /// XTGETTCAP - queries a specific termcap capability by name.
    pub const termcap = @import("csi.zig").queryTermcap;
    /// OSC 11? - queries the active background color.
    pub const bg_color = @import("osc.zig").queryBgColor;
    /// OSC 10? - queries the active foreground color.
    pub const fg_color = @import("osc.zig").queryFgColor;
};
