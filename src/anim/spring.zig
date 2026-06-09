// SPDX-License-Identifier: MIT

// Damped harmonic oscillator: port of Ryan Juckett's "Simple Damped Harmonic
// Motion" (2008-2012).  Algorithm documented at:
//   https://www.ryanjuckett.com/damped-springs/
// Do not substitute a different algorithm.

const std = @import("std");

// used to pick the damping regime
const EPSILON: f64 = std.math.floatEps(f64);

pub const UpdateResult = struct {
    pos: f64,
    vel: f64,
};

pub const Spring = struct {
    pos_pos_coef: f64,
    pos_vel_coef: f64,
    vel_pos_coef: f64,
    vel_vel_coef: f64,

    // Precompute the 2x2 transition matrix.
    // ang_freq and damping are clamped to [0, inf).
    pub fn init(delta_time: f64, ang_freq: f64, damping: f64) Spring {
        const w = @max(0.0, ang_freq);
        const zeta = @max(0.0, damping);

        // zero frequency, nothing moves
        if (w < EPSILON) {
            return .{
                .pos_pos_coef = 1.0,
                .pos_vel_coef = 0.0,
                .vel_pos_coef = 0.0,
                .vel_vel_coef = 1.0,
            };
        }

        // over-damped: two real roots
        if (zeta > 1.0 + EPSILON) {
            const za = -w * zeta;
            const zb = w * std.math.sqrt(zeta * zeta - 1.0);
            const z1 = za - zb;
            const z2 = za + zb;
            const e1 = std.math.exp(z1 * delta_time);
            const e2 = std.math.exp(z2 * delta_time);
            // inv_two_zb = 1 / (z2 - z1)
            const inv_two_zb = 1.0 / (2.0 * zb);

            const e1_i = e1 * inv_two_zb;
            const e2_i = e2 * inv_two_zb;
            const z1e1_i = z1 * e1_i;
            const z2e2_i = z2 * e2_i;

            return .{
                .pos_pos_coef = e1_i * z2 - z2e2_i + e2,
                .pos_vel_coef = -e1_i + e2_i,
                .vel_pos_coef = (z1e1_i - z2e2_i + e2) * z2,
                .vel_vel_coef = -z1e1_i + z2e2_i,
            };
        }

        // under-damped: complex roots, oscillates
        if (zeta < 1.0 - EPSILON) {
            const omega_zeta = w * zeta;
            const alpha = w * std.math.sqrt(1.0 - zeta * zeta);
            const exp_term = std.math.exp(-omega_zeta * delta_time);
            const cos_term = std.math.cos(alpha * delta_time);
            const sin_term = std.math.sin(alpha * delta_time);
            const inv_alpha = 1.0 / alpha;

            const exp_sin = exp_term * sin_term;
            const exp_cos = exp_term * cos_term;
            const exp_omega_zeta_sin_over_alpha =
                exp_term * omega_zeta * sin_term * inv_alpha;

            return .{
                .pos_pos_coef = exp_cos + exp_omega_zeta_sin_over_alpha,
                .pos_vel_coef = exp_sin * inv_alpha,
                .vel_pos_coef = -exp_sin * alpha -
                    omega_zeta * exp_omega_zeta_sin_over_alpha,
                .vel_vel_coef = exp_cos - exp_omega_zeta_sin_over_alpha,
            };
        }

        // critically damped: no overshoot, fastest convergence
        const exp_term = std.math.exp(-w * delta_time);
        const time_exp = delta_time * exp_term;
        const time_exp_freq = time_exp * w;

        return .{
            .pos_pos_coef = time_exp_freq + exp_term,
            .pos_vel_coef = time_exp,
            .vel_pos_coef = -w * time_exp_freq,
            .vel_vel_coef = -time_exp_freq + exp_term,
        };
    }

    // Spring is by value so the same Spring can drive multiple objects.
    pub fn update(self: Spring, pos: f64, vel: f64, target: f64) UpdateResult {
        const p = pos - target;
        return .{
            .pos = p * self.pos_pos_coef + vel * self.pos_vel_coef + target,
            .vel = p * self.vel_pos_coef + vel * self.vel_vel_coef,
        };
    }

    // Typical UI threshold is around 0.001.
    pub fn settled(self: Spring, pos: f64, vel: f64, target: f64, threshold: f64) bool {
        _ = self;
        return @abs(pos - target) < threshold and @abs(vel) < threshold;
    }
};

// Don't pass 0; that produces inf.
pub inline fn fps(n: u32) f64 {
    return 1.0 / @as(f64, @floatFromInt(n));
}

test "fps converts 60 frames per second to the correct delta time" {
    const testing = std.testing;
    try testing.expect(std.math.approxEqAbs(f64, fps(60), 1.0 / 60.0, 1e-6));
}

test "fps converts 30 frames per second to the correct delta time" {
    const testing = std.testing;
    try testing.expect(std.math.approxEqAbs(f64, fps(30), 1.0 / 30.0, 1e-6));
}

test "Spring init with zero angular frequency produces identity motion" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 0.0, 1.0);
    const r = spring.update(5.0, 3.0, 10.0);
    try testing.expect(std.math.approxEqAbs(f64, r.pos, 5.0, 1e-6));
    try testing.expect(std.math.approxEqAbs(f64, r.vel, 3.0, 1e-6));
}

test "Spring update moves position toward target under critically damped motion" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 18.0, 1.0);
    var pos: f64 = 0.0;
    var vel: f64 = 0.0;
    var i: u32 = 0;
    while (i < 120) : (i += 1) {
        const r = spring.update(pos, vel, 100.0);
        pos = r.pos;
        vel = r.vel;
    }
    try testing.expect(@abs(pos - 100.0) < 0.01);
}

test "Spring update never exceeds target under critically damped motion" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 18.0, 1.0);
    var pos: f64 = 0.0;
    var vel: f64 = 0.0;
    var i: u32 = 0;
    while (i < 240) : (i += 1) {
        const r = spring.update(pos, vel, 100.0);
        pos = r.pos;
        vel = r.vel;
        try testing.expect(pos <= 100.001);
    }
}

test "Spring update overshoots target under under-damped motion" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 6.0, 0.2);
    var pos: f64 = 0.0;
    var vel: f64 = 0.0;
    var overshot = false;
    var i: u32 = 0;
    while (i < 180) : (i += 1) {
        const r = spring.update(pos, vel, 100.0);
        pos = r.pos;
        vel = r.vel;
        if (pos > 100.0) overshot = true;
    }
    try testing.expect(overshot);
}

test "Spring update approaches target from below under over-damped motion" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 6.0, 2.0);
    var pos: f64 = 0.0;
    var vel: f64 = 0.0;
    var i: u32 = 0;
    while (i < 600) : (i += 1) {
        const r = spring.update(pos, vel, 100.0);
        pos = r.pos;
        vel = r.vel;
        try testing.expect(pos <= 100.001);
    }
    try testing.expect(@abs(pos - 100.0) < 0.1);
}

test "Spring settled returns true when position and velocity are within threshold" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 18.0, 1.0);
    // 99.999 is not representable exactly in f64: abs(99.999-100.0) > 0.001.
    // 99.9995 gives abs_diff ~0.0005, unambiguously inside the threshold.
    try testing.expect(spring.settled(99.9995, 0.0005, 100.0, 0.001));
}

test "Spring settled returns false when velocity exceeds threshold" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 18.0, 1.0);
    try testing.expect(!spring.settled(100.0, 0.1, 100.0, 0.001));
}

test "Spring settled returns false when position exceeds threshold" {
    const testing = std.testing;
    const spring = Spring.init(fps(60), 18.0, 1.0);
    try testing.expect(!spring.settled(98.0, 0.0, 100.0, 0.001));
}
