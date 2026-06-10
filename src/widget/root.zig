// SPDX-License-Identifier: MIT

// Public surface of fern/widget

/// animated spinner. ticks via Cmd(.every).
pub const spinner = @import("spinner.zig");

/// progress bar with optional gradient and spring animation
pub const progress = @import("progress.zig");

/// countdown timer. emits TimeoutMsg when it hits zero.
pub const timer = @import("timer.zig");

/// elapsed time stopwatch. counts up from zero.
pub const stopwatch = @import("stopwatch.zig");

/// single-line text input. scrolls when width is set.
pub const textinput = @import("textinput.zig");

/// pagination state and dot/arabic indicator. no Cmd, pure math.
pub const paginator = @import("paginator.zig");

/// scrollable viewport into content. fixed w x h window, no Cmd.
pub const viewport = @import("viewport.zig");

// shorthand - widget.Spinner instead of widget.spinner.Spinner
pub const Spinner = spinner.Spinner;
pub const Progress = progress.Progress;
pub const Timer = timer.Timer;
pub const Stopwatch = stopwatch.Stopwatch;
pub const TextInput = textinput.TextInput;
pub const Paginator = paginator.Paginator;
pub const Viewport = viewport.Viewport;
