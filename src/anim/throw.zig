// SPDX-License-Identifier: MIT

// Linear projectile: Euler integration over a constant acceleration.

const std = @import("std");

// standard gravity, Y-up (origin bottom-left)
pub const GRAVITY: Vec3 = .{ .x = 0.0, .y = -9.81, .z = 0.0 };

// terminal gravity, Y-down (origin top-left)
pub const TERM_GRAVITY: Vec3 = .{ .x = 0.0, .y = 9.81, .z = 0.0 };

pub const Point3 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub const Vec3 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub const Throw = struct {
    pos: Point3,
    vel: Vec3,
    acc: Vec3,
    dt: f64, // don't pass 0.0 or negative

    pub fn init(delta_time: f64, pos: Point3, vel: Vec3, acc: Vec3) Throw {
        return .{ .pos = pos, .vel = vel, .acc = acc, .dt = delta_time };
    }

    // pos before vel so callers see position at frame start
    pub fn update(self: *Throw) Point3 {
        self.pos.x += self.vel.x * self.dt;
        self.pos.y += self.vel.y * self.dt;
        self.pos.z += self.vel.z * self.dt;

        self.vel.x += self.acc.x * self.dt;
        self.vel.y += self.acc.y * self.dt;
        self.vel.z += self.acc.z * self.dt;

        return self.pos;
    }

    pub inline fn position(self: *const Throw) Point3 {
        return self.pos;
    }
    pub inline fn velocity(self: *const Throw) Vec3 {
        return self.vel;
    }
    pub inline fn acceleration(self: *const Throw) Vec3 {
        return self.acc;
    }
};

test "Throw init stores given initial state" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    const t = Throw.init(
        dt,
        .{ .x = 1.0, .y = 2.0, .z = 3.0 },
        .{ .x = 4.0, .y = 5.0, .z = 6.0 },
        GRAVITY,
    );
    try testing.expect(std.math.approxEqAbs(f64, t.position().x, 1.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.position().y, 2.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.position().z, 3.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.velocity().x, 4.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.velocity().y, 5.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.velocity().z, 6.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, t.acceleration().y, GRAVITY.y, 1e-6));
}

test "Throw update advances position by velocity times delta time" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    var t = Throw.init(
        dt,
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .{},
    );
    const pos = t.update();
    try testing.expect(std.math.approxEqAbs(f64, pos.x, 1.0 * dt, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, pos.y, 0.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, pos.z, 0.0, 1e-6));
}

test "Throw update accumulates acceleration into velocity" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    var t = Throw.init(
        dt,
        .{},
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 1.0, .y = 0.0, .z = 0.0 },
    );
    _ = t.update();
    _ = t.update();
    try testing.expect(std.math.approxEqAbs(f64, t.velocity().x, 2.0 * dt, 1e-6));
}

test "Throw under terminal gravity matches kinematic formula after one second" {
    // s = 0.5 * g * t^2 where g=9.81, t=1.0 => 4.905 m
    // Euler integration accrues O(dt) error per step; tolerance 0.1 is fair
    // for 60 steps at fps(60).
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    var t = Throw.init(dt, .{}, .{}, TERM_GRAVITY);
    var i: u32 = 0;
    while (i < 60) : (i += 1) _ = t.update();
    try testing.expect(@abs(t.position().y - 4.905) < 0.1);
}

test "Throw position does not mutate state" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    const t = Throw.init(dt, .{ .x = 5.0, .y = 5.0, .z = 5.0 }, .{}, .{});
    _ = t.position();
    _ = t.position();
    try testing.expect(std.math.approxEqAbs(f64, t.position().x, 5.0, 1e-6));
}

test "Throw velocity does not mutate state" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    const t = Throw.init(dt, .{}, .{ .x = 3.0, .y = 0.0, .z = 0.0 }, .{});
    _ = t.velocity();
    _ = t.velocity();
    try testing.expect(std.math.approxEqAbs(f64, t.velocity().x, 3.0, 1e-6));
}

test "Throw acceleration returns the constant acceleration unchanged after updates" {
    const testing = std.testing;
    const dt = @import("spring.zig").fps(60);
    var t = Throw.init(dt, .{}, .{}, TERM_GRAVITY);
    _ = t.update();
    _ = t.update();
    _ = t.update();
    try testing.expect(std.math.approxEqAbs(f64, t.acceleration().y, TERM_GRAVITY.y, 1e-6));
}
