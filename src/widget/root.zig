// SPDX-License-Identifier: MIT

// root.zig - fern.widget public surface: re-exports only, no logic.
//
// Users: const widget = @import("fern_widget");
// Import graph: root -> spinner, progress, timer, stopwatch,
//                       textinput, paginator, viewport (no cycles)

pub const spinner = @import("spinner.zig");
pub const progress = @import("progress.zig");
pub const timer = @import("timer.zig");
pub const stopwatch = @import("stopwatch.zig");
pub const textinput = @import("textinput.zig");
pub const paginator = @import("paginator.zig");
pub const viewport = @import("viewport.zig");

// Convenience re-exports of the most-used types so callers can write
// `widget.Spinner` instead of `widget.spinner.Spinner`.
pub const Spinner = spinner.Spinner;
pub const Progress = progress.Progress;
pub const Timer = timer.Timer;
pub const Stopwatch = stopwatch.Stopwatch;
pub const TextInput = textinput.TextInput;
pub const Paginator = paginator.Paginator;
pub const Viewport = viewport.Viewport;
