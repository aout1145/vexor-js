const std = @import("std");
const c = @import("./c.zig");
const value = @import("./value.zig");

/// false means error occurred
pub fn executePendingJob(ctx: *c.JSContext) !bool {
    while (true) {
        var ctx1: ?*c.JSContext = undefined;
        const err = c.JS_ExecutePendingJob(c.JS_GetRuntime(ctx), &ctx1);
        if (err < 0) return false;
        if (err == 0) break;
    }
    return true;
}

pub fn dumpErrorVal(ctx: *c.JSContext, val: c.JSValueConst, writer: std.io.AnyWriter) !void {
    // error
    const str1 = c.JS_ToCString(ctx, val);
    defer if (str1 != null) c.JS_FreeCString(ctx, str1);
    try writer.print("Uncaught {s}\n", .{if (str1 != null) std.mem.span(str1) else "[exception]"});
    // stack
    if (c.JS_IsError(ctx, val)) {
        const stack = c.JS_GetPropertyStr(ctx, val, "stack");
        defer c.JS_FreeValue(ctx, stack);
        const str2 = c.JS_ToCString(ctx, stack);
        if (str2 != null) {
            try writer.print("{s}\n", .{std.mem.span(str2)});
            c.JS_FreeCString(ctx, str2);
        }
    }
}
pub fn dumpError(ctx: *c.JSContext, writer: std.io.AnyWriter) !void {
    const val = c.JS_GetException(ctx);
    defer c.JS_FreeValue(ctx, val);
    try dumpErrorVal(ctx, val, writer);
}
