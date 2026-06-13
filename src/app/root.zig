// SPDX-License-Identifier: MIT

// Public surface of fern/app

/// side-effect descriptor returned by update()
pub const Cmd = @import("cmd.zig").Cmd;

/// recommended msg variant for .after and .every payloads
pub const TickMsg = @import("cmd.zig").TickMsg;

pub const none = @import("cmd.zig").none;
pub const quit = @import("cmd.zig").quit;

/// run multiple Cmds concurrently
pub const batch = @import("cmd.zig").batch;

/// like batch but intended to be ordered. v1 runs concurrently; ordering is v2.
pub const sequence = @import("cmd.zig").sequence;

/// run a function on a worker thread, push the result as a Msg
pub const task = @import("cmd.zig").task;

/// push a Msg after ns nanoseconds
pub const after = @import("cmd.zig").after;

/// push a generated Msg every ns nanoseconds. return another .every from update() to keep it going.
pub const every = @import("cmd.zig").every;

/// line-diff renderer: frame string -> minimal terminal escape sequences
pub const Renderer = @import("render.zig").Renderer;

/// init / update / view callback bundle
pub const Handlers = @import("app.zig").Handlers;

/// start the TEA event loop. blocks until update() returns quit.
pub const run = @import("app.zig").run;

/// runtime options for the event loop.
pub const RunOptions = @import("app.zig").RunOptions;
pub const runOpts = @import("app.zig").runOpts;

/// convenience entry point: manages arena and process exit. no init_ctx needed.
pub const runSimple = @import("app.zig").runSimple;

// re-exported here because app.zig already owns sys.zig; callers can't import it directly.
/// TIOCGWINSZ ioctl - writes cols and rows for the given fd
pub const queryTerminalSize = @import("sys.zig").queryTerminalSize;
