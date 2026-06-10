// SPDX-License-Identifier: MIT

// Public surface of fern/style

/// box-drawing glyph set for border rendering
pub const Border = @import("border.zig").Border;

pub const NONE = @import("border.zig").NONE;
pub const NORMAL = @import("border.zig").NORMAL;
pub const ROUNDED = @import("border.zig").ROUNDED;
pub const THICK = @import("border.zig").THICK;
pub const DOUBLE = @import("border.zig").DOUBLE;
pub const BLOCK = @import("border.zig").BLOCK;

/// half-block chars on the outer edges, no mid fields
pub const OUTER_HALF_BLOCK = @import("border.zig").OUTER_HALF_BLOCK;

/// inner inversion of OUTER_HALF_BLOCK
pub const INNER_HALF_BLOCK = @import("border.zig").INNER_HALF_BLOCK;

/// spaces on all sides - padding without visible lines
pub const HIDDEN = @import("border.zig").HIDDEN;

/// +, -, | fallback for terminals without box-drawing support
pub const ASCII = @import("border.zig").ASCII;

/// style builder and render pipeline. all setters return a new Style.
pub const Style = @import("style.zig").Style;

/// underline style enum, mirrors ansi.Attrs.Underline
pub const Underline = @import("style.zig").Underline;

pub const TAB_WIDTH_DEFAULT = @import("style.zig").TAB_WIDTH_DEFAULT;

/// f32 alignment in [0.0, 1.0]. use TOP/BOTTOM/LEFT/RIGHT/CENTER.
pub const Pos = @import("layout.zig").Pos;

pub const TOP = @import("layout.zig").TOP;
pub const BOTTOM = @import("layout.zig").BOTTOM;
pub const CENTER = @import("layout.zig").CENTER;
pub const LEFT = @import("layout.zig").LEFT;
pub const RIGHT = @import("layout.zig").RIGHT;

/// join blocks side by side. caller owns the result.
pub const hstack = @import("layout.zig").hstack;

/// join blocks top to bottom. caller owns the result.
pub const vstack = @import("layout.zig").vstack;

/// place str in a box_w x box_h box (placeH + placeV). caller owns the result.
pub const place = @import("layout.zig").place;

/// place str horizontally within box_w cells. caller owns the result.
pub const placeH = @import("layout.zig").placeH;

/// place str vertically within box_h lines. caller owns the result.
pub const placeV = @import("layout.zig").placeV;
