// SPDX-License-Identifier: MIT

// platforms:
// linux: full (libc-free)
// macos: needs libc
// windows: unsupported (maybe v3)
//
// commands:
// zig build                - build all
// zig build test           - run all tests
// zig build test-app       - test app module
// zig build test-widget    - test widget module
// zig build example- - run examples (spinner, progress, list)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Upstream linker issue: Zig's self-hosted linker can't handle the .sframe relocations
    // (R_X86_64_PC64) coming from recent GCC16/glibc updates.
    // Issue: https://codeberg.org/ziglang/zig/issues/30959
    //
    // Workaroun: bypass the internal linker using `zig build test -Duse-llvm=true`
    const use_llvm = b.option(bool, "use-llvm", "force LLVM backend (GCC16/glibc2.43+ sframe workaround)") orelse null;

    // macos needs libc since apple hides raw syscalls.
    // linux talks directly to the kernel and skips libc.
    // leaving linkLibC() on is fine for both anyway.
    const needs_libc: bool = target.result.os.tag == .macos or
        target.result.os.tag == .linux;

    // libraries >>

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

    // ansi_mod: used by style, zone, and app
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

    // app module >>
    //
    // app/ files: root, cmd, render, app.
    // sys.zig is internal. app.zig imports it by path, so no addImport is needed.

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

    // widget module >>
    //
    // widget dependencies: fern_ansi, fern_style, fern_app, fern_anim.
    // pure zig, no libc or syscalls.
    // key.zig is internal, imported by path.

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

    // docs >>
    //
    // Create a library step that will have its documentation emitted.
    // We reuse the existing widget_mod which already has all imports.
    const docs_lib = b.addLibrary(.{
        .name = "fern_docs",
        .root_module = widget_mod, // widget_mod already includes everything
        .linkage = .static,
    });

    // Retrieve the directory where Zig will place the emitted HTML files.
    const emitted_docs = docs_lib.getEmittedDocs();

    // Install those HTML files into zig-out/docs/ when the docs step runs.
    const install_docs = b.addInstallDirectory(.{
        .source_dir = emitted_docs,
        .install_dir = .prefix,      // installs to zig-out/
        .install_subdir = "docs",    // subdirectory: zig-out/docs/
    });

    // Create a top-level step named "docs".
    const docs_step = b.step("docs", "Generate project documentation (HTML)");
    docs_step.dependOn(&install_docs.step);

    // tests >>
    //
    // one test binary per file to see which module failed.

    const test_step = b.step("test", "Run all fern tests");

    // ansi and anim: standalone, no external imports

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

    // root.zig is a re-export shim with no tests. skip it.
    inline for (.{ ansi_sources, anim_sources }) |group| {
        for (group) |src| {
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
    }

    // style and zone both need fern_ansi

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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        test_step.dependOn(&b.addRunArtifact(unit).step);
    }

    // app/: cmd, render, sys, app >>
    //
    // test sys.zig by itself to separate syscall errors from app bugs.
    //
    // imports:
    // cmd: std
    // render: fern_ansi
    // sys: std (needs libc on mac)
    // app: fern_ansi, fern_anim, and local files by path

    const test_app_step = b.step("test-app", "Run only the app/ module tests");

    {
        const unit = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/app/cmd.zig"),
                .target = target,
                .optimize = optimize,
            }),
            .use_llvm = use_llvm,
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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
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
            .use_llvm = use_llvm,
        });
        if (needs_libc) unit.root_module.link_libc = true;
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // app.zig: fern_ansi + fern_anim; cmd/render/sys resolved.....
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/app/app.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_anim", anim_lib.root_module);
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        if (needs_libc) unit.root_module.link_libc = true;
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_app_step.dependOn(&run.step);
    }

    // widget/: one test binary per file >>
    //
    // imports (locals by path):
    // key: fern_ansi
    // spinner: fern_ansi, fern_style, fern_app
    // progress: fern_ansi, fern_style, fern_app, fern_anim
    // timer: fern_app
    // stopwatch: fern_app
    // paginator: fern_ansi, key
    // viewport: fern_ansi, fern_style, key
    // textinput: fern_ansi, fern_style, key

    const test_widget_step = b.step("test-widget", "Run only the widget/ module tests");

    // key.zig: fern_ansi.
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/key.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
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
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // paginator.zig: fern_ansi; key.zig resolved
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/paginator.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // viewport.zig: fern_ansi, fern_style; key.zig resolved
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/viewport.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // textinput.zig: fern_ansi, fern_style; key.zig resolved
    {
        const unit_mod = b.createModule(.{
            .root_source_file = b.path("src/widget/textinput.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_mod.addImport("fern_ansi", ansi_mod);
        unit_mod.addImport("fern_style", style_mod);
        const unit = b.addTest(.{ .root_module = unit_mod, .use_llvm = use_llvm });
        const run = b.addRunArtifact(unit);
        test_step.dependOn(&run.step);
        test_widget_step.dependOn(&run.step);
    }

    // examples >>

    // spinner example >
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

    // static stripped binary approach. Sheds a few KB at
    // the cost of an extra install step.
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

    // progress example >
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

    // list example >
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
