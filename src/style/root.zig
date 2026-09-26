// SPDX-License-Identifier: MIT

//! Public API surface for fern/style.
//!
//! Provides declarative text styling, border rendering, and block layout primitives.

/// Box-drawing glyph set for border rendering.
pub const Border = @import("border.zig").Border;

/// No border.
pub const NONE = @import("border.zig").NONE;
/// Standard single-line box characters.
pub const NORMAL = @import("border.zig").NORMAL;
/// Single-line box characters with rounded corners.
pub const ROUNDED = @import("border.zig").ROUNDED;
/// Heavy/bold single-line box characters.
pub const THICK = @import("border.zig").THICK;
/// Double-line box characters.
pub const DOUBLE = @import("border.zig").DOUBLE;
/// Solid block characters on all sides.
pub const BLOCK = @import("border.zig").BLOCK;

/// Half-block characters on the outer edges (no mid fields).
pub const OUTER_HALF_BLOCK = @import("border.zig").OUTER_HALF_BLOCK;

/// Inner inversion of OUTER_HALF_BLOCK.
pub const INNER_HALF_BLOCK = @import("border.zig").INNER_HALF_BLOCK;

/// Invisible border mapping spaces to all sides for padding.
pub const HIDDEN = @import("border.zig").HIDDEN;

/// ASCII fallback (+, -, |) for terminals without box-drawing support.
pub const ASCII = @import("border.zig").ASCII;

/// Declarative style builder and render pipeline.
/// All setters return a new, mutated `Style` by value.
pub const Style = @import("style.zig").Style;

/// Underline style enumeration. Mirrors `ansi.Attrs.Underline`.
pub const Underline = @import("style.zig").Underline;

/// Default amount of spaces a tab character is expanded into.
pub const TAB_WIDTH_DEFAULT = @import("style.zig").TAB_WIDTH_DEFAULT;

/// Floating point alignment bounded to [0.0, 1.0].
pub const Pos = @import("layout.zig").Pos;

pub const TOP = @import("layout.zig").TOP;
pub const BOTTOM = @import("layout.zig").BOTTOM;
pub const CENTER = @import("layout.zig").CENTER;
pub const LEFT = @import("layout.zig").LEFT;
pub const RIGHT = @import("layout.zig").RIGHT;

/// Horizontally joins text blocks. Caller owns the resulting string.
pub const hstack = @import("layout.zig").hstack;

/// Vertically stacks text blocks. Caller owns the resulting string.
pub const vstack = @import("layout.zig").vstack;

/// Places a string in an explicitly sized 2D box. Caller owns the resulting string.
pub const place = @import("layout.zig").place;

/// Horizontally aligns a string within a specific column width. Caller owns the resulting string.
pub const placeH = @import("layout.zig").placeH;

/// Vertically aligns a string within a specific row height. Caller owns the resulting string.
pub const placeV = @import("layout.zig").placeV;
