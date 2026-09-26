// SPDX-License-Identifier: MIT

//! Public API surface for fern/anim.
//!
//! This module provides utilities for procedural animation, including damped
//! harmonic springs and simple kinematic projectiles.

/// 2x2 transition matrix for a damped harmonic oscillator.
///
/// Construct once per `(delta_time, ang_freq, damping)` combination, then reuse
/// across consecutive frames.
pub const Spring = @import("spring.zig").Spring;

/// Position and velocity resulting from a `Spring.update` step.
///
/// Feed both values back into the next frame's update. Dropping `vel` resets
/// momentum to zero.
pub const UpdateResult = @import("spring.zig").UpdateResult;

/// Converts a given frame rate (Hz) to delta-time (seconds).
///
/// Do not pass `0`, as it produces infinity.
pub const fps = @import("spring.zig").fps;

/// Linear projectile using Euler integration over a constant acceleration.
///
/// Call `update` each frame. Read state using `position`, `velocity`, and
/// `acceleration`.
pub const Throw = @import("throw.zig").Throw;

/// 3D position. All components default to 0.0.
pub const Point3 = @import("throw.zig").Point3;

/// 3D vector. All components default to 0.0.
///
/// Used for velocity, acceleration, and gravity vectors.
pub const Vec3 = @import("throw.zig").Vec3;

/// Standard world-space gravity: 9.81 m/s^2 downward, Y-up (origin bottom-left).
pub const GRAVITY = @import("throw.zig").GRAVITY;

/// Terminal coordinates gravity: 9.81 m/s^2 downward, Y-down (origin top-left).
pub const TERM_GRAVITY = @import("throw.zig").TERM_GRAVITY;
