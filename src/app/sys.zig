// SPDX-License-Identifier: MIT

// sys.zig - platform syscall abstraction for the fern runtime.
//
// This file is the ONLY place in src/app/ that names std.os.linux or std.c
// directly.  All other modules call through this file.
//
// Supported platforms (v1+):
//   Linux  -- std.os.linux syscalls where std.c is unavailable
//   macOS  -- std.c libc wrappers (no pipe2; uses pipe + fcntl)
//
// Windows (planned v3):
//   Stubs are marked compileError so the compiler surfaces them early.
//
// Compile-time guard: importing this file on an unsupported OS
// is a hard error with a clear message.

const std = @import("std");
const builtin = @import("builtin");

const OS = builtin.os.tag;

// ---------------------------------------------------------------------------
// Platform guard
// ---------------------------------------------------------------------------

comptime {
    switch (OS) {
        .linux, .macos => {},
        .windows => @compileError(
            "fern (sys.zig): Windows is planned for v3. " ++
                "Thank you for your understanding !!",
        ),
        else => @compileError(
            "fern (sys.zig): unsupported OS '" ++ @tagName(OS) ++ "'. " ++
                "Supported: linux, macos.",
        ),
    }
}

// ---------------------------------------------------------------------------
// OS-tag booleans (comptime constants, zero cost after DCE)
// ---------------------------------------------------------------------------

pub const IS_LINUX: bool = (OS == .linux);
pub const IS_MACOS: bool = (OS == .macos);

// ---------------------------------------------------------------------------
// write() -- async-signal-safe byte write to a file descriptor
//
// Used in signal handlers and worker threads.
// Returns the number of bytes written; negative values are ignored by callers
// (wakeup pipes: best-effort, not critical-path).
//
// Linux: raw linux.write syscall (no libc, safe inside signal handler)
// macOS: std.c.write (libc, also async-signal-safe per POSIX)
// ---------------------------------------------------------------------------

pub fn write(fd: std.posix.fd_t, buf: [*]const u8, count: usize) isize {
    if (IS_LINUX) {
        return @bitCast(std.os.linux.write(@bitCast(fd), buf, count));
    } else {
        // std.c.write: extern "c" fn write(fd, buf, nbyte) isize
        return std.c.write(fd, buf, count);
    }
}

// ---------------------------------------------------------------------------
// pipe() / initPipe() -- create a close-on-exec pipe pair
//
// Linux: linux.pipe2 with O_CLOEXEC in one syscall
// macOS: std.c.pipe + two fcntl(F_SETFD, FD_CLOEXEC) calls
//        (pipe2 is a Linux extension; macOS does not have it)
// ---------------------------------------------------------------------------

pub fn initPipe(fds: *[2]std.posix.fd_t) !void {
    if (IS_LINUX) {
        var raw: [2]i32 = undefined;
        const rc = std.os.linux.pipe2(&raw, .{ .CLOEXEC = true });
        if (rc != @intFromEnum(std.os.linux.E.SUCCESS)) return error.SystemResources;
        fds[0] = raw[0];
        fds[1] = raw[1];
    } else {
        // macOS: pipe() then FD_CLOEXEC on both ends.
        var raw: [2]std.c.fd_t = undefined;
        if (std.c.pipe(&raw) != 0) return error.SystemResources;

        // Set FD_CLOEXEC using standard POSIX constants
        _ = std.c.fcntl(raw[0], std.posix.F.SETFD, @as(c_int, std.posix.FD_CLOEXEC));
        _ = std.c.fcntl(raw[1], std.posix.F.SETFD, @as(c_int, std.posix.FD_CLOEXEC));

        fds[0] = raw[0];
        fds[1] = raw[1];
    }
}

/// Close both ends of a pipe produced by initPipe.
pub fn closePipe(fds: *[2]std.posix.fd_t) void {
    if (IS_LINUX) {
        _ = std.os.linux.close(fds[0]);
        _ = std.os.linux.close(fds[1]);
    } else {
        _ = std.c.close(fds[0]);
        _ = std.c.close(fds[1]);
    }
}

// ---------------------------------------------------------------------------
// queryTerminalSize() -- TIOCGWINSZ ioctl
//
// Linux: std.os.linux.ioctl with linux.T.IOCGWINSZ
// macOS: std.c.ioctl with std.c.T.IOCGWINSZ
//        Both wrap the same ioctl(2) syscall; only the import path differs.
// ---------------------------------------------------------------------------

pub fn queryTerminalSize(fd: std.posix.fd_t, cols: *u16, rows: *u16) void {
    var ws: std.posix.winsize = undefined;

    const rc: usize = blk: {
        if (IS_LINUX) {
            break :blk std.os.linux.ioctl(fd, std.os.linux.T.IOCGWINSZ, @intFromPtr(&ws));
        } else {
            // std.c.ioctl is a varargs extern; cast request to c_int.
            // std.c.T.IOCGWINSZ is defined for macOS in std/c.zig.
            const req: c_int = @intCast(std.c.T.IOCGWINSZ);
            break :blk @bitCast(@as(isize, std.c.ioctl(fd, req, &ws)));
        }
    };

    // On Linux errno(rc); on macOS rc == -1 means error.
    // We treat failure as non-fatal: leave cols/rows at defaults.
    const ok: bool = if (IS_LINUX)
        std.os.linux.errno(rc) == .SUCCESS
    else
        rc != @as(usize, @bitCast(@as(isize, -1)));

    if (ok) {
        if (ws.col > 0) cols.* = ws.col;
        if (ws.row > 0) rows.* = ws.row;
    }
}

// ---------------------------------------------------------------------------
// nanosleep() -- sub-second sleep for worker threads
//
// Linux: std.os.linux.nanosleep (std.time.sleep removed in 0.16 and
//        std.Io async replacements require an Io context detached threads lack)
// macOS: std.c.nanosleep (same POSIX interface)
// ---------------------------------------------------------------------------

pub fn threadSleep(ns: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(ns / std.time.ns_per_s),
        .nsec = @intCast(ns % std.time.ns_per_s),
    };
    if (IS_LINUX) {
        _ = std.os.linux.nanosleep(&ts, null);
    } else {
        _ = std.c.nanosleep(&ts, null);
    }
}

// ---------------------------------------------------------------------------
// nanoTimestamp() -- realtime clock in nanoseconds
//
// Linux: std.os.linux.clock_gettime (std.time.nanoTimestamp removed in 0.16)
// macOS: std.c.clock_gettime (POSIX, available on macOS)
// ---------------------------------------------------------------------------

pub fn nanoTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    if (IS_LINUX) {
        _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    } else {
        _ = std.c.clock_gettime(.REALTIME, &ts);
    }
    return ts.sec * std.time.ns_per_s + ts.nsec;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "write wakeup byte to a real pipe does not panic" {
    if (!IS_LINUX and !IS_MACOS) return error.SkipZigTest;
    var fds: [2]std.posix.fd_t = undefined;
    try initPipe(&fds);
    defer closePipe(&fds);
    const byte: [1]u8 = .{0};
    const n = write(fds[1], byte[0..].ptr, 1);
    try std.testing.expect(n == 1);
}

test "threadSleep zero nanoseconds does not hang" {
    threadSleep(0);
}

test "nanoTimestamp returns a positive value" {
    const ts = nanoTimestamp();
    try std.testing.expect(ts > 0);
}

test "queryTerminalSize leaves defaults on non-tty fd" {
    var cols: u16 = 80;
    var rows: u16 = 24;
    // fd 999 is almost certainly invalid; the call should silently no-op.
    queryTerminalSize(999, &cols, &rows);
    // Defaults unchanged because ioctl failed on an invalid fd.
    try std.testing.expectEqual(@as(u16, 80), cols);
    try std.testing.expectEqual(@as(u16, 24), rows);
}
