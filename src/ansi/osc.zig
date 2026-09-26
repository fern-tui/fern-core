// SPDX-License-Identifier: MIT

//! Operating System Command (OSC) sequence generators.
//!
//! Generates formatting instructions targeting host terminal window systems
//! (e.g., titles, clipboards, hyperlinks). All strings terminate safely with
//! `ESC\` to bypass problematic handling of `BEL`.

const std = @import("std");

const OSC_OPEN = "\x1b]";
const ST = "\x1b\\";

/// Emits sequence to update terminal window title format.
pub fn setTitle(w: anytype, title: []const u8) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("0;");
    try w.writeAll(title);
    try w.writeAll(ST);
}

/// Emits sequence to set the application icon text indicator.
pub fn setIconName(w: anytype, name: []const u8) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("1;");
    try w.writeAll(name);
    try w.writeAll(ST);
}

/// Begins a hyperlink block spanning output content.
pub fn hyperlinkStart(w: anytype, uri: []const u8, params: []const u8) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("8;");
    try w.writeAll(params);
    try w.writeAll(";");
    try w.writeAll(uri);
    try w.writeAll(ST);
}

/// Terminates an active hyperlink span block.
pub fn hyperlinkEnd(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("8;;");
    try w.writeAll(ST);
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Stack-based base64 encoder. Writes in chunks (3 bytes in, 4 chars out).
fn writeBase64(w: anytype, data: []const u8) !void {
    var i: usize = 0;
    while (i + 3 <= data.len) : (i += 3) {
        const a = data[i];
        const b = data[i + 1];
        const c = data[i + 2];
        const out: [4]u8 = .{
            B64[a >> 2],
            B64[((a & 3) << 4) | (b >> 4)],
            B64[((b & 0xF) << 2) | (c >> 6)],
            B64[c & 0x3F],
        };
        try w.writeAll(&out);
    }
    const rem = data.len - i;
    if (rem == 1) {
        const a = data[i];
        const out: [4]u8 = .{
            B64[a >> 2],
            B64[(a & 3) << 4],
            '=',
            '=',
        };
        try w.writeAll(&out);
    } else if (rem == 2) {
        const a = data[i];
        const b = data[i + 1];
        const out: [4]u8 = .{
            B64[a >> 2],
            B64[((a & 3) << 4) | (b >> 4)],
            B64[(b & 0xF) << 2],
            '=',
        };
        try w.writeAll(&out);
    }
}

/// Executes OSC 52 host clipboard write integration.
///
/// Converts raw data to base64 internally without allocating.
///
/// Parameters:
///   - w: Output writer.
///   - target: Clipboard target identifier (usually "c" or "p").
///   - data: Plaintext payload to encode and copy.
pub fn setClipboard(w: anytype, target: []const u8, data: []const u8) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("52;");
    try w.writeAll(target);
    try w.writeAll(";");
    try writeBase64(w, data);
    try w.writeAll(ST);
}

/// Initiates host clipboard content request via OSC 52.
pub fn requestClipboard(w: anytype, target: []const u8) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("52;");
    try w.writeAll(target);
    try w.writeAll(";?");
    try w.writeAll(ST);
}

// Inline 4-digit hex for 16-bit color components
fn writeHex16(w: anytype, v: u16) !void {
    const hex = "0123456789ABCDEF";
    const out: [4]u8 = .{
        hex[(v >> 12) & 0xF],
        hex[(v >> 8) & 0xF],
        hex[(v >> 4) & 0xF],
        hex[(v >> 0) & 0xF],
    };
    try w.writeAll(&out);
}

fn writeOscColor(w: anytype, code: []const u8, r: u16, g: u16, b: u16) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll(code);
    try w.writeAll(";rgb:");
    try writeHex16(w, r);
    try w.writeAll("/");
    try writeHex16(w, g);
    try w.writeAll("/");
    try writeHex16(w, b);
    try w.writeAll(ST);
}

/// Issues command overwriting primary window foreground color.
pub fn setFgColor(w: anytype, r: u16, g: u16, b: u16) !void {
    try writeOscColor(w, "10", r, g, b);
}

/// Issues command overwriting primary window background color.
pub fn setBgColor(w: anytype, r: u16, g: u16, b: u16) !void {
    try writeOscColor(w, "11", r, g, b);
}

/// Issues command overwriting terminal cursor color element.
pub fn setCursorColor(w: anytype, r: u16, g: u16, b: u16) !void {
    try writeOscColor(w, "12", r, g, b);
}

/// Transmits foreground color query block.
pub fn queryFgColor(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("10;?");
    try w.writeAll(ST);
}

/// Transmits background color query block.
pub fn queryBgColor(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("11;?");
    try w.writeAll(ST);
}

/// Orders terminal to revert foreground properties back to profile defaults.
pub fn resetFgColor(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("110;");
    try w.writeAll(ST);
}

/// Orders terminal to revert background properties back to profile defaults.
pub fn resetBgColor(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("111;");
    try w.writeAll(ST);
}

/// Orders terminal to revert cursor color properties back to profile defaults.
pub fn resetCursorColor(w: anytype) !void {
    try w.writeAll(OSC_OPEN);
    try w.writeAll("112;");
    try w.writeAll(ST);
}

/// Dispatches asynchronous local desktop notification blocks.
///
/// Simultaneously dispatches fallback payload structures to support both
/// Windows Terminal/PowerShell native formatting alongside legacy libnotify configurations.
pub fn notify(w: anytype, title: []const u8, body: []const u8) !void {
    // Windows Terminal / PowerShell format
    try w.writeAll(OSC_OPEN);
    try w.writeAll("9;9;");
    try w.writeAll(title);
    try w.writeAll("\n");
    try w.writeAll(body);
    try w.writeAll(ST);
    // libnotify / urxvt format
    try w.writeAll(OSC_OPEN);
    try w.writeAll("777;notify;");
    try w.writeAll(title);
    try w.writeAll(";");
    try w.writeAll(body);
    try w.writeAll(ST);
}

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

test "setTitle produces correct OSC 0 sequence" {
    var w: BufW(64) = .{};
    try setTitle(&w, "fern");
    try std.testing.expectEqualStrings("\x1b]0;fern\x1b\\", w.written());
}

test "queryBgColor produces ESC]11;?ST" {
    var w: BufW(16) = .{};
    try queryBgColor(&w);
    try std.testing.expectEqualStrings("\x1b]11;?\x1b\\", w.written());
}

test "base64 encoder single byte" {
    var w: BufW(8) = .{};
    try writeBase64(&w, "f");
    try std.testing.expectEqualStrings("Zg==", w.written());
}

test "base64 encoder three bytes" {
    var w: BufW(8) = .{};
    try writeBase64(&w, "foo");
    try std.testing.expectEqualStrings("Zm9v", w.written());
}
