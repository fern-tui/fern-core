// SPDX-License-Identifier: MIT

// root.zig - fern.style public surface
//
// Users: const style = @import("fern_style");
// Import graph: root -> border, style, layout (no cycles)

pub const Border = @import("border.zig").Border;
pub const NONE = @import("border.zig").NONE;
pub const NORMAL = @import("border.zig").NORMAL;
pub const ROUNDED = @import("border.zig").ROUNDED;
pub const THICK = @import("border.zig").THICK;
pub const DOUBLE = @import("border.zig").DOUBLE;
pub const BLOCK = @import("border.zig").BLOCK;
pub const OUTER_HALF_BLOCK = @import("border.zig").OUTER_HALF_BLOCK;
pub const INNER_HALF_BLOCK = @import("border.zig").INNER_HALF_BLOCK;
pub const HIDDEN = @import("border.zig").HIDDEN;
pub const ASCII = @import("border.zig").ASCII;

pub const Style = @import("style.zig").Style;
pub const Underline = @import("style.zig").Underline;
pub const TAB_WIDTH_DEFAULT = @import("style.zig").TAB_WIDTH_DEFAULT;

pub const Pos = @import("layout.zig").Pos;
pub const TOP = @import("layout.zig").TOP;
pub const BOTTOM = @import("layout.zig").BOTTOM;
pub const CENTER = @import("layout.zig").CENTER;
pub const LEFT = @import("layout.zig").LEFT;
pub const RIGHT = @import("layout.zig").RIGHT;
pub const hstack = @import("layout.zig").hstack;
pub const vstack = @import("layout.zig").vstack;
pub const place = @import("layout.zig").place;
pub const placeH = @import("layout.zig").placeH;
pub const placeV = @import("layout.zig").placeV;
