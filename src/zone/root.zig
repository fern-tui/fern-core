// SPDX-License-Identifier: MIT

// Public surface of fern/zone.

/// AABB of a named component in terminal cells. Set by Manager.scan(), zero until first scan.
pub const ZoneInfo = @import("info.zig").ZoneInfo;

/// Tracks component bounds across frames. Call mark() to wrap output, scan() to record bounds.
pub const Manager = @import("manager.zig").Manager;
