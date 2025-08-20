const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:encoding";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        module_name,
        &.{
            qjs.zig_utils.defFunc("encode", 0, encode),
            qjs.zig_utils.defFunc("decode", 0, decode),
        },
        &.{},
        .{
            .{
                .encodings = Encoding,
            },
        },
    );
}

const Encoding = enum(i32) {
    UTF_8,
    _,
};
fn freeFunc(_: ?*qjs.JSRuntime, @"opaque": ?*anyopaque, c_ptr: ?*anyopaque) callconv(.c) void {
    const ptr: [*]u8 = @ptrCast(@alignCast(c_ptr));
    const len: usize = @intFromPtr(@"opaque");
    smp_allocator.free(ptr[0..len]);
}
fn encode(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ qjs.JSValue, i32 });
    const string = try qjs.zig_utils.toString(ctx, args[0]);
    defer qjs.JS_FreeCString(ctx, string.ptr);
    const encoding: Encoding = @enumFromInt(args[1]);
    return switch (encoding) {
        .UTF_8 => qjs.JS_NewUint8ArrayCopy(ctx, string.ptr, string.len),
        else => qjs.JS_ThrowRangeError(ctx, "not an available encoding"),
    };
}
fn decode(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ qjs.JSValue, i32 });
    const buffer = try qjs.zig_utils.getBuffer(ctx, args[0]);
    const encoding: Encoding = @enumFromInt(args[1]);
    return switch (encoding) {
        .UTF_8 => try qjs.zig_utils.newValue(ctx, buffer),
        else => qjs.JS_ThrowRangeError(ctx, "not an available encoding"),
    };
}

test Encoding {
    const testRun = @import("vexor").debug.testRun;
    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);
    try testRun(vexor,
        \\import { encodings, encode, decode } from 'std:encoding';
        \\const str = '123abcd啊';
        \\const buf = Uint8Array.of(49, 50, 51, 97, 98, 99, 100, 229, 149, 138);
        \\expectEql(buf.toString(), encode(str, encodings.UTF_8).toString());
        \\expectEql(str, decode(buf, encodings.UTF_8));
    , "");
}
