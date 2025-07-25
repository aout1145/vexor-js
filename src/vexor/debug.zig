const std = @import("std");
const qjs = @import("qjs");

const Vexor = @import("./vexor.zig");

fn print(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
    for (js_args, 0..) |arg, i| {
        if (i != 0) std.debug.print(" ", .{});
        const str = qjs.JS_ToCString(ctx, arg);
        defer qjs.JS_FreeCString(ctx, str);
        std.debug.print("{s}", .{std.mem.span(str)});
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

pub fn init(vexor: *Vexor) void {
    const global_this = qjs.JS_GetGlobalObject(vexor.ctx);
    defer qjs.JS_FreeValue(vexor.ctx, global_this);
    qjs.zig_utils.setPropertyFunctionList(vexor.ctx, global_this, &[_]qjs.JSCFunctionListEntry{
        qjs.zig_utils.defFunc("print", 0, print),
        qjs.zig_utils.defFunc("expect", 0, expect),
    });
}
