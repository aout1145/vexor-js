const std = @import("std");
const qjs = @import("qjs");
const uvc = @import("uv");

pub fn getVexor(ptr: anytype) *@import("./vexor.zig") {
    return @ptrCast(@alignCast(switch (@TypeOf(ptr)) {
        *qjs.JSRuntime => qjs.JS_GetRuntimeOpaque(ptr),
        *qjs.JSContext => qjs.JS_GetContextOpaque(ptr),
        else => @compileError("unsupported type"),
    }));
}

pub const uv = struct {
    fn newErrno2(ctx: *qjs.JSContext, err: c_int) !qjs.JSValue {
        const obj = qjs.JS_NewError(ctx);
        errdefer qjs.JS_FreeValue(ctx, obj);
        if (!qjs.JS_IsError(ctx, obj)) return error.FailedToNewError;
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "{s}: {s}", .{ std.mem.span(uvc.uv_err_name(err)), std.mem.span(uvc.uv_strerror(err)) });
        _ = qjs.JS_DefinePropertyValueStr(ctx, obj, "message", qjs.JS_NewStringLen(ctx, msg.ptr, msg.len), qjs.JS_PROP_WRITABLE | qjs.JS_PROP_CONFIGURABLE);
        _ = qjs.JS_DefinePropertyValueStr(ctx, obj, "code", qjs.JS_NewInt32(ctx, @intCast(err)), qjs.JS_PROP_WRITABLE | qjs.JS_PROP_CONFIGURABLE);
        return obj;
    }
    /// create a js error from uv errno
    pub fn newErrno(ctx: *qjs.JSContext, err: c_int) qjs.JSValue {
        return newErrno2(ctx, err) catch |e| qjs.JS_NewInternalError(ctx, "%s", @errorName(e).ptr);
    }
    pub fn checkThrow(ctx: *qjs.JSContext, err: c_int) !void {
        if (err < 0) {
            _ = qjs.JS_Throw(ctx, newErrno(ctx, err));
            return error.UVErrno;
        }
    }
};
