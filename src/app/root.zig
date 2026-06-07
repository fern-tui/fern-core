// SPDX-License-Identifier: MIT

// root.zig - fern.app public surface: re-exports only, no logic.
//
// Users: const fern_app = @import("fern_app");

pub const Cmd = @import("cmd.zig").Cmd;
pub const TickMsg = @import("cmd.zig").TickMsg;
pub const none = @import("cmd.zig").none;
pub const quit = @import("cmd.zig").quit;
pub const batch = @import("cmd.zig").batch;
pub const sequence = @import("cmd.zig").sequence;
pub const task = @import("cmd.zig").task;
pub const after = @import("cmd.zig").after;
pub const every = @import("cmd.zig").every;

pub const Renderer = @import("render.zig").Renderer;
pub const Handlers = @import("app.zig").Handlers;
pub const run = @import("app.zig").run;

// sys helpers exposed so callers can query terminal dimensions without
// importing sys.zig directly (which would create a duplicate-file error
// because app.zig already owns that file via @import("sys.zig")).
pub const queryTerminalSize = @import("sys.zig").queryTerminalSize;
