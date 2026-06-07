// SPDX-License-Identifier: MIT

// Public surface of fern/anim.  Re-exports only; no logic here.

pub const Spring = @import("spring.zig").Spring;
pub const UpdateResult = @import("spring.zig").UpdateResult;
pub const fps = @import("spring.zig").fps;

pub const Throw = @import("throw.zig").Throw;
pub const Point3 = @import("throw.zig").Point3;
pub const Vec3 = @import("throw.zig").Vec3;
pub const GRAVITY = @import("throw.zig").GRAVITY;
pub const TERM_GRAVITY = @import("throw.zig").TERM_GRAVITY;
