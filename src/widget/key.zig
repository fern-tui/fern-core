// SPDX-License-Identifier: MIT

// Global keybindings for all fern widgets.
// A Binding just glues a set of expected KeyCodes to some optional help text.
// To check for a hit, just throw a live KeyEvent at `matches()` to see if
// it triggers.
const std = @import("std");
const ansi = @import("fern_ansi");

/// A set of key codes that trigger the same action, plus display help text.
pub const Binding = struct {
    /// Human-readable display name (e.g. "↑/k").
    key_display: []const u8 = "",
    /// Short description of the action (e.g. "move up").
    desc: []const u8 = "",
    /// Whether this binding is currently active.
    enabled: bool = true,
    /// The set of key codes that match this binding.
    codes: []const ansi.KeyCode = &.{},
    /// Optional required modifiers (all must be present).
    mods: ansi.KeyMods = .{},
};

/// Returns true if ev matches any code in b and all required mods are present.
pub fn matches(ev: ansi.KeyEvent, b: Binding) bool {
    if (!b.enabled) return false;
    // Check mods: every required mod bit must be set in the event.
    const req: u8 = @bitCast(b.mods);
    const got: u8 = @bitCast(ev.mods);
    if ((got & req) != req) return false;
    for (b.codes) |code| {
        if (keyCodeEql(ev.code, code)) return true;
    }
    return false;
}

fn keyCodeEql(a: ansi.KeyCode, b: ansi.KeyCode) bool {
    return switch (a) {
        .char => |c| switch (b) {
            .char => |d| c == d,
            else => false,
        },
        .f => |n| switch (b) {
            .f => |m| n == m,
            else => false,
        },
        .kp_char => |c| switch (b) {
            .kp_char => |d| c == d,
            else => false,
        },
        else => std.meta.activeTag(a) == std.meta.activeTag(b),
    };
}

pub fn isQuit(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .escape => true,
        .char => |c| c == 'q' or (c == 'c' and ev.mods.ctrl),
        else => false,
    };
}

//directional helpers
pub fn isUp(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .up => true,
        .char => |c| c == 'k',
        else => false,
    };
}
pub fn isDown(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .down => true,
        .char => |c| c == 'j',
        else => false,
    };
}
pub fn isLeft(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .left => true,
        .char => |c| c == 'h',
        else => false,
    };
}
pub fn isRight(ev: ansi.KeyEvent) bool {
    return switch (ev.code) {
        .right => true,
        .char => |c| c == 'l',
        else => false,
    };
}

// Helpers to build Bindings concisely

/// Build a Binding from a slice of KeyCode values.
pub fn bind(codes: []const ansi.KeyCode) Binding {
    return .{ .codes = codes };
}

/// Build a Binding with display text.
pub fn bindHelp(
    codes: []const ansi.KeyCode,
    key_display: []const u8,
    desc: []const u8,
) Binding {
    return .{ .codes = codes, .key_display = key_display, .desc = desc };
}

test "matches returns true for matching char code" {
    const b = Binding{ .codes = &.{ .{ .char = 'j' }, .down } };
    const ev = ansi.KeyEvent{ .code = .{ .char = 'j' }, .mods = .{} };
    try std.testing.expect(matches(ev, b));
}

test "matches returns false for disabled binding" {
    const b = Binding{ .codes = &.{.down}, .enabled = false };
    const ev = ansi.KeyEvent{ .code = .down, .mods = .{} };
    try std.testing.expect(!matches(ev, b));
}

test "matches returns false when required mod is absent" {
    const b = Binding{ .codes = &.{.{ .char = 'u' }}, .mods = .{ .ctrl = true } };
    const ev = ansi.KeyEvent{ .code = .{ .char = 'u' }, .mods = .{} };
    try std.testing.expect(!matches(ev, b));
}

test "matches returns true when required mod is present" {
    const b = Binding{ .codes = &.{.{ .char = 'u' }}, .mods = .{ .ctrl = true } };
    const ev = ansi.KeyEvent{ .code = .{ .char = 'u' }, .mods = .{ .ctrl = true } };
    try std.testing.expect(matches(ev, b));
}
