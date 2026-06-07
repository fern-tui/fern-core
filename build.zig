// SPDX-License-Identifier: MIT

// build.zig -- fern library build script (Zig 0.16.0)
//
// Platform support:
//   Linux   -- fully supported; std.os.linux syscalls, libc-free
//   macOS   -- supported; sys.zig uses std.c.*, so linkLibC() is added
//   Windows -- compile-time error in sys.zig; planned for v3, do not wait up
//
// Steps:
//   zig build                   -- build and install all libraries
//   zig build test              -- run all per-module unit tests
//   zig build test-app          -- run only the app/ module tests
//   zig build test-widget       -- run only the widget/ module tests
//   zig build example-spinner   -- run examples/01_spinner
//   zig build example-progress  -- run examples/02_progress
//   zig build example-list      -- run examples/03_list

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // sys.zig calls into std.c.* (extern "c") on macOS because Apple
    // decided the raw syscall ABI is not for users.  On Linux, sys.zig
    // speaks to the kernel directly via std.os.linux and skips libc
    // entirely.  linkLibC() is harmless there and covers any std.posix
    // path that silently routes through libc anyway.
    const needs_libc: bool = target.result.os.tag == .macos or
        target.result.os.tag == .linux;

    // ---- libraries ----------------------------------------------------------

    const ansi_lib = b.addLibrary(.{
        .name = "fern_ansi",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ansi/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(ansi_lib);

    const anim_lib = b.addLibrary(.{
        .name = "fern_anim",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/anim/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(anim_lib);

    // ansi_mod: the popular kid -- style, zone, and app all depend on it.
    const ansi_mod = ansi_lib.root_module;

    const style_mod = b.createModule(.{
        .root_source_file = b.path("src/style/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    style_mod.addImport("fern_ansi", ansi_mod);

    const style_lib = b.addLibrary(.{
        .name = "fern_style",
        .linkage = .static,
        .root_module = style_mod,
    });
    b.installArtifact(style_lib);

    const zone_mod = b.createModule(.{
        .root_source_file = b.path("src/zone/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zone_mod.addImport("fern_ansi", ansi_mod);

    const zone_lib = b.addLibrary(.{
        .name = "fern_zone",
        .linkage = .static,
        .root_module = zone_mod,
    });
    b.installArtifact(zone_lib);

    // ---- app module ---------------------------------------------------------
    //
    // app/ has four files: root.zig, cmd.zig, render.zig, app.zig.
    // sys.zig is internal; app.zig @imports it by relative path and it
    // never surfaces as a named module -- the Zig module system resolves
    // sibling @import("sys.zig") by path, no addImport("sys", ...) needed.

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_mod.addImport("fern_ansi", ansi_mod);
    app_mod.addImport("fern_anim", anim_lib.root_module);
    app_mod.addImport("fern_zone", zone_mod);

    const app_lib = b.addLibrary(.{
        .name = "fern_app",
        .linkage = .static,
        .root_module = app_mod,
    });
    if (needs_libc) app_lib.root_module.link_libc = true;
    b.installArtifact(app_lib);

    // ---- widget module ------------------------------------------------------
    //
    // widget/ depends on: fern_ansi, fern_style, fern_app, fern_anim.
    // Pure Zig; no platform syscalls, no libc, no drama.
    // widget/key.zig is internal, resolved as a relative sibling @import.

    const widget_mod = b.createModule(.{
        .root_source_file = b.path("src/widget/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    widget_mod.addImport("fern_ansi", ansi_mod);
    widget_mod.addImport("fern_style", style_mod);
    widget_mod.addImport("fern_app", app_mod);
    widget_mod.addImport("fern_anim", anim_lib.root_module);

    const widget_lib = b.addLibrary(.{
        .name = "fern_widget",
        .linkage = .static,
        .root_module = widget_mod,
    });
    b.installArtifact(widget_lib);

    // ---- tests --------------------------------------------------------------
    //
    // One test binary per source file so you know exactly which module
    // ruined your day.

    const test_step = b.step("test", "Run all fern tests");

    // --- ansi and anim: standalone; no external imports ----------------------

    const ansi_sources: []const []const u8 = &.{
        "src/ansi/color.zig",
        "src/ansi/width.zig",
        "src/ansi/csi.zig",
        "src/ansi/osc.zig",
        "src/ansi/str.zig",
        "src/ansi/parse.zig",
        "src/ansi/root.zig",
    };

    const anim_sources: []const []const u8 = &.{
        "src/anim/spring.zig",
        "src/anim/throw.zig",
    };

    // root.zig is a re-export shim with no test blocks; skip it.
    inline for (.{ ansi_sources, anim_sources }) |group| {
        for (group) |src| {
            const unit = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path(src),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            test_step.dependOn(&b.addRunArtifact(unit).step);
        }
    }

    // --- style and zone: each needs fern_ansi --------------------------------

    const ansi_dep_sources: []const []const u8 = &.{
        "src/style/border.zig",
        "src/style/style.zig",
        "src/style/layout.zig",
        "src/zone/info.zig",
        "src/zone/manager.zig",
    };

    for (ansi_dep_sources) |src| {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        test_step.dependOn(&b.addRunArtifact(unit).step);
    }

    // --- app/: cmd, render, sys, app -----------------------------------------
    //
    // sys.zig is tested in isolation so its syscall failures are clearly
    // distinguishable from the application logic sitting above it.
    //
    // Import map:
    //   cmd.zig    -- std only
    //   render.zig -- fern_ansi
    //   sys.zig    -- std only (std.c / std.os.linux); linkLibC() on macOS
    //   app.zig    -- fern_ansi + fern_anim; sibling path resolution for
    //                 cmd.zig, render.zig, sys.zig

    const test_app_step = b.step("test-app", "Run only the app/ module tests");

    // cmd.zig: std only, no imports.
    {
        const unit = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/app/cmd.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // render.zig: fern_ansi.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/app/render.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // sys.zig: no named imports; linkLibC() required on macOS for std.c.*.
    {
        const unit = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/app/sys.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        if (needs_libc) unit.root_module.link_libc = true;
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // app.zig: fern_ansi + fern_anim; cmd/render/sys resolved as siblings.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/app/app.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_anim", anim_lib.root_module);
        const unit = b.addTest(.{ .root_module = unit_mod });
        if (needs_libc) unit.root_module.link_libc = true;
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // --- widget/: one test binary per file -----------------------------------
    //
    // Import map (key.zig siblings resolved by relative @import, not listed):
    //   key.zig        -- fern_ansi
    //   spinner.zig    -- fern_ansi, fern_style, fern_app
    //   progress.zig   -- fern_ansi, fern_style, fern_app, fern_anim
    //   timer.zig      -- fern_app
    //   stopwatch.zig  -- fern_app
    //   paginator.zig  -- fern_ansi, sibling key.zig
    //   viewport.zig   -- fern_ansi, fern_style, sibling key.zig
    //   textinput.zig  -- fern_ansi, fern_style, sibling key.zig

    const test_widget_step = b.step("test-widget", "Run only the widget/ module tests");

    // key.zig: fern_ansi.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/key.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // spinner.zig: fern_ansi, fern_style, fern_app.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/spinner.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        unit_mod.addImport("fern_app", app_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // progress.zig: fern_ansi, fern_style, fern_app, fern_anim.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/progress.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        unit_mod.addImport("fern_app", app_mod);
        unit_mod.addImport("fern_anim", anim_lib.root_module);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // timer.zig: fern_app only.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/timer.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_app", app_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // stopwatch.zig: fern_app only.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/stopwatch.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_app", app_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // paginator.zig: fern_ansi; key.zig resolved as relative sibling.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/paginator.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // viewport.zig: fern_ansi, fern_style; key.zig resolved as sibling.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/viewport.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // textinput.zig: fern_ansi, fern_style; key.zig resolved as sibling.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/textinput.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        const unit = b.addTest(.{ .root_module = unit_mod });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // ---- examples -----------------------------------------------------------

    // --- spinner example -----------------------------------------------------
    const spinner_exe = b.addExecutable(.{
        .name = "spinner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/01_spinner/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    spinner_exe.root_module.addImport("fern_ansi", ansi_mod);
    spinner_exe.root_module.addImport("fern_style", style_mod);
    spinner_exe.root_module.addImport("fern_app", app_mod);
    spinner_exe.root_module.addImport("fern_widget", widget_mod);

    if (needs_libc) spinner_exe.root_module.link_libc = true;
    b.installArtifact(spinner_exe);

    const run_spinner = b.addRunArtifact(spinner_exe);
    const example_spinner_step = b.step("example-spinner", "Run examples/01_spinner");
    example_spinner_step.dependOn(&run_spinner.step);

    // Museum exhibit: static stripped binary approach.  Sheds a few KB at
    // the cost of an extra install step.  Preserved for posterity and the
    // three people who will inevitably ask why it was removed.
    //
    //     const spinner_exe = b.addExecutable(.{
    //         .name = "spinner",
    //         .root_module = b.createModule(.{
    //             .root_source_file = b.path("examples/01_spinner/main.zig"),
    //             .target = target,
    //             .optimize = optimize,
    //         }),
    //     });
    //
    //     spinner_exe.linkage = .static;
    //
    //     if (needs_libc) {
    //         spinner_exe.root_module.link_libc = true;
    //     }
    //     spinner_exe.root_module.strip = true;
    //
    //     spinner_exe.root_module.addImport("fern_ansi", ansi_mod);
    //     spinner_exe.root_module.addImport("fern_style", style_mod);
    //     spinner_exe.root_module.addImport("fern_app", app_mod);
    //     spinner_exe.root_module.addImport("fern_widget", widget_mod);
    //
    //     b.installArtifact(spinner_exe);
    //
    //     const install_spinner = b.addInstallArtifact(spinner_exe, .{});
    //
    //     const run_spinner = b.addRunArtifact(spinner_exe);
    //     const example_spinner_step = b.step("example-spinner", "Run examples/01_spinner");
    //
    //     example_spinner_step.dependOn(&install_spinner.step);
    //     example_spinner_step.dependOn(&run_spinner.step);

    // --- progress example ----------------------------------------------------
    const progress_exe = b.addExecutable(.{
        .name = "progress",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/02_progress/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    progress_exe.root_module.addImport("fern_ansi", ansi_mod);
    progress_exe.root_module.addImport("fern_style", style_mod);
    progress_exe.root_module.addImport("fern_app", app_mod);
    progress_exe.root_module.addImport("fern_widget", widget_mod);
    // fern_anim: because a progress bar that does not move is just a rectangle.
    progress_exe.root_module.addImport("fern_anim", anim_lib.root_module);

    if (needs_libc) progress_exe.root_module.link_libc = true;
    b.installArtifact(progress_exe);

    const run_progress = b.addRunArtifact(progress_exe);
    const example_progress_step = b.step("example-progress", "Run examples/02_progress");
    example_progress_step.dependOn(&run_progress.step);

    // --- list example --------------------------------------------------------
    const list_exe = b.addExecutable(.{
        .name = "list",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/03_list/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    list_exe.root_module.addImport("fern_ansi", ansi_mod);
    list_exe.root_module.addImport("fern_style", style_mod);
    list_exe.root_module.addImport("fern_app", app_mod);
    list_exe.root_module.addImport("fern_widget", widget_mod);

    if (needs_libc) list_exe.root_module.link_libc = true;
    b.installArtifact(list_exe);

    const run_list = b.addRunArtifact(list_exe);
    const example_list_step = b.step("example-list", "Run examples/03_list");
    example_list_step.dependOn(&run_list.step);
}
