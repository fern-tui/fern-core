// SPDX-License-Identifier: MIT

// Public surface of fern/anim.

/// 2x2 transition matrix for a damped harmonic oscillator.
/// Construct once per (delta_time, ang_freq, damping) triple, then reuse across frames.
pub const Spring = @import("spring.zig").Spring;

/// Position and velocity from `Spring.update`.
/// Feed both back into the next call; dropping `vel` resets momentum to zero.
pub const UpdateResult = @import("spring.zig").UpdateResult;

/// Converts a frame rate to delta-time. Don't pass 0; that produces inf.
pub const fps = @import("spring.zig").fps;

/// Linear projectile using Euler integration over a constant acceleration.
/// Call `update` each frame; read state with `position`, `velocity`, `acceleration`.
pub const Throw = @import("throw.zig").Throw;

/// 3D position, all components default to 0.
pub const Point3 = @import("throw.zig").Point3;

/// 3D vector, all components default to 0. Used for velocity, acceleration, and gravity.
pub const Vec3 = @import("throw.zig").Vec3;

/// 9.81 m/s² downward, Y-up (origin bottom-left). Standard world-space gravity.
pub const GRAVITY = @import("throw.zig").GRAVITY;

/// 9.81 m/s² downward, Y-down (origin top-left). Use this for terminal coordinates.
pub const TERM_GRAVITY = @import("throw.zig").TERM_GRAVITY;
