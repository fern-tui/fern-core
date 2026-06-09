// SPDX-License-Identifier: MIT

const ansi = @import("fern_ansi");

// AABB of a named component in 0-based terminal cells.
// (0, 0) is top-left. Set by Manager.scan(); zero value means not yet scanned.
pub const ZoneInfo = struct {
    start_x: u16,
    start_y: u16,
    end_x: u16,
    end_y: u16,

    // Inclusive on all edges. Returns false for malformed zones where start > end.
    pub fn inBounds(self: ZoneInfo, mouse: ansi.MouseEvent) bool {
        if (self.start_x > self.end_x or self.start_y > self.end_y) return false;
        if (mouse.col < self.start_x or mouse.col > self.end_x) return false;
        if (mouse.row < self.start_y or mouse.row > self.end_y) return false;
        return true;
    }

    // (0, 0) is the zone's top-left corner. Returns null if outside.
    pub fn relPos(self: ZoneInfo, mouse: ansi.MouseEvent) ?struct { x: u16, y: u16 } {
        if (!self.inBounds(mouse)) return null;
        return .{
            .x = mouse.col - self.start_x,
            .y = mouse.row - self.start_y,
        };
    }

    // All-zero means registered but not yet scanned.
    pub fn isEmpty(self: ZoneInfo) bool {
        return self.start_x == 0 and self.start_y == 0 and self.end_x == 0 and self.end_y == 0;
    }
};

const std = @import("std");

fn makeMouseEvent(col: u16, row: u16) ansi.MouseEvent {
    return .{
        .col = col,
        .row = row,
        .button = .none,
        .kind = .motion,
    };
}

test "ZoneInfo inBounds returns true when mouse is inside zone" {
    const z = ZoneInfo{ .start_x = 2, .start_y = 1, .end_x = 5, .end_y = 3 };
    const mouse = makeMouseEvent(3, 2);
    try std.testing.expect(z.inBounds(mouse));
}

test "ZoneInfo inBounds returns true on the boundary" {
    const z = ZoneInfo{ .start_x = 2, .start_y = 1, .end_x = 5, .end_y = 3 };
    try std.testing.expect(z.inBounds(makeMouseEvent(2, 1)));
    try std.testing.expect(z.inBounds(makeMouseEvent(5, 3)));
}

test "ZoneInfo inBounds returns false when mouse is outside zone" {
    const z = ZoneInfo{ .start_x = 2, .start_y = 1, .end_x = 5, .end_y = 3 };
    try std.testing.expect(!z.inBounds(makeMouseEvent(6, 2)));
}

test "ZoneInfo inBounds returns false for malformed zone where start > end" {
    const z = ZoneInfo{ .start_x = 5, .start_y = 3, .end_x = 2, .end_y = 1 };
    try std.testing.expect(!z.inBounds(makeMouseEvent(3, 2)));
}

test "ZoneInfo relPos returns zero-based offset from zone origin" {
    const z = ZoneInfo{ .start_x = 2, .start_y = 1, .end_x = 5, .end_y = 3 };
    const p = z.relPos(makeMouseEvent(4, 2));
    try std.testing.expect(p != null);
    try std.testing.expectEqual(@as(u16, 2), p.?.x);
    try std.testing.expectEqual(@as(u16, 1), p.?.y);
}

test "ZoneInfo relPos returns null when mouse is outside zone" {
    const z = ZoneInfo{ .start_x = 2, .start_y = 1, .end_x = 5, .end_y = 3 };
    try std.testing.expect(z.relPos(makeMouseEvent(10, 10)) == null);
}

test "ZoneInfo isEmpty returns true for zero zone" {
    const z = ZoneInfo{ .start_x = 0, .start_y = 0, .end_x = 0, .end_y = 0 };
    try std.testing.expect(z.isEmpty());
}
