// SPDX-License-Identifier: MIT
//
// Platform Support:
//   - Linux:   Full support via direct kernel syscalls (pure, libc-free static binaries).
//   - macOS:   Full support via libSystem (libc required due to Darwin syscall stability).
//   - Windows: Planned (v0.3+) via ConPTY / VT100 virtual terminal sequences.
//
// Key Build Commands:
//   zig build                  Build all default artifacts
//   zig build docs             Generate self-contained HTML documentation in zig-out/docs
//   zig build test             Run the complete test suite (file-by-file runner)
//   zig build test-app         Test the core runtime, event loop, and platform hooks
//   zig build test-canvas      Test terminal drawing primitives and cell matrices
//   zig build test-widget      Test high-level UI components
//   zig build example-<name>   Run a specific example (e.g. `zig build example-spinner`)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Upstream Linker Workaround:
    // Recent GCC 16 and glibc 2.43+ toolchains emit .sframe (Simple Frame) unwinding
    // sections containing relocations (e.g. R_X86_64_PC64) that Zig's native self-hosted
    // ELF linker does not yet fully recognize.
    // Upstream tracking: https://codeberg.org/ziglang/zig/issues/30959
    // Flag allows falling back to the LLVM backend when developing on rolling distros:
    const use_llvm = b.option(
        bool,
        "use-llvm",
        "Force LLVM backend (workaround for GCC 16 / glibc 2.43+ .sframe relocations)",
    ) orelse null;

    // Platform ABI boundary:
    // Linux interfaces directly with kernel ioctl/termios syscalls with zero libc dependency.
    // macOS requires linking libSystem because Apple does not guarantee kernel syscall stability.
    const needs_libc: bool = (target.result.os.tag == .macos);

    ////////////////////
    // Core Sub-Modules

    // ANSI parser, CSI escape sequences, terminal detection, and OSC commands
    const ansi_mod = b.addModule("fern_ansi", .{
        .root_source_file = b.path("src/ansi/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Physics-based spring animations and velocity-driven throw transitions
    const anim_mod = b.addModule("fern_anim", .{
        .root_source_file = b.path("src/anim/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Compositing styles, box borders, padding, and Flex-like terminal layouts
    const style_mod = b.addModule("fern_style", .{
        .root_source_file = b.path("src/style/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    style_mod.addImport("fern_ansi", ansi_mod);

    // Mouse tracking, hover detection, and region coordinate multiplexing
    const zone_mod = b.addModule("fern_zone", .{
        .root_source_file = b.path("src/zone/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zone_mod.addImport("fern_ansi", ansi_mod);

    // 2D terminal drawing surface, cell matrices, and Unicode-aware clipping
    const canvas_mod = b.addModule("fern_canvas", .{
        .root_source_file = b.path("src/canvas/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    canvas_mod.addImport("fern_ansi", ansi_mod);

    // Runtime runtime engine: Elm/Bubbletea-style event loop, commands, and render diffing
    const app_mod = b.addModule("fern_app", .{
        .root_source_file = b.path("src/app/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_mod.addImport("fern_ansi", ansi_mod);
    app_mod.addImport("fern_anim", anim_mod);
    app_mod.addImport("fern_zone", zone_mod);
    if (needs_libc) app_mod.link_libc = true;

    // High-level reusable components: viewports, paginators, tables, and text inputs
    const widget_mod = b.addModule("fern_widget", .{
        .root_source_file = b.path("src/widget/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    widget_mod.addImport("fern_ansi", ansi_mod);
    widget_mod.addImport("fern_style", style_mod);
    widget_mod.addImport("fern_app", app_mod);
    widget_mod.addImport("fern_anim", anim_mod);

    ////////////////////////////////////
    // Primary Umbrella Module (`fern`)
    //
    // Exposes the complete engine as a single ergonomic drop-in dependency:
    //
    // In consumer's build.zig:
    //   exe.root_module.addImport("fern", fern_dep.module("fern"));
    //
    // In consumer's code:
    //   const fern = @import("fern");
    //   const App  = fern.App;
    //   const View = fern.widget.Viewport;

    const fern_mod = b.addModule("fern", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    fern_mod.addImport("fern_ansi", ansi_mod);
    fern_mod.addImport("fern_anim", anim_mod);
    fern_mod.addImport("fern_style", style_mod);
    fern_mod.addImport("fern_zone", zone_mod);
    fern_mod.addImport("fern_canvas", canvas_mod);
    fern_mod.addImport("fern_app", app_mod);
    fern_mod.addImport("fern_widget", widget_mod);
    if (needs_libc) fern_mod.link_libc = true;

    ////////////////////////////
    // Documentation Generation
    //
    // Uses an object artifact to trigger AST doc analysis on the umbrella module
    // without linking an unnecessary binary to disk.
    const docs_obj = b.addObject(.{
        .name = "fern_docs",
        .root_module = fern_mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate HTML documentation under zig-out/docs/");
    docs_step.dependOn(&install_docs.step);

    //////////////
    // Test Suite
    //
    // Tests are deliberately compiled into individual standalone units rather
    // than one monolithic runner. This prevents stack-corrupting regressions in one
    // module from masking subtle failures in independent subsystems.

    const test_step = b.step("test", "Run the complete Fern test suite");

    const standalone_tests = [_][]const u8{
        "src/ansi/color.zig",
        "src/ansi/width.zig",
        "src/ansi/csi.zig",
        "src/ansi/osc.zig",
        "src/ansi/str.zig",
        "src/ansi/parse.zig",
        "src/anim/spring.zig",
        "src/anim/throw.zig",
    };

    for (standalone_tests) |src| {
        const unit = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(src),
                .target = target,
                .optimize = optimize,
            }),
            .use_llvm = use_llvm,
        });
        test_step.dependOn(&b.addRunArtifact(unit).step);
    }

    const test_canvas_step = b.step("test-canvas", "Run tests for canvas and rendering primitives");

    const ansi_dep_tests = [_][]const u8{
        "src/style/border.zig",
        "src/style/style.zig",
        "src/style/layout.zig",
        "src/zone/info.zig",
        "src/zone/manager.zig",
        "src/canvas/cell.zig",
        "src/canvas/draw.zig",
        "src/canvas/canvas.zig",
    };

    for (ansi_dep_tests) |src| {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);

        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);

        test_step.dependOn(&run.step);
        if (std.mem.startsWith(u8, src, "src/canvas/")) {
            test_canvas_step.dependOn(&run.step);
        }
    }

    // sys.zig is isolated to separate OS-level ioctl/termios failures from application logic.
    const test_app_step = b.step("test-app", "Run tests for application runtime and OS layers");

    const app_tests = [_]struct {
        path: []const u8,
        link_libc: bool,
        needs_anim: bool,
        needs_ansi: bool,
    }{
        .{ .path = "src/app/cmd.zig", .link_libc = false, .needs_anim = false, .needs_ansi = false },
        .{ .path = "src/app/render.zig", .link_libc = false, .needs_anim = false, .needs_ansi = true },
        .{ .path = "src/app/sys.zig", .link_libc = needs_libc, .needs_anim = false, .needs_ansi = false },
        .{ .path = "src/app/app.zig", .link_libc = needs_libc, .needs_anim = true, .needs_ansi = true },
    };

    for (app_tests) |t| {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path(t.path),
            .target = target,
            .optimize = optimize,
        });
        if (t.needs_ansi) unit_mod.addImport("fern_ansi", ansi_mod);
        if (t.needs_anim) unit_mod.addImport("fern_anim", anim_mod);
        if (t.link_libc) unit_mod.link_libc = true;

        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    const test_widget_step = b.step("test-widget", "Run tests for UI widgets");

    const widget_tests = [_]struct {
        path: []const u8,
        needs_style: bool,
        needs_anim: bool,
        needs_app: bool,
    }{
        .{ .path = "src/widget/key.zig", .needs_style = false, .needs_anim = false, .needs_app = false },
        .{ .path = "src/widget/spinner.zig", .needs_style = true, .needs_anim = false, .needs_app = true },
        .{ .path = "src/widget/progress.zig", .needs_style = true, .needs_anim = true, .needs_app = true },
        .{ .path = "src/widget/timer.zig", .needs_style = false, .needs_anim = false, .needs_app = true },
        .{ .path = "src/widget/stopwatch.zig", .needs_style = false, .needs_anim = false, .needs_app = true },
        .{ .path = "src/widget/paginator.zig", .needs_style = false, .needs_anim = false, .needs_app = false },
        .{ .path = "src/widget/viewport.zig", .needs_style = true, .needs_anim = false, .needs_app = false },
        .{ .path = "src/widget/textinput.zig", .needs_style = true, .needs_anim = false, .needs_app = false },
        .{ .path = "src/widget/table.zig", .needs_style = true, .needs_anim = false, .needs_app = false },
    };

    for (widget_tests) |t| {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path(t.path),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        if (t.needs_style) unit_mod.addImport("fern_style", style_mod);
        if (t.needs_anim) unit_mod.addImport("fern_anim", anim_mod);
        if (t.needs_app) unit_mod.addImport("fern_app", app_mod);

        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    ///////////////////////
    // Example Executables
    //
    // Each example is built with the unified `fern` module as well as individual
    // submodules to maintain seamless backwards compatibility.

    const example_configs = [_]struct {
        name: []const u8,
        path: []const u8,
        needs_anim: bool,
    }{
        .{ .name = "minimal", .path = "examples/00_minimal/main.zig", .needs_anim = false },
        .{ .name = "spinner", .path = "examples/01_spinner/main.zig", .needs_anim = false },
        // fern_anim: because a progress bar that does not move is just a rectangle.
        .{ .name = "progress", .path = "examples/02_progress/main.zig", .needs_anim = true },
        .{ .name = "list", .path = "examples/03_list/main.zig", .needs_anim = false },
        .{ .name = "textinput", .path = "examples/04_textinput/main.zig", .needs_anim = false },
        .{ .name = "table", .path = "examples/05_table/main.zig", .needs_anim = false },
    };

    for (example_configs) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex.path),
                .target = target,
                .optimize = optimize,
            }),
            .use_llvm = use_llvm,
        });

        // Drop-in unified import
        exe.root_module.addImport("fern", fern_mod);

        // Granular imports (kept for compatibility with existing examples)
        exe.root_module.addImport("fern_ansi", ansi_mod);
        exe.root_module.addImport("fern_style", style_mod);
        exe.root_module.addImport("fern_app", app_mod);
        exe.root_module.addImport("fern_widget", widget_mod);
        if (ex.needs_anim) exe.root_module.addImport("fern_anim", anim_mod);

        if (needs_libc) exe.root_module.link_libc = true;
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(
            b.fmt("example-{s}", .{ex.name}),
            b.fmt("Run {s}", .{ex.path}),
        );
        run_step.dependOn(&run_cmd.step);
    }
}
