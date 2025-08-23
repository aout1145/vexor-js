const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dependency
    const dep_qjs = b.dependency("qjs", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_uv = b.dependency("uv", .{
        .target = target,
        .optimize = optimize,
    });

    // modules
    const mod_vexor = b.addModule("vexor", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor/root.zig"),
    });
    mod_vexor.addImport("qjs", dep_qjs.module("qjs"));
    mod_vexor.addImport("uv", dep_uv.module("uv"));

    const mod_vexor_compiler = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor/compiler.zig"),
    });
    mod_vexor_compiler.addImport("vexor", mod_vexor);
    const vexor_compiler = b.addExecutable(.{
        .name = "vexor-compiler",
        .root_module = mod_vexor_compiler,
    });

    const mod_vexor_std = b.addModule("vexor", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./src/vexor-std/root.zig"),
    });
    mod_vexor_std.addImport("qjs", dep_qjs.module("qjs"));
    mod_vexor_std.addImport("uv", dep_uv.module("uv"));
    mod_vexor_std.addImport("vexor", mod_vexor);
    compileJSFile(b, vexor_compiler, mod_vexor_std, js_files_std);

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

    // tests
    const filter = b.option([]const u8, "test-filter", "Skip tests that do not match any filter");
    const run_test_vexor = b.addRunArtifact(b.addTest(.{
        .root_module = mod_vexor,
        .filter = filter,
    }));
    const run_test_vexor_std = b.addRunArtifact(b.addTest(.{
        .root_module = mod_vexor_std,
        .filter = filter,
    }));
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test_vexor.step);
    test_step.dependOn(&run_test_vexor_std.step);
}

fn compileJSFile(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    mod: *std.Build.Module,
    comptime js_files: anytype,
) void {
    inline for (comptime std.meta.fieldNames(@TypeOf(js_files))) |module_name| {
        const js_file = @field(js_files, module_name);
        const pre_compile_step = b.addRunArtifact(compiler);
        pre_compile_step.addFileArg(b.path(js_file));
        const output = pre_compile_step.addOutputFileArg(js_file ++ ".compiled");
        mod.addAnonymousImport(module_name, .{
            .root_source_file = output,
        });
    }
}
const js_files_std = .{
    .@"timer.js.compiled" = "src/vexor-std/timer.js",
    .@"tty.js.compiled" = "src/vexor-std/tty.js",
    .@"fs.js.compiled" = "src/vexor-std/fs.js",
    .@"process.js.compiled" = "src/vexor-std/process.js",
    .@"os.js.compiled" = "src/vexor-std/os.js",
    .@"path.js.compiled" = "src/vexor-std/path.js",
};
