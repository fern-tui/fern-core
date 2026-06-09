// SPDX-License-Identifier: MIT

// Single-threaded contract: all public methods from one thread.
// enabled is atomic so it can be toggled from outside the event loop.

const std = @import("std");
const ansi = @import("fern_ansi");
const info = @import("info.zig");
const ZoneInfo = info.ZoneInfo;

const MARKER_ESC: u8 = 0x1B;
const MARKER_CSI: u8 = 0x5B;
const MARKER_END: u8 = 0x7A; // 'z': private-use CSI final byte

// 5-digit minimum to avoid collision with real CSI sequences like ESC[25z.
const COUNTER_START: u32 = 10000;

const PREFIX_START: u32 = 0;

pub const Manager = struct {
    // ids is source of truth; rids and zones both point into its keys.
    ids: std.StringHashMap(u32),
    // marker number -> user ID; values point into ids keys
    rids: std.AutoHashMap(u32, []const u8),
    // user ID -> last scanned ZoneInfo; keys point into ids
    zones: std.StringHashMap(ZoneInfo),
    counter: std.atomic.Value(u32),
    prefix_counter: std.atomic.Value(u32),
    // atomic so it can be toggled outside the event loop
    enabled: std.atomic.Value(bool),
    // stored because the maps outlive individual frames
    alloc: std.mem.Allocator,

    // enabled defaults to true.
    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{
            .ids = std.StringHashMap(u32).init(allocator),
            .rids = std.AutoHashMap(u32, []const u8).init(allocator),
            .zones = std.StringHashMap(ZoneInfo).init(allocator),
            .counter = std.atomic.Value(u32).init(COUNTER_START),
            .prefix_counter = std.atomic.Value(u32).init(PREFIX_START),
            .enabled = std.atomic.Value(bool).init(true),
            .alloc = allocator,
        };
    }

    // After deinit the Manager must not be used.
    pub fn deinit(self: *Manager) void {
        // Keys were duped by getOrCreateMarker; free each one.
        var key_it = self.ids.iterator();
        while (key_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
        }
        self.ids.deinit();
        self.rids.deinit();
        self.zones.deinit();
    }

    pub fn setEnabled(self: *Manager, on: bool) void {
        self.enabled.store(on, .seq_cst);
    }

    pub fn isEnabled(self: *const Manager) bool {
        return self.enabled.load(.seq_cst);
    }

    // Writes a unique prefix into buf (caller owns, at least 24 bytes). Returns a slice into buf.
    // Call during component init and prepend to all zone IDs; without this two instances of the
    // same component share marker numbers and take turns going invisible.
    pub fn newPrefix(self: *Manager, buf: *[24]u8) []u8 {
        const n = self.prefix_counter.fetchAdd(1, .seq_cst);
        // "zone_" + 10-digit max + "__" = 18 chars < 24; bufPrint cannot fail.
        return std.fmt.bufPrint(buf, "zone_{d}__", .{n}) catch unreachable;
    }

    // Wraps content with zone markers. Returns a dupe unchanged when disabled, id is empty,
    // or content is empty. Caller frees with allocator.free().
    // Same id always gets the same marker number within one Manager instance.
    pub fn mark(
        self: *Manager,
        allocator: std.mem.Allocator,
        id: []const u8,
        content: []const u8,
    ) error{OutOfMemory}![]u8 {
        if (!self.isEnabled() or id.len == 0 or content.len == 0) {
            return allocator.dupe(u8, content);
        }
        const marker_num = try self.getOrCreateMarker(id);
        return buildMarked(allocator, marker_num, content);
    }

    // Strips zone markers, records component bounds. Returns clean frame (caller frees).
    // Call after assembling the full view string, before diffing.
    pub fn scan(
        self: *Manager,
        allocator: std.mem.Allocator,
        frame: []const u8,
    ) error{OutOfMemory}![]u8 {
        self.zones.clearRetainingCapacity();
        return runScanner(self, allocator, frame);
    }

    // Returns null if the id has not been scanned yet.
    pub fn get(self: *const Manager, id: []const u8) ?ZoneInfo {
        return self.zones.get(id);
    }

    pub fn clear(self: *Manager, id: []const u8) void {
        _ = self.zones.remove(id);
    }

    // Does not remove ID-to-marker mappings.
    pub fn clearAll(self: *Manager) void {
        self.zones.clearRetainingCapacity();
    }

    // Counter increments before map puts so a failed put doesn't waste a number visible to callers.
    fn getOrCreateMarker(self: *Manager, id: []const u8) error{OutOfMemory}!u32 {
        if (self.ids.get(id)) |n| return n;

        const n = self.counter.fetchAdd(1, .seq_cst);
        const duped = try self.alloc.dupe(u8, id);
        errdefer self.alloc.free(duped);

        try self.ids.put(duped, n);
        errdefer _ = self.ids.remove(duped);

        try self.rids.put(n, duped);

        return n;
    }
};

// Builds ESC[<n>z + content + ESC[<n>z. Caller frees with allocator.free().
fn buildMarked(
    allocator: std.mem.Allocator,
    marker_num: u32,
    content: []const u8,
) error{OutOfMemory}![]u8 {
    var marker_buf: [16]u8 = undefined;
    // "ESC[" + 10-digit max u32 + "z" = 14 bytes; 16 is always enough.
    const marker = std.fmt.bufPrint(&marker_buf, "\x1B[{d}z", .{marker_num}) catch unreachable;

    const total = marker.len + content.len + marker.len;
    const out = try allocator.alloc(u8, total);

    var pos: usize = 0;
    @memcpy(out[pos..][0..marker.len], marker);
    pos += marker.len;
    @memcpy(out[pos..][0..content.len], content);
    pos += content.len;
    @memcpy(out[pos..][0..marker.len], marker);

    return out;
}

// Walks frame byte by byte: strips zone markers, records bounds, returns clean output.
// pending is ephemeral (caller's allocator, lives one scan call).
// manager.ids/rids/zones use manager.alloc because they outlive frames.
fn runScanner(
    manager: *Manager,
    allocator: std.mem.Allocator,
    frame: []const u8,
) error{OutOfMemory}![]u8 {

    // Records the opening position of a marker not yet closed.
    const PendingZone = struct {
        start_x: u16,
        start_y: u16,
    };

    var output: std.ArrayList(u8) = .empty;
    var pending: std.AutoHashMap(u32, PendingZone) =
        std.AutoHashMap(u32, PendingZone).init(allocator);

    defer output.deinit(allocator);
    defer pending.deinit();

    // cur_x: printable cell columns from start of current line.
    // cur_y: newlines seen so far (= current row index).
    var cur_x: u16 = 0;
    var cur_y: u16 = 0;
    var i: usize = 0;

    while (i < frame.len) {
        if (frame[i] == '\n') {
            try output.append(allocator, '\n');
            cur_y +|= 1;
            cur_x = 0;
            i += 1;
            continue;
        }

        if (frame[i] == MARKER_ESC and
            i + 1 < frame.len and
            frame[i + 1] == MARKER_CSI)
        {
            // Try a zone marker first: ESC [ <digits >= COUNTER_START> z
            if (tryParseMarker(frame, i)) |result| {
                const marker_num = result.num;
                const seq_len = result.len;

                // When disabled, markers are stripped but positions not stored.
                if (manager.isEnabled()) {
                    if (manager.rids.get(marker_num)) |user_id| {
                        if (pending.get(marker_num)) |pz| {
                            // Closing marker: record bounds.
                            // end_x is cur_x - 1; marker takes no cells.
                            const end_x: u16 = if (cur_x > 0) cur_x - 1 else 0;
                            try manager.zones.put(user_id, ZoneInfo{
                                .start_x = pz.start_x,
                                .start_y = pz.start_y,
                                .end_x = end_x,
                                .end_y = cur_y,
                            });
                            _ = pending.remove(marker_num);
                        } else {
                            // Opening marker: remember position.
                            try pending.put(marker_num, PendingZone{
                                .start_x = cur_x,
                                .start_y = cur_y,
                            });
                        }
                    }
                }
                // Either way: the marker bytes are stripped from output.
                i += seq_len;
                continue;
            }

            // Real ANSI CSI sequence: copy verbatim, don't advance cur_x.
            const seq_len = consumeAnsiSeq(frame, i);
            try output.appendSlice(allocator, frame[i .. i + seq_len]);
            i += seq_len;
            continue;
        }

        const byte_len = std.unicode.utf8ByteSequenceLength(frame[i]) catch 1;
        const cp_end = @min(i + byte_len, frame.len);
        const cp_bytes = frame[i..cp_end];
        try output.appendSlice(allocator, cp_bytes);
        const cp = std.unicode.utf8Decode(cp_bytes) catch 0xFFFD;
        cur_x +|= @as(u16, @intCast(ansi.cpWidth(cp)));
        i = cp_end;
    }

    return output.toOwnedSlice(allocator);
}

// Tries to parse a zone marker at frame[pos]. Returns null if not a valid marker.
// A valid marker is ESC '[' digits 'z' where digits >= COUNTER_START.
// The COUNTER_START guard is load-bearing: real CSI sequences can end in 'z'
// (e.g. ESC[25z for DEC mode queries); anything below the threshold is left alone.
fn tryParseMarker(
    frame: []const u8,
    pos: usize,
) ?struct { num: u32, len: usize } {
    // pos -> ESC, pos+1 -> '[', digits start at pos+2.
    var j = pos + 2;
    if (j >= frame.len or frame[j] < '0' or frame[j] > '9') return null;

    while (j < frame.len and frame[j] >= '0' and frame[j] <= '9') : (j += 1) {}

    if (j >= frame.len or frame[j] != MARKER_END) return null;

    const num_str = frame[pos + 2 .. j];
    const num = std.fmt.parseInt(u32, num_str, 10) catch return null;

    if (num < COUNTER_START) return null;

    return .{ .num = num, .len = j + 1 - pos };
}

// Returns byte length of the ANSI CSI sequence at frame[pos].
// pos must point to ESC. Returns 1 for malformed or truncated sequences.
fn consumeAnsiSeq(frame: []const u8, pos: usize) usize {
    if (pos + 1 >= frame.len) return 1;

    // Non-CSI: ESC followed by something other than '[' is a 2-byte sequence.
    if (frame[pos + 1] != MARKER_CSI) return 2;

    // Consume parameter and intermediate bytes until a final byte (0x40-0x7E).
    var j = pos + 2;
    while (j < frame.len) : (j += 1) {
        const b = frame[j];
        if (b >= 0x40 and b <= 0x7E) return j + 1 - pos;
    }

    // Truncated sequence: consume what remains and move on.
    return frame.len - pos;
}

const testing = std.testing;

test "Manager init starts with zero zones" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    try testing.expect(m.get("x") == null);
}

test "Manager mark returns content unchanged when id is empty" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const result = try m.mark(testing.allocator, "", "hello");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("hello", result);
}

test "Manager mark returns content unchanged when content is empty" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const result = try m.mark(testing.allocator, "btn", "");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("", result);
}

test "Manager mark wraps content with ESC bracket digits z delimiters" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const result = try m.mark(testing.allocator, "btn", "hello");
    defer testing.allocator.free(result);
    // Must start with ESC then '[' and end with 'z', and contain "hello".
    try testing.expect(result.len > 0);
    try testing.expectEqual(@as(u8, 0x1B), result[0]);
    try testing.expectEqual(@as(u8, '['), result[1]);
    try testing.expectEqual(@as(u8, 'z'), result[result.len - 1]);
    try testing.expect(std.mem.indexOf(u8, result, "hello") != null);
}

test "Manager mark returns identical delimiter for same id on second call" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const r1 = try m.mark(testing.allocator, "btn", "a");
    defer testing.allocator.free(r1);
    const r2 = try m.mark(testing.allocator, "btn", "b");
    defer testing.allocator.free(r2);
    // Opening marker is 8 bytes: ESC [ 5-digit-num z
    try testing.expectEqualStrings(r1[0..8], r2[0..8]);
}

test "Manager mark returns different delimiter for different ids" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const r1 = try m.mark(testing.allocator, "btn1", "a");
    defer testing.allocator.free(r1);
    const r2 = try m.mark(testing.allocator, "btn2", "b");
    defer testing.allocator.free(r2);
    try testing.expect(!std.mem.eql(u8, r1[0..8], r2[0..8]));
}

test "Manager mark returns content unchanged when disabled" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    m.setEnabled(false);
    const result = try m.mark(testing.allocator, "btn", "hello");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("hello", result);
}

test "Manager scan strips markers and returns clean string" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    const marked = try m.mark(testing.allocator, "a", "hi");
    defer testing.allocator.free(marked);
    const clean = try m.scan(testing.allocator, marked);
    defer testing.allocator.free(clean);
    try testing.expectEqualStrings("hi", clean);
}

test "Manager scan records zone with correct start coordinates" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_part = try m.mark(testing.allocator, "btn", "yy");
    defer testing.allocator.free(marked_part);

    const frame = try std.mem.concat(testing.allocator, u8, &.{ "xxx", marked_part });
    defer testing.allocator.free(frame);

    const clean = try m.scan(testing.allocator, frame);
    defer testing.allocator.free(clean);

    const z = m.get("btn");
    try testing.expect(z != null);
    try testing.expectEqual(@as(u16, 3), z.?.start_x);
    try testing.expectEqual(@as(u16, 0), z.?.start_y);
}

test "Manager scan records zone start_y on second line" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_part = try m.mark(testing.allocator, "btn", "yy");
    defer testing.allocator.free(marked_part);

    const frame = try std.mem.concat(testing.allocator, u8, &.{ "first\n", marked_part });
    defer testing.allocator.free(frame);

    const clean = try m.scan(testing.allocator, frame);
    defer testing.allocator.free(clean);

    const z = m.get("btn");
    try testing.expect(z != null);
    try testing.expectEqual(@as(u16, 1), z.?.start_y);
    try testing.expectEqual(@as(u16, 0), z.?.start_x);
}

test "Manager scan records correct end_x" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_part = try m.mark(testing.allocator, "btn", "ab");
    defer testing.allocator.free(marked_part);

    const clean = try m.scan(testing.allocator, marked_part);
    defer testing.allocator.free(clean);

    const z = m.get("btn");
    try testing.expect(z != null);
    try testing.expectEqual(@as(u16, 0), z.?.start_x);
    // "ab" is 2 printable cells; end_x = cur_x(2) - 1 = 1.
    try testing.expectEqual(@as(u16, 1), z.?.end_x);
}

test "Manager scan strips markers from disabled manager" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    // Mark while enabled so the marker bytes actually exist in the string.
    const marked_part = try m.mark(testing.allocator, "btn", "hi");
    defer testing.allocator.free(marked_part);

    m.setEnabled(false);
    const clean = try m.scan(testing.allocator, marked_part);
    defer testing.allocator.free(clean);

    // Even when disabled, scan still strips any markers already in the frame.
    try testing.expectEqualStrings("hi", clean);
    // Disabled: zones not recorded.
    try testing.expect(m.get("btn") == null);
}

test "Manager scan clears previous zones before recording new ones" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_a = try m.mark(testing.allocator, "a", "x");
    defer testing.allocator.free(marked_a);

    const clean_a = try m.scan(testing.allocator, marked_a);
    defer testing.allocator.free(clean_a);
    try testing.expect(m.get("a") != null);

    const marked_b = try m.mark(testing.allocator, "b", "y");
    defer testing.allocator.free(marked_b);

    const clean_b = try m.scan(testing.allocator, marked_b);
    defer testing.allocator.free(clean_b);

    // Zone "a" was not in the second frame; it must be cleared.
    try testing.expect(m.get("a") == null);
    try testing.expect(m.get("b") != null);
}

test "Manager get returns null for unknown id" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();
    try testing.expect(m.get("nonexistent") == null);
}

test "Manager clear removes zone for id" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_part = try m.mark(testing.allocator, "btn", "x");
    defer testing.allocator.free(marked_part);

    const clean = try m.scan(testing.allocator, marked_part);
    defer testing.allocator.free(clean);

    try testing.expect(m.get("btn") != null);
    m.clear("btn");
    try testing.expect(m.get("btn") == null);
}

test "Manager clearAll removes all zones" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    const marked_a = try m.mark(testing.allocator, "a", "x");
    defer testing.allocator.free(marked_a);
    const marked_b = try m.mark(testing.allocator, "b", "y");
    defer testing.allocator.free(marked_b);

    const frame = try std.mem.concat(testing.allocator, u8, &.{ marked_a, marked_b });
    defer testing.allocator.free(frame);

    const clean = try m.scan(testing.allocator, frame);
    defer testing.allocator.free(clean);

    m.clearAll();
    try testing.expect(m.get("a") == null);
    try testing.expect(m.get("b") == null);
}

test "Manager newPrefix returns unique strings on each call" {
    var m = Manager.init(testing.allocator);
    defer m.deinit();

    var buf1: [24]u8 = undefined;
    var buf2: [24]u8 = undefined;
    const p1 = m.newPrefix(&buf1);
    const p2 = m.newPrefix(&buf2);
    try testing.expect(!std.mem.eql(u8, p1, p2));
}

test "tryParseMarker returns null for regular CSI sequence not ending in z" {
    const frame = "\x1B[1m";
    try testing.expect(tryParseMarker(frame, 0) == null);
}

test "tryParseMarker returns null for short sequence" {
    const frame = "\x1B[";
    try testing.expect(tryParseMarker(frame, 0) == null);
}

test "tryParseMarker returns num and len for valid marker" {
    const frame = "\x1B[10001z";
    const result = tryParseMarker(frame, 0);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 10001), result.?.num);
    try testing.expectEqual(@as(usize, 8), result.?.len);
}

test "tryParseMarker returns null for number below COUNTER_START" {
    // ESC[25z is a real DEC mode query; must not be treated as a zone marker.
    const frame = "\x1B[25z";
    try testing.expect(tryParseMarker(frame, 0) == null);
}

test "consumeAnsiSeq returns correct length for SGR sequence" {
    const frame = "\x1B[1;32m";
    try testing.expectEqual(@as(usize, 7), consumeAnsiSeq(frame, 0));
}

test "consumeAnsiSeq returns 2 for ESC followed by non-bracket" {
    // ESC 7 = DEC save cursor (non-CSI two-byte sequence).
    const frame = "\x1B7";
    try testing.expectEqual(@as(usize, 2), consumeAnsiSeq(frame, 0));
}
