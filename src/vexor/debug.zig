const std = @import("std");
const qjs = @import("qjs");

const Vexor = @import("./vexor.zig");

/// expected_err: null means any
pub fn testRun(vexor: *Vexor, js_str: []const u8, expected_err: ?[]const u8) !void {
    var buffer: [65536]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try vexor.run(js_str, null, stream.writer().any());
    if (expected_err) |expected| {
        if (!std.mem.eql(u8, expected, stream.getWritten())) {
            std.debug.print("expect:\n{s}\noutput:\n{s}\n", .{ expected, stream.getWritten() });
            @panic("testRun failed");
        }
    }
}

fn print(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    for (js_args, 0..) |arg, i| {
        if (i != 0) std.debug.print(" ", .{});
        const str = try qjs.zig_utils.toString(ctx, arg);
        defer qjs.JS_FreeCString(ctx, str.ptr);
        std.debug.print("{s}", .{str});
    }
    std.debug.print("\n", .{});
    return qjs.zig_utils.values.undefined();
}
fn expect(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    for (js_args) |arg| {
        std.testing.expect(try qjs.zig_utils.castValue(bool, ctx, arg)) catch @panic("expect failed");
    }
    return null;
}
fn expectEql(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    if (!qjs.JS_IsStrictEqual(ctx, js_args[0], js_args[1])) {
        const str1 = try qjs.zig_utils.toString(ctx, js_args[0]);
        const str2 = try qjs.zig_utils.toString(ctx, js_args[1]);
        std.debug.print("op1:\n{s}\nop2:\n{s}\n", .{ str1, str2 });
        @panic("expectEql failed");
    }
    return null;
}

pub fn init(vexor: *Vexor) void {
    const global_this = qjs.JS_GetGlobalObject(vexor.ctx);
    defer qjs.JS_FreeValue(vexor.ctx, global_this);
    _ = qjs.zig_utils.setPropertyFunctionList(vexor.ctx, global_this, &[_]qjs.JSCFunctionListEntry{
        qjs.zig_utils.defFunc("print", 0, print),
        qjs.zig_utils.defFunc("expect", 0, expect),
        qjs.zig_utils.defFunc("expectEql", 2, expectEql),
    });
}
