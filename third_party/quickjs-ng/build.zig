const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("quickjs-ng", .{});
    const mod_qjs = b.addModule("qjs", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("./src/root.zig"),
    });
    mod_qjs.addIncludePath(dep.path("."));
    mod_qjs.addCSourceFiles(.{
        .root = dep.path("."),
        .files = files,
        .flags = flags,
    });
    mod_qjs.addCMacro("_GNU_SOURCE", "");
    switch (target.result.os.tag) {
        .windows => {
            mod_qjs.addCMacro("WIN32_LEAN_AND_MEAN", "");
        },
        .linux => {
            mod_qjs.linkSystemLibrary("pthread", .{});
        },
        else => unreachable,
    }
    switch (optimize) {
        .Debug => {
            mod_qjs.addCMacro("ENABLE_DUMPS", "");
        },
        else => {},
    }
}

const flags: []const []const u8 = &.{
    "-std=c11",
    "-funsigned-char",
    "-fno-sanitize=undefined",
};

const files: []const []const u8 = &.{
    "cutils.c",
    "libregexp.c",
    "libunicode.c",
    "xsum.c",
    "quickjs.c",
};
