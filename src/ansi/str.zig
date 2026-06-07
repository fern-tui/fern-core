// SPDX-License-Identifier: MIT

// str.zig - string utilities: ANSI-aware measure, truncate, pad, wrap
//
// Deps: width.zig

const std = @import("std");
const width = @import("width.zig");

pub const strWidth = width.strWidth;
pub const rawWidth = width.rawWidth;

// Allocate a copy of s with all ANSI escape sequences stripped.
pub fn stripAnsi(s: []const u8, alloc: std.mem.Allocator) ![]u8 {
    // worst case: no escapes, output == input length
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    var i: usize = 0;
    while (i < s.len) {
        const b = s[i];
        if (b == 0x1B and i + 1 < s.len) {
            const next = s[i + 1];
            i += 2;
            if (next == '[') {
                while (i < s.len and (s[i] < 0x40 or s[i] > 0x7E)) : (i += 1) {}
                if (i < s.len) i += 1;
            } else if (next == ']' or next == 'P' or next == '_') {
                while (i < s.len) {
                    if (s[i] == 0x07) {
                        i += 1;
                        break;
                    }
                    if (s[i] == 0x1B and i + 1 < s.len and s[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            }
            continue;
        }
        try out.append(alloc, b);
        i += 1;
    }
    return out.toOwnedSlice(alloc);
}

// Advance i past one complete escape sequence starting at i (must be 0x1B).
// Returns new i.
fn skipEscape(s: []const u8, start: usize) usize {
    var i = start;
    if (i >= s.len or s[i] != 0x1B) return i;
    i += 1;
    if (i >= s.len) return i;
    const next = s[i];
    i += 1;
    if (next == '[') {
        while (i < s.len and (s[i] < 0x40 or s[i] > 0x7E)) : (i += 1) {}
        if (i < s.len) i += 1;
    } else if (next == ']' or next == 'P' or next == '_') {
        while (i < s.len) {
            if (s[i] == 0x07) {
                i += 1;
                break;
            }
            if (s[i] == 0x1B and i + 1 < s.len and s[i + 1] == '\\') {
                i += 2;
                break;
            }
            i += 1;
        }
    }
    return i;
}

// Truncate s to at most max_width visible cells.
// Returns a slice of s when no truncation needed (no alloc).
// Allocates only when truncation is needed (may insert trailing space for
// split wide char).
pub fn truncate(s: []const u8, max_width: usize, alloc: std.mem.Allocator) ![]u8 {
    var visible: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1B) {
            const j = skipEscape(s, i);
            i = j;
            continue;
        }
        if (s[i] < 0x20 or s[i] == 0x7F) {
            i += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > s.len) break;
        const cp = std.unicode.utf8Decode(s[i .. i + seq_len]) catch 0xFFFD;
        const cw = width.cpWidth(cp);
        if (visible + cw > max_width) {
            // wide char would overflow: pad with space instead
            var out = try alloc.alloc(u8, i + 1);
            @memcpy(out[0..i], s[0..i]);
            if (cw == 2 and visible + 1 <= max_width) {
                out[i] = ' ';
            } else {
                out = try alloc.realloc(out, i);
            }
            return out;
        }
        visible += cw;
        i += seq_len;
    }
    // no truncation needed; return a heap copy for consistent ownership
    const out = try alloc.alloc(u8, i);
    @memcpy(out, s[0..i]);
    return out;
}

// Pad s on the right to exactly target_width visible cells.
// Truncates if wider. Allocates only when pad/truncate is needed.
pub fn pad(s: []const u8, target_width: usize, alloc: std.mem.Allocator) ![]u8 {
    const w = width.strWidth(s);
    if (w == target_width) {
        const out = try alloc.alloc(u8, s.len);
        @memcpy(out, s);
        return out;
    }
    if (w > target_width) {
        return truncate(s, target_width, alloc);
    }
    const pad_count = target_width - w;
    const out = try alloc.alloc(u8, s.len + pad_count);
    @memcpy(out[0..s.len], s);
    @memset(out[s.len..], ' ');
    return out;
}

// Left-pad s with spaces to reach exactly target_width visible cells.
pub fn padLeft(s: []const u8, target_width: usize, alloc: std.mem.Allocator) ![]u8 {
    const w = width.strWidth(s);
    if (w >= target_width) {
        const out = try alloc.alloc(u8, s.len);
        @memcpy(out, s);
        return out;
    }
    const pad_count = target_width - w;
    const out = try alloc.alloc(u8, pad_count + s.len);
    @memset(out[0..pad_count], ' ');
    @memcpy(out[pad_count..], s);
    return out;
}

// Split s on '\n'. Returned slices reference s bytes (no copy).
pub fn splitLines(s: []const u8, alloc: std.mem.Allocator) ![][]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(alloc);

    var start: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n') {
            try lines.append(alloc, s[start..i]);
            start = i + 1;
        }
    }
    try lines.append(alloc, s[start..]);
    return lines.toOwnedSlice(alloc);
}

pub fn lineCount(s: []const u8) usize {
    var count: usize = 1;
    for (s) |b| {
        if (b == '\n') count += 1;
    }
    return count;
}

pub fn maxLineWidth(s: []const u8) usize {
    var max: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= s.len) : (i += 1) {
        if (i == s.len or s[i] == '\n') {
            const lw = width.strWidth(s[start..i]);
            if (lw > max) max = lw;
            start = i + 1;
        }
    }
    return max;
}

// Wrap s to max_width cells. Breaks at spaces; force-breaks long words.
// Returns newline-joined string (allocates).
pub fn wrap(s: []const u8, max_width: usize, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    // Process line by line (respect existing breaks)
    var line_start: usize = 0;
    while (line_start <= s.len) {
        // find end of current input line
        var line_end = line_start;
        while (line_end < s.len and s[line_end] != '\n') : (line_end += 1) {}

        const input_line = s[line_start..line_end];
        try wrapLine(input_line, max_width, &out, alloc);

        if (line_end < s.len) {
            try out.append(alloc, '\n');
            line_start = line_end + 1;
        } else {
            break;
        }
    }

    return out.toOwnedSlice(alloc);
}

fn wrapLine(
    s: []const u8,
    max_width: usize,
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
) !void {
    var col: usize = 0; // current column
    var i: usize = 0;
    var word_start: usize = 0;

    while (i <= s.len) {
        const at_end = (i == s.len);
        const at_space = (!at_end and s[i] == ' ');

        if (at_end or at_space) {
            // flush word s[word_start..i]
            const word_slice = s[word_start..i];
            const word_w = width.strWidth(word_slice);

            if (col > 0 and col + (if (col > 0) @as(usize, 1) else 0) + word_w > max_width) {
                // word doesn't fit on current line; emit newline
                try out.append(alloc, '\n');
                col = 0;
            }
            if (col > 0 and word_w > 0) {
                try out.append(alloc, ' ');
                col += 1;
            }

            // word itself may be wider than max_width: force-break it
            var wi: usize = 0;
            while (wi < word_slice.len) {
                const b = word_slice[wi];
                const seq_len = std.unicode.utf8ByteSequenceLength(b) catch {
                    wi += 1;
                    continue;
                };
                if (wi + seq_len > word_slice.len) break;
                const cp = std.unicode.utf8Decode(word_slice[wi .. wi + seq_len]) catch 0xFFFD;
                const cw = width.cpWidth(cp);
                if (col + cw > max_width and col > 0) {
                    try out.append(alloc, '\n');
                    col = 0;
                }
                try out.appendSlice(alloc, word_slice[wi .. wi + seq_len]);
                col += cw;
                wi += seq_len;
            }

            if (at_space) {
                // skip the space; we re-insert it above on next word
                i += 1;
                word_start = i;
            } else {
                break;
            }
        } else {
            i += 1;
        }
    }
}

// Expand tabs to spaces at tab_width intervals.
pub fn expandTabs(s: []const u8, tab_width: u8, alloc: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    var col: usize = 0;
    for (s) |b| {
        if (b == '\t') {
            const spaces = tab_width - @as(u8, @intCast(col % tab_width));
            var k: u8 = 0;
            while (k < spaces) : (k += 1) {
                try out.append(alloc, ' ');
            }
            col += spaces;
        } else if (b == '\n') {
            try out.append(alloc, '\n');
            col = 0;
        } else {
            try out.append(alloc, b);
            col += 1;
        }
    }
    return out.toOwnedSlice(alloc);
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "stripAnsi removes CSI sequences" {
    const alloc = std.testing.allocator;
    const got = try stripAnsi("\x1b[1mhello\x1b[0m", alloc);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("hello", got);
}

test "pad right-pads with spaces" {
    const alloc = std.testing.allocator;
    const got = try pad("hi", 5, alloc);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("hi   ", got);
}

test "padLeft left-pads with spaces" {
    const alloc = std.testing.allocator;
    const got = try padLeft("hi", 5, alloc);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("   hi", got);
}

test "splitLines basic" {
    const alloc = std.testing.allocator;
    const got = try splitLines("a\nb\nc", alloc);
    defer alloc.free(got);
    try std.testing.expectEqual(@as(usize, 3), got.len);
    try std.testing.expectEqualStrings("a", got[0]);
    try std.testing.expectEqualStrings("b", got[1]);
    try std.testing.expectEqualStrings("c", got[2]);
}

test "lineCount" {
    try std.testing.expectEqual(@as(usize, 3), lineCount("a\nb\nc"));
    try std.testing.expectEqual(@as(usize, 1), lineCount("hello"));
}

test "expandTabs at tab stop" {
    const alloc = std.testing.allocator;
    const got = try expandTabs("a\tb", 4, alloc);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("a   b", got);
}
