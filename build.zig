const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_qjs = b.dependency("qjs", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_uv = b.dependency("uv", .{
        .target = target,
        .optimize = optimize,
    });

    const mod_vexor = b.addModule("vexor", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor/root.zig"),
    });
    mod_vexor.addImport("qjs", dep_qjs.module("qjs"));
    mod_vexor.addImport("uv", dep_uv.module("uv"));

    const mod_vexor_std = b.addModule("vexor", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor-std/root.zig"),
    });
    mod_vexor_std.addImport("qjs", dep_qjs.module("qjs"));
    mod_vexor_std.addImport("uv", dep_uv.module("uv"));
    mod_vexor_std.addImport("vexor", mod_vexor);

    const mod_vexor_cli = b.addModule("vexor-cli", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor-cli/main.zig"),
    });
    mod_vexor_cli.addImport("vexor", mod_vexor);
    mod_vexor_cli.addImport("vexor-std", mod_vexor_std);
    const exe = b.addExecutable(.{
        .name = "vexor",
        .root_module = mod_vexor_cli,
    });
    b.installArtifact(exe);

    const run_test_vexor = b.addRunArtifact(b.addTest(.{
        .root_module = mod_vexor,
    }));
    const run_test_vexor_std = b.addRunArtifact(b.addTest(.{
        .root_module = mod_vexor_std,
    }));
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test_vexor.step);
    test_step.dependOn(&run_test_vexor_std.step);
}
