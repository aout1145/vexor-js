const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("libuv", .{});
    const mod_uv = b.addModule("uv", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("./src/root.zig"),
    });

    mod_uv.addCSourceFiles(.{
        .root = dep.path("./src"),
        .files = common_sources,
        .flags = cflags,
    });
    mod_uv.addIncludePath(dep.path("./include"));
    mod_uv.addIncludePath(dep.path("./src"));

    switch (target.result.os.tag) {
        .windows => {
            mod_uv.addCSourceFiles(.{
                .root = dep.path("./src"),
                .files = win_sources,
                .flags = cflags,
            });

            mod_uv.addCMacro("_WIN32_WINNT", "0x0A00");
            mod_uv.addCMacro("WIN32_LEAN_AND_MEAN", "");
            mod_uv.addCMacro("_CRT_DECLARE_NONSTDC_NAMES", "0");

            mod_uv.linkSystemLibrary("psapi", .{});
            mod_uv.linkSystemLibrary("user32", .{});
            mod_uv.linkSystemLibrary("advapi32", .{});
            mod_uv.linkSystemLibrary("iphlpapi", .{});
            mod_uv.linkSystemLibrary("userenv", .{});
            mod_uv.linkSystemLibrary("ws2_32", .{});
            mod_uv.linkSystemLibrary("dbghelp", .{});
            mod_uv.linkSystemLibrary("ole32", .{});
            mod_uv.linkSystemLibrary("shell32", .{});
        },
        .linux => {
            mod_uv.addCSourceFiles(.{
                .root = dep.path("./src"),
                .files = unix_sources ++ linux_sources,
                .flags = cflags,
            });

            mod_uv.addCMacro("_FILE_OFFSET_BITS", "64");
            mod_uv.addCMacro("_LARGEFILE_SOURCE", "");
            mod_uv.addCMacro("_GNU_SOURCE", "");
            mod_uv.addCMacro("_POSIX_C_SOURCE", "200112");

            mod_uv.linkSystemLibrary("pthread", .{});
        },
        .macos => {
            mod_uv.addCSourceFiles(.{
                .root = dep.path("./src"),
                .files = unix_sources ++ darwin_sources,
                .flags = cflags,
            });

            mod_uv.addCMacro("_FILE_OFFSET_BITS", "64");
            mod_uv.addCMacro("_LARGEFILE_SOURCE", "");
            mod_uv.addCMacro("_DARWIN_UNLIMITED_SELECT", "1");
            mod_uv.addCMacro("_DARWIN_USE_64_BIT_INODE", "1");

            mod_uv.linkSystemLibrary("pthread", .{});
        },
        else => unreachable,
    }
}

const cflags: []const []const u8 = &.{
    "-std=gnu90",
};

const common_sources: []const []const u8 = &.{
    "fs-poll.c",
    "idna.c",
    "inet.c",
    "random.c",
    "strscpy.c",
    "strtok.c",
    "thread-common.c",
    "threadpool.c",
    "timer.c",
    "uv-common.c",
    "uv-data-getter-setters.c",
    "version.c",
};

const unix_sources: []const []const u8 = &.{
    "unix/async.c",
    "unix/core.c",
    "unix/dl.c",
    "unix/fs.c",
    "unix/getaddrinfo.c",
    "unix/getnameinfo.c",
    "unix/loop-watcher.c",
    "unix/loop.c",
    "unix/pipe.c",
    "unix/poll.c",
    "unix/process.c",
    "unix/random-devurandom.c",
    "unix/signal.c",
    "unix/stream.c",
    "unix/tcp.c",
    "unix/thread.c",
    "unix/tty.c",
    "unix/udp.c",
};

const darwin_sources: []const []const u8 = &.{
    "unix/darwin-proctitle.c",
    "unix/darwin.c",
    "unix/fsevents.c",
    "unix/random-getentropy.c",

    "unix/proctitle.c",
    "unix/bsd-ifaddrs.c",
    "unix/kqueue.c",
};

const linux_sources: []const []const u8 = &.{
    "unix/linux.c",
    "unix/procfs-exepath.c",
    "unix/random-getrandom.c",
    "unix/random-sysctl-linux.c",

    "unix/proctitle.c",
};

const win_sources: []const []const u8 = &.{
    "win/async.c",
    "win/core.c",
    "win/detect-wakeup.c",
    "win/dl.c",
    "win/error.c",
    "win/fs.c",
    "win/fs-event.c",
    "win/getaddrinfo.c",
    "win/getnameinfo.c",
    "win/handle.c",
    "win/loop-watcher.c",
    "win/pipe.c",
    "win/thread.c",
    "win/poll.c",
    "win/process.c",
    "win/process-stdio.c",
    "win/signal.c",
    "win/snprintf.c",
    "win/stream.c",
    "win/tcp.c",
    "win/tty.c",
    "win/udp.c",
    "win/util.c",
    "win/winapi.c",
    "win/winsock.c",
};
