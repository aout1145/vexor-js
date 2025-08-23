const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:os";
pub const internal_name = "std:internal:os";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        internal_name,
        &os.func_defs,
        &.{},
        .{os.value_defs},
    );
    try vexor.addModule(module_name, @embedFile("os.js.compiled"));
}

const os = struct {
    // for homedir, tmpdir
    fn getStringFn(comptime uv_func: anytype) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, _: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
                const buffer = try smp_allocator.alloc(u8, 256);
                var size: usize = 256;
                defer smp_allocator.free(buffer);
                switch (uv_func(buffer.ptr, &size)) {
                    0 => {
                        return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
                    },
                    uv.UV_ENOBUFS => {
                        try check(ctx, uv_func(buffer.ptr, &size));
                        return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
                    },
                    else => |err| {
                        try check(ctx, err);
                        unreachable;
                    },
                }
            }
        }.func;
    }
    const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("homedir", 0, getStringFn(uv.uv_os_homedir)),
        qjs.zig_utils.defFunc("tmpdir", 0, getStringFn(uv.uv_os_tmpdir)),
    };
    const value_defs = .{
        .platforms = std.Target.Os.Tag,
        .platform = .{
            .type = @as(u32, @intFromEnum(@import("builtin").os.tag)),
            .name = @as([:0]const u8, @tagName(@import("builtin").os.tag)),
        },
        .archs = std.Target.Cpu.Arch,
        .arch = .{
            .type = @as(u32, @intFromEnum(@import("builtin").cpu.arch)),
            .name = @as([:0]const u8, @tagName(@import("builtin").cpu.arch)),
        },
    };
};

test os {
    const testRun = @import("vexor").debug.testRun;
    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);

    try testRun(vexor,
        \\import { homedir, tmpdir } from 'std:os';
        \\expect(typeof homedir() === 'string', 'homedir returns string');
        \\expect(homedir().length > 0, 'homedir returns non-empty');
        \\expect(typeof tmpdir() === 'string', 'tmpdir returns string');
        \\expect(tmpdir().length > 0, 'tmpdir returns non-empty');
    , "");
    try testRun(vexor,
        \\import { platform, platforms, arch, archs } from 'std:os';
        \\expect(typeof platform.type === 'number', 'platform.type is number');
        \\expect(typeof platform.name === 'string', 'platform.name is string');
        \\expect(typeof platforms === 'object', 'platforms is object');
        \\expect(typeof arch.type === 'number', 'arch.type is number');
        \\expect(typeof arch.name === 'string', 'arch.name is string');
        \\expect(typeof archs === 'object', 'archs is object');
    , "");
}
