// SPDX-License-Identifier: MIT

// sys.zig - OS abstraction and libc quarantine.
// All raw Linux syscalls and macOS libc hacks (like faking pipe2) live here.
// Throws a comptime error on Windows and other unsupported platforms.
const std = @import("std");
const builtin = @import("builtin");

const OS = builtin.os.tag;

// Platform guard
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

pub const IS_LINUX: bool = (OS == .linux);
pub const IS_MACOS: bool = (OS == .macos);

// Async-signal-safe write (raw syscall on Linux, libc on macOS).
// Strictly for best-effort wakeups from signal handlers/threads, so errors
// are intentionally ignored.
pub fn write(fd: std.posix.fd_t, buf: [*]const u8, count: usize) isize {
    if (IS_LINUX) {
        return @bitCast(std.os.linux.write(@bitCast(fd), buf, count));
    } else {
        // std.c.write: extern "c" fn write(fd, buf, nbyte) isize
        return std.c.write(fd, buf, count);
    }
}

// Creates a pipe pair and forces them to close-on-exec.
// Linux lets us do this cleanly in one shot with pipe2(). Since macOS doesn't
// support pipe2, we have to polyfill it: open a standard pipe and manually
// hammer both ends with fcntl to set FD_CLOEXEC.
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

// Fetches terminal dimensions (TIOCGWINSZ).
// Same ioctl on both OSes, just different Zig namespaces.
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

// Worker thread sleep.
// Bypassing the stdlib since 0.16 removed std.time.sleep, and our detached
// workers lack the Io context needed for the new async APIs.
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

// Realtime clock (nanoseconds).
// Polyfill for the removed std.time.nanoTimestamp via clock_gettime.
pub fn nanoTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    if (IS_LINUX) {
        _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    } else {
        _ = std.c.clock_gettime(.REALTIME, &ts);
    }
    return ts.sec * std.time.ns_per_s + ts.nsec;
}

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
