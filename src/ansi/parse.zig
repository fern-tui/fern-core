// SPDX-License-Identifier: MIT

// parse.zig - VT/ANSI input parser: bytes -> Event
//
// Deps: color.zig, width.zig (width only for future use; not imported here)
// Allocates only for paste content, unknown sequences, and OSC unknown bodies.
// Everything else is stack-only.

const std = @import("std");
const color = @import("color.zig");

pub const KeyCode = union(enum) {
    char: u21,
    enter,
    backspace,
    delete,
    tab,
    backtab,
    escape,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    insert,
    f: u8, // F1-F35, 1-indexed
    kp_enter,
    kp_char: u21,
    kp_up,
    kp_down,
    kp_left,
    kp_right,
    kp_home,
    kp_end,
    kp_page_up,
    kp_page_down,
    kp_insert,
    kp_delete,
    kp_begin,
};

pub const KeyMods = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    _pad: u2 = 0,

    // CSI modifier param uses 1-based: unmodified=1, shift=2, ctrl=5...
    pub fn csiBit(self: KeyMods) u8 {
        var n: u8 = 0;
        if (self.shift) n |= 1;
        if (self.alt) n |= 2;
        if (self.ctrl) n |= 4;
        if (self.super) n |= 8;
        return n + 1;
    }

    pub fn fromCsi(param: u8) KeyMods {
        const v = param -| 1;
        return .{
            .shift = (v & 1) != 0,
            .alt = (v & 2) != 0,
            .ctrl = (v & 4) != 0,
            .super = (v & 8) != 0,
        };
    }
};

pub const KeyEvent = struct {
    code: KeyCode,
    mods: KeyMods = .{},
    kind: KeyKind = .press,

    pub const KeyKind = enum { press, release, repeat };
};

pub const MouseEvent = struct {
    col: u16,
    row: u16,
    button: Button,
    mods: KeyMods = .{},
    kind: Kind,

    pub const Kind = enum { press, release, motion };

    pub const Button = enum(u8) {
        none = 0,
        left = 1,
        middle = 2,
        right = 3,
        wheel_up = 4,
        wheel_down = 5,
        wheel_left = 6,
        wheel_right = 7,
        btn8 = 8,
        btn9 = 9,
        btn10 = 10,
        btn11 = 11,
    };
};

pub const ResizeEvent = struct { cols: u16, rows: u16 };
pub const FocusEvent = enum { gained, lost };
pub const PasteEvent = struct { text: []const u8 }; // caller owns
pub const CursorPos = struct { row: u16, col: u16 };
pub const ColorReport = struct { slot: u8, r: u16, g: u16, b: u16 };
pub const DaResponse = struct { params: [8]u16, len: u4 };
pub const ModeReport = struct { mode: u16, value: u8 };

pub const Event = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: ResizeEvent,
    focus: FocusEvent,
    paste: PasteEvent, // allocates content slice
    cursor_pos: CursorPos,
    color_report: ColorReport,
    da_response: DaResponse,
    mode_report: ModeReport,
    unknown: []const u8, // allocates
};

const State = enum {
    ground,
    escape,
    ss3,
    csi_entry,
    csi_param,
    csi_inter,
    osc_string,
    dcs_entry,
    dcs_param,
    dcs_inter,
    dcs_passthrough,
    dcs_ignore,
    sos_pm_apc,
    utf8_2,
    utf8_3,
    utf8_4,
    bracketed_paste,
};

const MAX_PARAMS = 8;
const MAX_SUBPARAMS = 2; // colon-separated within one param slot

// Parsed parameter block from a CSI sequence.
const CsiParams = struct {
    vals: [MAX_PARAMS][MAX_SUBPARAMS]u16,
    n_main: u4, // number of main params
    n_sub: [MAX_PARAMS]u2, // sub-param count per slot

    fn main(self: *const CsiParams, i: usize) u16 {
        if (i >= self.n_main) return 0;
        return self.vals[i][0];
    }

    fn sub(self: *const CsiParams, i: usize, j: usize) u16 {
        if (i >= self.n_main) return 0;
        if (j >= self.n_sub[i]) return 0;
        return self.vals[i][j];
    }
};

pub const Parser = struct {
    state: State = .ground,
    param_buf: [32]u8 = undefined,
    param_len: u8 = 0,
    inter_buf: [4]u8 = undefined,
    inter_len: u4 = 0,
    osc_buf: [512]u8 = undefined,
    osc_len: u16 = 0,
    utf8_buf: [4]u8 = undefined,
    utf8_rem: u3 = 0,
    utf8_cp: u21 = 0,
    ate_cr: bool = false, // CR+LF de-dup
    sgr_lt: bool = false, // saw '<' in CSI param (SGR mouse prefix)
    paste_buf: std.ArrayList(u8) = .empty,

    pub fn init() Parser {
        return .{};
    }

    // Release the internal paste buffer. Call when the parser is no longer needed.
    pub fn deinit(self: *Parser, alloc: std.mem.Allocator) void {
        self.paste_buf.deinit(alloc);
    }

    pub fn reset(self: *Parser) void {
        self.state = .ground;
        self.param_len = 0;
        self.inter_len = 0;
        self.osc_len = 0;
        self.utf8_rem = 0;
        self.utf8_cp = 0;
        self.ate_cr = false;
        self.sgr_lt = false;
    }

    pub fn feed(
        self: *Parser,
        byte: u8,
        alloc: std.mem.Allocator,
    ) !?Event {
        return switch (self.state) {
            .ground => self.groundByte(byte, alloc),
            .escape => self.escapeByte(byte, alloc),
            .ss3 => self.ss3Byte(byte, alloc),
            .csi_entry => self.csiEntryByte(byte, alloc),
            .csi_param => self.csiParamByte(byte, alloc),
            .csi_inter => self.csiInterByte(byte, alloc),
            .osc_string => self.oscByte(byte, alloc),
            .dcs_entry, .dcs_param, .dcs_inter, .dcs_passthrough => self.dcsByte(byte, alloc),
            .dcs_ignore => self.dcsIgnoreByte(byte),
            .sos_pm_apc => self.sosByte(byte),
            .utf8_2, .utf8_3, .utf8_4 => self.utf8ContinueByte(byte),
            .bracketed_paste => self.pasteByte(byte, alloc),
        };
    }

    pub fn feedSlice(
        self: *Parser,
        bytes: []const u8,
        alloc: std.mem.Allocator,
    ) !?Event {
        for (bytes) |b| {
            if (try self.feed(b, alloc)) |ev| return ev;
        }
        return null;
    }

    pub fn feedAll(
        self: *Parser,
        bytes: []const u8,
        out_events: *std.ArrayList(Event),
        alloc: std.mem.Allocator,
    ) !void {
        for (bytes) |b| {
            if (try self.feed(b, alloc)) |ev| {
                try out_events.append(alloc, ev);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Ground state
    // -----------------------------------------------------------------------

    fn groundByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        // CR+LF de-dup: if previous byte was CR and this is LF, eat it.
        if (self.ate_cr and byte == 0x0A) {
            self.ate_cr = false;
            return null;
        }
        self.ate_cr = false;

        return switch (byte) {
            0x00 => keyEvent(.{ .char = ' ' }, .{ .ctrl = true }),
            0x01...0x07 => |b| keyEvent(.{ .char = @as(u21, 'a' + b - 1) }, .{ .ctrl = true }),
            0x08 => keyEvent(.backspace, .{ .ctrl = true }),
            0x09 => keyEvent(.tab, .{}),
            0x0A => keyEvent(.enter, .{}),
            0x0B => keyEvent(.{ .char = 'k' }, .{ .ctrl = true }),
            0x0C => keyEvent(.{ .char = 'l' }, .{ .ctrl = true }),
            0x0D => blk: {
                self.ate_cr = true;
                break :blk keyEvent(.enter, .{});
            },
            0x0E...0x1A => |b| keyEvent(.{ .char = @as(u21, 'n' + b - 0x0E) }, .{ .ctrl = true }),
            0x1B => blk: {
                self.beginEscape();
                break :blk null;
            },
            0x1C => keyEvent(.{ .char = '\\' }, .{ .ctrl = true }),
            0x1D => keyEvent(.{ .char = ']' }, .{ .ctrl = true }),
            0x1E => keyEvent(.{ .char = '^' }, .{ .ctrl = true }),
            0x1F => keyEvent(.{ .char = '_' }, .{ .ctrl = true }),
            0x20...0x7E => |b| keyEvent(.{ .char = b }, .{}),
            0x7F => keyEvent(.backspace, .{}),
            0x80...0xBF => try self.emitUnknown(alloc, &.{byte}),
            0xC0...0xDF => |b| {
                self.beginUtf8(2, b & 0x1F);
                return null;
            },
            0xE0...0xEF => |b| {
                self.beginUtf8(3, b & 0x0F);
                return null;
            },
            0xF0...0xF7 => |b| {
                self.beginUtf8(4, b & 0x07);
                return null;
            },
            else => try self.emitUnknown(alloc, &.{byte}),
        };
    }

    // -----------------------------------------------------------------------
    // Escape state
    // -----------------------------------------------------------------------

    fn beginEscape(self: *Parser) void {
        self.state = .escape;
        self.param_len = 0;
        self.inter_len = 0;
        self.sgr_lt = false;
    }

    fn escapeByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        return switch (byte) {
            0x1B => blk: {
                // Double ESC: emit a bare escape, stay in escape for next
                self.state = .ground;
                break :blk keyEvent(.escape, .{});
            },
            '[' => blk: {
                self.state = .csi_entry;
                self.param_len = 0;
                self.inter_len = 0;
                self.sgr_lt = false;
                break :blk null;
            },
            'O' => blk: {
                self.state = .ss3;
                break :blk null;
            },
            ']' => blk: {
                self.state = .osc_string;
                self.osc_len = 0;
                break :blk null;
            },
            'P' => blk: {
                self.state = .dcs_entry;
                self.param_len = 0;
                self.inter_len = 0;
                break :blk null;
            },
            'X', '^', '_' => blk: {
                self.state = .sos_pm_apc;
                break :blk null;
            },
            // DEC save/restore cursor: no parser event; pass through silently
            '7', '8' => blk: {
                self.state = .ground;
                break :blk null;
            },
            'c' => blk: {
                // full reset; let app handle it
                self.state = .ground;
                break :blk try self.emitUnknown(alloc, "\x1bc");
            },
            0x20...0x2F => blk: {
                // ESC intermediate
                self.addInter(byte);
                // remain in escape state to accumulate more intermediates
                break :blk null;
            },
            else => blk: {
                self.state = .ground;
                // 0x40-0x7E bytes not caught by named cases above: unrecognised C1 final.
                if (byte >= 0x40 and byte <= 0x7E) {
                    break :blk try self.emitUnknown(alloc, &.{ 0x1B, byte });
                }
                // 0x30-0x3F: ESC + digit/punct -> Alt+char.
                if (byte >= 0x30 and byte <= 0x3F) {
                    break :blk keyEvent(.{ .char = byte }, .{ .alt = true });
                }
                // < 0x20 (0x1B already handled above): Alt + C0 control char.
                var ctrl_ev = try self.groundByte(byte, alloc);
                if (ctrl_ev) |*ke| {
                    if (std.meta.activeTag(ke.*) == .key) {
                        ke.key.mods.alt = true;
                    }
                }
                break :blk ctrl_ev;
            },
        };
    }

    // -----------------------------------------------------------------------
    // SS3
    // -----------------------------------------------------------------------

    fn ss3Byte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        self.state = .ground;
        return switch (byte) {
            'A' => keyEvent(.up, .{}),
            'B' => keyEvent(.down, .{}),
            'C' => keyEvent(.right, .{}),
            'D' => keyEvent(.left, .{}),
            'H' => keyEvent(.home, .{}),
            'F' => keyEvent(.end, .{}),
            'M' => keyEvent(.kp_enter, .{}),
            'P' => keyEvent(.{ .f = 1 }, .{}),
            'Q' => keyEvent(.{ .f = 2 }, .{}),
            'R' => keyEvent(.{ .f = 3 }, .{}),
            'S' => keyEvent(.{ .f = 4 }, .{}),
            else => try self.emitUnknown(alloc, &.{ 0x1B, 'O', byte }),
        };
    }

    // -----------------------------------------------------------------------
    // CSI entry: collect first byte
    // -----------------------------------------------------------------------

    fn csiEntryByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        if (byte >= 0x40 and byte <= 0x7E) {
            // immediate final with no params
            self.state = .ground;
            return self.dispatchCsi(byte, alloc);
        }
        if (byte == '<') {
            // SGR mouse prefix
            self.sgr_lt = true;
            self.state = .csi_param;
            return null;
        }
        if (byte >= 0x30 and byte <= 0x3F) {
            self.param_buf[0] = byte;
            self.param_len = 1;
            self.state = .csi_param;
            return null;
        }
        if (byte >= 0x20 and byte <= 0x2F) {
            self.addInter(byte);
            self.state = .csi_inter;
            return null;
        }
        self.state = .ground;
        return try self.emitUnknown(alloc, &.{ 0x1B, '[', byte });
    }

    fn csiParamByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        if (byte >= 0x40 and byte <= 0x7E) {
            self.state = .ground;
            return self.dispatchCsi(byte, alloc);
        }
        if ((byte >= 0x30 and byte <= 0x39) or byte == ';' or byte == ':') {
            if (self.param_len < self.param_buf.len) {
                self.param_buf[self.param_len] = byte;
                self.param_len += 1;
            }
            return null;
        }
        if (byte >= 0x20 and byte <= 0x2F) {
            self.addInter(byte);
            self.state = .csi_inter;
            return null;
        }
        self.state = .ground;
        return null;
    }

    fn csiInterByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        if (byte >= 0x40 and byte <= 0x7E) {
            self.state = .ground;
            return self.dispatchCsi(byte, alloc);
        }
        if (byte >= 0x20 and byte <= 0x2F) {
            self.addInter(byte);
            return null;
        }
        self.state = .ground;
        return null;
    }

    // -----------------------------------------------------------------------
    // CSI dispatch
    // -----------------------------------------------------------------------

    fn parseCsiParams(self: *const Parser) CsiParams {
        var out: CsiParams = .{
            .vals = std.mem.zeroes([MAX_PARAMS][MAX_SUBPARAMS]u16),
            .n_main = 0,
            .n_sub = std.mem.zeroes([MAX_PARAMS]u2),
        };
        const s = self.param_buf[0..self.param_len];
        var p_idx: usize = 0; // current main param index
        var s_idx: usize = 0; // current sub-param index within p_idx
        var acc: u16 = 0;
        var has_digit = false;

        for (s) |b| {
            if (b >= '0' and b <= '9') {
                acc = acc *| 10 +| @as(u16, b - '0');
                has_digit = true;
            } else if (b == ';') {
                if (p_idx < MAX_PARAMS) {
                    if (s_idx < MAX_SUBPARAMS) {
                        out.vals[p_idx][s_idx] = if (has_digit) acc else 0;
                        if (s_idx + 1 > out.n_sub[p_idx]) out.n_sub[p_idx] = @intCast(s_idx + 1);
                    }
                    p_idx += 1;
                }
                s_idx = 0;
                acc = 0;
                has_digit = false;
            } else if (b == ':') {
                if (p_idx < MAX_PARAMS and s_idx < MAX_SUBPARAMS) {
                    out.vals[p_idx][s_idx] = if (has_digit) acc else 0;
                    if (s_idx + 1 > out.n_sub[p_idx]) out.n_sub[p_idx] = @intCast(s_idx + 1);
                    s_idx += 1;
                }
                acc = 0;
                has_digit = false;
            }
        }
        // flush last accumulator
        if (p_idx < MAX_PARAMS and s_idx < MAX_SUBPARAMS) {
            out.vals[p_idx][s_idx] = if (has_digit) acc else 0;
            if (has_digit or p_idx > 0 or s_idx > 0) {
                if (s_idx + 1 > out.n_sub[p_idx]) out.n_sub[p_idx] = @intCast(s_idx + 1);
            }
        }
        out.n_main = @intCast(@min(p_idx + (if (has_digit or s_idx > 0 or p_idx > 0) @as(usize, 1) else 0), MAX_PARAMS));
        return out;
    }

    fn dispatchCsi(self: *Parser, final: u8, alloc: std.mem.Allocator) !?Event {
        const p = self.parseCsiParams();

        // ESC[?N$p — mode report query (intermediate '$')
        if (self.inter_len == 1 and self.inter_buf[0] == '$' and final == 'y') {
            return Event{ .mode_report = .{
                .mode = p.main(0),
                .value = @intCast(p.main(1)),
            } };
        }

        // SGR mouse: CSI < btn;col;row M/m
        if (self.sgr_lt and (final == 'M' or final == 'm')) {
            return dispatchSgrMouse(&p, final);
        }

        return switch (final) {
            'A' => keyWithMod(.up, p.main(1)),
            'B' => keyWithMod(.down, p.main(1)),
            'C' => keyWithMod(.right, p.main(1)),
            'D' => keyWithMod(.left, p.main(1)),
            'E' => keyWithMod(.kp_begin, p.main(1)),
            'F' => keyWithMod(.end, p.main(1)),
            'H' => keyWithMod(.home, p.main(1)),
            'I' => Event{ .focus = .gained },
            'O' => Event{ .focus = .lost },
            'P' => keyWithMod(.{ .f = 1 }, p.main(1)),
            'Q' => keyWithMod(.{ .f = 2 }, p.main(1)),
            'R' => blk: {
                const row = if (p.n_main > 0 and p.main(0) > 0) p.main(0) else 1;
                const col = if (p.n_main > 1 and p.main(1) > 0) p.main(1) else 1;
                break :blk Event{ .cursor_pos = .{ .row = row, .col = col } };
            },
            'S' => keyWithMod(.{ .f = 4 }, p.main(1)),
            'Z' => Event{ .key = .{ .code = .backtab, .mods = .{ .shift = true } } },
            'c' => blk: {
                // Primary DA response
                var da: DaResponse = .{ .params = std.mem.zeroes([8]u16), .len = 0 };
                var i: u4 = 0;
                while (i < p.n_main and i < 8) : (i += 1) {
                    da.params[i] = p.main(i);
                    da.len = i + 1;
                }
                break :blk Event{ .da_response = da };
            },
            't' => blk: {
                // ESC[8;rows;cols t  — resize report
                if (p.main(0) == 8) {
                    break :blk Event{ .resize = .{ .rows = p.main(1), .cols = p.main(2) } };
                }
                break :blk try self.emitUnknownCsi(alloc, final);
            },
            'u' => self.dispatchKitty(&p),
            '~' => self.dispatchTilde(&p, alloc),
            else => try self.emitUnknownCsi(alloc, final),
        };
    }

    fn keyWithMod(code: KeyCode, mod_param: u16) ?Event {
        const mods = if (mod_param > 1)
            KeyMods.fromCsi(@intCast(@min(mod_param, 255)))
        else
            KeyMods{};
        return Event{ .key = .{ .code = code, .mods = mods } };
    }

    fn dispatchSgrMouse(p: *const CsiParams, final: u8) ?Event {
        const btn_raw: u8 = @intCast(@min(p.main(0), 255));
        const mods = KeyMods{
            .shift = (btn_raw & 4) != 0,
            .alt = (btn_raw & 8) != 0,
            .ctrl = (btn_raw & 16) != 0,
        };
        const motion = (btn_raw & 32) != 0;
        const button_bits: u8 = btn_raw & 0xC3;
        const button: MouseEvent.Button = switch (button_bits) {
            0 => .left,
            1 => .middle,
            2 => .right,
            64 => .wheel_up,
            65 => .wheel_down,
            66 => .wheel_left,
            67 => .wheel_right,
            128 => .btn8,
            129 => .btn9,
            130 => .btn10,
            131 => .btn11,
            else => .none,
        };
        const col: u16 = if (p.main(1) > 0) p.main(1) - 1 else 0;
        const row: u16 = if (p.main(2) > 0) p.main(2) - 1 else 0;
        const kind: MouseEvent.Kind = if (final == 'm')
            .release
        else if (motion)
            .motion
        else
            .press;
        return Event{ .mouse = .{
            .col = col,
            .row = row,
            .button = button,
            .mods = mods,
            .kind = kind,
        } };
    }

    fn dispatchKitty(self: *const Parser, p: *const CsiParams) ?Event {
        _ = self;
        const cp = p.main(0);
        const mod_param: u16 = if (p.n_main > 1) p.main(1) else 1;
        const mods = KeyMods.fromCsi(@intCast(@min(mod_param, 255)));

        // sub-param of mod slot encodes event type: 1=press,2=repeat,3=release
        const event_type_sub = p.sub(1, 0);
        const kind: KeyEvent.KeyKind = switch (event_type_sub) {
            2 => .repeat,
            3 => .release,
            else => .press,
        };

        const code: KeyCode = switch (cp) {
            57344 => .escape,
            57358 => .tab,
            57359 => .backspace,
            57361 => .insert,
            57362 => .delete,
            57363 => .left,
            57364 => .right,
            57365 => .up,
            57366 => .down,
            57367 => .page_up,
            57368 => .page_down,
            57369 => .home,
            57370 => .end,
            57376...57398 => |n| .{ .f = @intCast(n - 57376 + 1) },
            57399...57408 => |n| .{ .kp_char = @intCast('0' + n - 57399) },
            57414 => .kp_enter,
            57427 => .kp_begin,
            0x0D => .enter,
            0x09 => .tab,
            else => .{ .char = @intCast(@min(cp, 0x10FFFF)) },
        };

        return Event{ .key = .{ .code = code, .mods = mods, .kind = kind } };
    }

    fn dispatchTilde(self: *Parser, p: *const CsiParams, alloc: std.mem.Allocator) !?Event {
        const key_num = p.main(0);
        const mod_param = p.main(1);

        if (key_num == 200) {
            // bracketed paste begin
            self.state = .bracketed_paste;
            self.paste_buf.clearRetainingCapacity();
            return null;
        }
        if (key_num == 201) {
            // shouldn't arrive here (handled in paste state), but reset
            return null;
        }

        const code: KeyCode = switch (key_num) {
            1, 7 => .home,
            2 => .insert,
            3 => .delete,
            4, 8 => .end,
            5 => .page_up,
            6 => .page_down,
            11 => .{ .f = 1 },
            12 => .{ .f = 2 },
            13 => .{ .f = 3 },
            14 => .{ .f = 4 },
            15 => .{ .f = 5 },
            17 => .{ .f = 6 },
            18 => .{ .f = 7 },
            19 => .{ .f = 8 },
            20 => .{ .f = 9 },
            21 => .{ .f = 10 },
            23 => .{ .f = 11 },
            24 => .{ .f = 12 },
            25 => .{ .f = 13 },
            26 => .{ .f = 14 },
            28 => .{ .f = 15 },
            29 => .{ .f = 16 },
            31 => .{ .f = 17 },
            32 => .{ .f = 18 },
            33 => .{ .f = 19 },
            34 => .{ .f = 20 },
            57427 => .kp_begin,
            else => return try self.emitUnknownCsi(alloc, '~'),
        };

        return keyWithMod(code, mod_param);
    }

    fn emitUnknownCsi(self: *const Parser, alloc: std.mem.Allocator, final: u8) !?Event {
        // reconstruct ESC [ <params> <inter> <final>
        const total = 2 + self.param_len + self.inter_len + 1;
        const buf = try alloc.alloc(u8, total);
        buf[0] = 0x1B;
        buf[1] = '[';
        @memcpy(buf[2..][0..self.param_len], self.param_buf[0..self.param_len]);
        @memcpy(buf[2 + self.param_len ..][0..self.inter_len], self.inter_buf[0..self.inter_len]);
        buf[total - 1] = final;
        return Event{ .unknown = buf };
    }

    // -----------------------------------------------------------------------
    // OSC
    // -----------------------------------------------------------------------

    fn oscByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        if (byte == 0x07) {
            // BEL as ST terminator
            return self.dispatchOsc(alloc);
        }
        if (byte == 0x1B) {
            // potential ESC \ terminator — peek handled on next byte
            // We handle this by switching state temporarily. Simpler: check
            // if next call is '\' while in osc_string. Store ESC in osc_buf
            // and let next byte check for \\.
            if (self.osc_len < self.osc_buf.len) {
                self.osc_buf[self.osc_len] = byte;
                self.osc_len += 1;
            }
            return null;
        }
        // Check if previous byte was ESC (0x1B) and current is \
        if (byte == '\\' and self.osc_len > 0 and self.osc_buf[self.osc_len - 1] == 0x1B) {
            self.osc_len -= 1; // strip the ESC
            return self.dispatchOsc(alloc);
        }
        if (self.osc_len < self.osc_buf.len) {
            self.osc_buf[self.osc_len] = byte;
            self.osc_len += 1;
        }
        return null;
    }

    fn dispatchOsc(self: *Parser, alloc: std.mem.Allocator) !?Event {
        self.state = .ground;
        const s = self.osc_buf[0..self.osc_len];

        // parse leading OSC code (digits before ';')
        var code: u32 = 0;
        var i: usize = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            code = code * 10 + (s[i] - '0');
        }
        // skip ';'
        if (i < s.len and s[i] == ';') i += 1;
        const body = s[i..];

        return switch (code) {
            10, 11, 12 => parseColorReport(body, @intCast(code)),
            else => blk: {
                // emit raw OSC string as unknown
                const raw = try alloc.alloc(u8, self.osc_len + 4);
                raw[0] = 0x1B;
                raw[1] = ']';
                @memcpy(raw[2..][0..self.osc_len], self.osc_buf[0..self.osc_len]);
                raw[2 + self.osc_len] = 0x1B;
                raw[2 + self.osc_len + 1] = '\\';
                break :blk Event{ .unknown = raw };
            },
        };
    }

    // Parse "rgb:RRRR/GGGG/BBBB" from OSC 10/11/12 response body
    fn parseColorReport(body: []const u8, slot: u8) ?Event {
        const prefix = "rgb:";
        if (!std.mem.startsWith(u8, body, prefix)) return null;
        const s = body[prefix.len..];

        var parts: [3]u16 = .{ 0, 0, 0 };
        var pi: usize = 0;
        var j: usize = 0;
        while (pi < 3 and j < s.len) {
            var val: u16 = 0;
            var digits: usize = 0;
            while (j < s.len and s[j] != '/') : (j += 1) {
                const d = hexDigit(s[j]) orelse break;
                val = val *| 16 +| d;
                digits += 1;
            }
            if (digits == 0) return null;
            parts[pi] = val;
            pi += 1;
            if (j < s.len and s[j] == '/') j += 1;
        }
        if (pi < 3) return null;
        return Event{ .color_report = .{ .slot = slot, .r = parts[0], .g = parts[1], .b = parts[2] } };
    }

    fn hexDigit(b: u8) ?u16 {
        return switch (b) {
            '0'...'9' => b - '0',
            'a'...'f' => 10 + b - 'a',
            'A'...'F' => 10 + b - 'A',
            else => null,
        };
    }

    // -----------------------------------------------------------------------
    // DCS
    // -----------------------------------------------------------------------

    fn dcsByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        if (byte >= 0x40 and byte <= 0x7E and self.state != .dcs_passthrough) {
            // final byte of DCS intro — switch to passthrough
            self.state = .dcs_passthrough;
            return null;
        }
        if (byte >= 0x20 and byte <= 0x2F and self.state == .dcs_entry) {
            self.state = .dcs_inter;
            return null;
        }
        if (byte >= 0x30 and byte <= 0x3F and self.state == .dcs_entry) {
            self.state = .dcs_param;
            return null;
        }
        if (self.state == .dcs_passthrough) {
            if (byte == 0x1B) {
                // may be ESC \ — handled via osc-like look-ahead
                self.osc_buf[0] = byte;
                self.osc_len = 1;
                return null;
            }
            if (byte == '\\' and self.osc_len == 1 and self.osc_buf[0] == 0x1B) {
                // ST received; emit unknown for DCS passthrough
                self.state = .ground;
                self.osc_len = 0;
                return try self.emitUnknown(alloc, ""); // no meaningful content
            }
        }
        return null;
    }

    fn dcsIgnoreByte(self: *Parser, byte: u8) !?Event {
        if (byte == 0x9C or (byte == '\\' and self.osc_len > 0 and self.osc_buf[0] == 0x1B)) {
            self.state = .ground;
            self.osc_len = 0;
        } else if (byte == 0x1B) {
            self.osc_buf[0] = byte;
            self.osc_len = 1;
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // SOS / PM / APC — drain until ST
    // -----------------------------------------------------------------------

    fn sosByte(self: *Parser, byte: u8) !?Event {
        if (byte == 0x9C) {
            self.state = .ground;
        } else if (byte == 0x1B) {
            // store, next byte might be \
            self.osc_buf[0] = byte;
            self.osc_len = 1;
        } else if (byte == '\\' and self.osc_len > 0 and self.osc_buf[0] == 0x1B) {
            self.state = .ground;
            self.osc_len = 0;
        } else {
            self.osc_len = 0;
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // Bracketed paste
    // -----------------------------------------------------------------------

    fn pasteByte(self: *Parser, byte: u8, alloc: std.mem.Allocator) !?Event {
        // Accumulate every byte into paste_buf. When the tail equals the
        // bracketed-paste-end marker ESC[201~, strip it and emit PasteEvent.
        const MARKER_LEN = 6; // "\x1b[201~"
        const MARKER: [MARKER_LEN]u8 = .{ 0x1B, '[', '2', '0', '1', '~' };

        try self.paste_buf.append(alloc, byte);

        const items = self.paste_buf.items;
        if (items.len >= MARKER_LEN and
            std.mem.eql(u8, items[items.len - MARKER_LEN ..], &MARKER))
        {
            self.paste_buf.items.len -= MARKER_LEN;
            self.state = .ground;
            const text = try self.paste_buf.toOwnedSlice(alloc);
            self.paste_buf = .empty;
            return Event{ .paste = .{ .text = text } };
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // UTF-8 multi-byte accumulation
    // -----------------------------------------------------------------------

    fn beginUtf8(self: *Parser, total: u3, first_bits: u21) void {
        self.utf8_rem = total - 1;
        self.utf8_cp = first_bits;
        self.state = switch (total) {
            2 => .utf8_2,
            3 => .utf8_3,
            4 => .utf8_4,
            else => unreachable,
        };
        self.utf8_buf[0] = 0; // reset; we reconstruct from cp bits
    }

    fn utf8ContinueByte(self: *Parser, byte: u8) !?Event {
        if (byte & 0xC0 != 0x80) {
            // invalid continuation byte; emit replacement
            self.state = .ground;
            return Event{ .key = .{ .code = .{ .char = 0xFFFD } } };
        }
        self.utf8_cp = (self.utf8_cp << 6) | @as(u21, byte & 0x3F);
        self.utf8_rem -= 1;
        if (self.utf8_rem == 0) {
            self.state = .ground;
            const cp = self.utf8_cp;
            return Event{ .key = .{ .code = .{ .char = cp } } };
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    fn addInter(self: *Parser, byte: u8) void {
        if (self.inter_len < self.inter_buf.len) {
            self.inter_buf[self.inter_len] = byte;
            self.inter_len += 1;
        }
    }

    fn emitUnknown(self: *const Parser, alloc: std.mem.Allocator, s: []const u8) !?Event {
        _ = self;
        if (s.len == 0) return null;
        const buf = try alloc.alloc(u8, s.len);
        @memcpy(buf, s);
        return Event{ .unknown = buf };
    }
};

fn keyEvent(code: KeyCode, mods: KeyMods) ?Event {
    return Event{ .key = .{ .code = code, .mods = mods } };
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "ground: printable char A" {
    var p = Parser.init();
    const ev = try p.feed(0x41, std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 'A'), ev.?.key.code.char);
}

test "ground: ctrl+A (0x01)" {
    var p = Parser.init();
    const ev = try p.feed(0x01, std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 'a'), ev.?.key.code.char);
    try std.testing.expect(ev.?.key.mods.ctrl);
}

test "CSI A -> up arrow" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    const ev = try p.feed('A', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .up);
}

test "CSI 1;5A -> ctrl+up" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    _ = try p.feed('1', std.testing.allocator);
    _ = try p.feed(';', std.testing.allocator);
    _ = try p.feed('5', std.testing.allocator);
    const ev = try p.feed('A', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .up);
    try std.testing.expect(ev.?.key.mods.ctrl);
}

test "CSI 2~ -> insert" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    _ = try p.feed('2', std.testing.allocator);
    const ev = try p.feed('~', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .insert);
}

test "CSI 5~ -> page_up" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    _ = try p.feed('5', std.testing.allocator);
    const ev = try p.feed('~', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expect(ev.?.key.code == .page_up);
}

test "CSI 11~ -> F1" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    _ = try p.feed('1', std.testing.allocator);
    _ = try p.feed('1', std.testing.allocator);
    const ev = try p.feed('~', std.testing.allocator);
    try std.testing.expect(ev != null);
    switch (ev.?.key.code) {
        .f => |n| try std.testing.expectEqual(@as(u8, 1), n),
        else => return error.WrongCode,
    }
}

test "SGR mouse press ESC[<0;5;3M -> left press col=4 row=2" {
    var p = Parser.init();
    for ("\x1b[<0;5;3M") |b| {
        const ev = try p.feed(b, std.testing.allocator);
        if (ev) |e| {
            try std.testing.expect(std.meta.activeTag(e) == .mouse);
            try std.testing.expectEqual(MouseEvent.Button.left, e.mouse.button);
            try std.testing.expectEqual(@as(u16, 4), e.mouse.col);
            try std.testing.expectEqual(@as(u16, 2), e.mouse.row);
            try std.testing.expectEqual(MouseEvent.Kind.press, e.mouse.kind);
            return;
        }
    }
    return error.NoEvent;
}

test "focus gained ESC[I" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    const ev = try p.feed('I', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expectEqual(Event{ .focus = .gained }, ev.?);
}

test "focus lost ESC[O" {
    var p = Parser.init();
    _ = try p.feed(0x1B, std.testing.allocator);
    _ = try p.feed('[', std.testing.allocator);
    const ev = try p.feed('O', std.testing.allocator);
    try std.testing.expect(ev != null);
    try std.testing.expectEqual(Event{ .focus = .lost }, ev.?);
}

test "cursor pos ESC[6;20R" {
    var p = Parser.init();
    for ("\x1b[6;20R") |b| {
        const ev = try p.feed(b, std.testing.allocator);
        if (ev) |e| {
            try std.testing.expectEqual(CursorPos{ .row = 6, .col = 20 }, e.cursor_pos);
            return;
        }
    }
    return error.NoEvent;
}

test "resize ESC[8;40;120t" {
    var p = Parser.init();
    for ("\x1b[8;40;120t") |b| {
        const ev = try p.feed(b, std.testing.allocator);
        if (ev) |e| {
            try std.testing.expectEqual(ResizeEvent{ .rows = 40, .cols = 120 }, e.resize);
            return;
        }
    }
    return error.NoEvent;
}

test "mode report ESC[?2026;1$y" {
    var p = Parser.init();
    for ("\x1b[?2026;1$y") |b| {
        const ev = try p.feed(b, std.testing.allocator);
        if (ev) |e| {
            try std.testing.expectEqual(@as(u16, 2026), e.mode_report.mode);
            try std.testing.expectEqual(@as(u8, 1), e.mode_report.value);
            return;
        }
    }
    return error.NoEvent;
}

test "OSC color report ESC]11;rgb:0000/0000/ffff ST" {
    var p = Parser.init();
    const seq = "\x1b]11;rgb:0000/0000/ffff\x1b\\";
    for (seq) |b| {
        const ev = try p.feed(b, std.testing.allocator);
        if (ev) |e| {
            try std.testing.expect(std.meta.activeTag(e) == .color_report);
            try std.testing.expectEqual(@as(u8, 11), e.color_report.slot);
            try std.testing.expectEqual(@as(u16, 0), e.color_report.r);
            try std.testing.expectEqual(@as(u16, 0), e.color_report.g);
            try std.testing.expectEqual(@as(u16, 0xffff), e.color_report.b);
            return;
        }
    }
    return error.NoEvent;
}
