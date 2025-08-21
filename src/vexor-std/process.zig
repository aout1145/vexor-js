const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:process";
pub const internal_name = "std:internal:process";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        internal_name,
        &process.func_defs,
        &.{},
        .{},
    );
    try vexor.addModule(module_name, @embedFile("process.js.compiled"));
}

const process = struct {
    fn cwd(ctx: *qjs.JSContext, _: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const buffer = try smp_allocator.alloc(u8, 256);
        var size: usize = 256;
        defer smp_allocator.free(buffer);
        switch (uv.uv_cwd(buffer.ptr, &size)) {
            0 => {
                return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
            },
            uv.UV_ENOBUFS => {
                try check(ctx, uv.uv_cwd(buffer.ptr, &size));
                return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
            },
            else => |err| {
                try check(ctx, err);
                unreachable;
            },
        }
    }
    fn chdir(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{qjs.JSValue});
        const dir = try qjs.zig_utils.toString(ctx, args[0]);
        defer qjs.JS_FreeCString(ctx, dir.ptr);
        try check(ctx, uv.uv_chdir(dir.ptr));
        return null;
    }
    const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("cwd", 0, cwd),
        qjs.zig_utils.defFunc("chdir", 0, chdir),
    };
};

test process {
    const testRun = @import("vexor").debug.testRun;
    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);

    const global_this = qjs.JS_GetGlobalObject(vexor.ctx);
    defer qjs.JS_FreeValue(vexor.ctx, global_this);
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    var tmp_path: [256]u8 = undefined;
    _ = qjs.JS_SetPropertyStr(
        vexor.ctx,
        global_this,
        "tmpdir",
        try qjs.zig_utils.newValue(vexor.ctx, try tmp_dir.dir.realpath(".", &tmp_path)),
    );

    try testRun(vexor,
        \\import { cwd, chdir } from 'std:process';
        \\expect(typeof cwd() === 'string', 'cwd returns string');
        \\expect(cwd().length > 0, 'cwd returns non-empty');
        \\chdir(tmpdir);
        \\expect(cwd() === tmpdir, 'chdir works');
    , "");
}
