// SPDX-License-Identifier: MIT

// root.zig -- fern_zone public surface.
//
// Import as: const zone = @import("fern_zone");
// Import graph: root -> info.zig, manager.zig (no cycles; we checked).

pub const ZoneInfo = @import("info.zig").ZoneInfo;
pub const Manager = @import("manager.zig").Manager;
