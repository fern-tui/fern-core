# Changelog

All notable changes to the `fern-core` project will be documented in this file.

## [Unreleased]

## [0.1.6-dev.14] - 2026-09-26

### Added
- Unified `fern` umbrella root module (`src/root.zig`), enabling single drop-in
  package imports (`@import("fern")`).
- Dual-mode terminal rendering: native support for both full-screen alternate
  buffer (`.alt_screen = true`) and inline CLI rendering.
- Automated window resize event propagation (`ansi.ResizeEvent`) eliminating
  per-frame `ioctl` syscalls.
- `Table` widget demo (`05_table`).
- Upstream compatibility support for Zig `0.17.0-dev`.

### Changed
- Refactored `build.zig` to eliminate redundant `.a` static library compilation
  and streamlined test/example build matrices.
- Optimized renderer diffing to retain a single backing frame buffer,
  eliminating per-frame line allocation churn.
- Updated `runSimple` to recycle a frame scratch arena (`reset(.retain_capacity)`)
  to prevent memory leaks during long runs.
- Adopted `std.heap.smp_allocator` as default application allocator for
  Zig 0.16.0+ compatibility.
- Streamlined comptime event dispatching in `app.zig` using direct `@hasField`
  and `@FieldType` lookups.
- Migrated canvas array initializations from removed `**` operator to `@splat`.
- Modernized example suite (`00_minimal`, `01_spinner`, `02_progress`, `05_table`)
  to consume the unified `fern` module.

### Fixed
- Fixed raw-mode newline staircasing by properly emitting CRLF (`\r\n`) in diff painter.
- Fixed cursor visibility bug where `render.zig` was inadvertently restoring the
  cursor when `.hide_cursor = true` was active.
- Guaranteed terminal state restoration (cursor, mouse tracking, alt-screen, termios)
  via `defer` to prevent bricked shells on errors.
- Enforced libc-free builds for Linux targets while retaining Darwin libc requirements.

## [0.1.6-beta.11] - 2026-06-14

### Added
- Single field `TextInput` demo (`04_textinput`).
- `runSimple` application runner, exported directly from the root.
- Extracted `runImpl` and added the `RunOptions` struct, retaining the `run()` compatibility shim.
- Minimal build step and example (`00_minimal`).

### Fixed
- Snapshot batch slice before dispatch to prevent stack corruption.
- Updated version tracking in `build.zig.zon`.

## [0.1.6-beta.10] - 2026-06-12

### Added
- Native `list` widget (promoted and generalized from previously hand-rolled examples).
- Directional helper functions and an `isQuit` helper exposed in `widget/key`.
- `-Duse-llvm` fallback flag to all tests to safely bypass the glibc 2.43 linker bug.
- Continuous integration and CD workflow relying on Zig `release-0.16.0`.
- Code of Conduct and updated `CODEOWNERS` referencing the maintainers team.

### Changed
- Condensed and cleaned up code comments/docstrings across `app`, `style`, `widget`, `anim`,
  `zone`, and `ansi`.
- Revised `CONTRIBUTING.md` for structure and improved setup instructions.
- Clarified AI usage and project features in `README.md`.
- Consolidated example documentations into `examples.md` showcasing asset GIFs.

### Fixed
- Critical stack-escape undefined behavior (UB) in `stopwatch.start()`.
- Wildcard `id==0` issue inside the timer logic.
- Broken asset and image paths across the README and `docs/assets`.

## [0.1.5-beta.9] - 2026-06-07

### Added
- Added all pub/ files from local vcs to github.com
- Initial project architecture and repository initialization.


*(Note: History prior to v0.1.5 was maintained in a local, offline VCS with no active development 
        or public releases.)*