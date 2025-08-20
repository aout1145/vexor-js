const std = @import("std");
const c = @import("./c.zig");

// value utils
pub fn newValue(ctx: *c.JSContext, value: anytype) !c.JSValue {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .@"struct") {
        const obj = c.JS_NewObject(ctx);
        errdefer c.JS_FreeValue(ctx, obj);
        if (!c.JS_IsObject(obj)) return error.FailedToNewObject;
        inline for (comptime std.meta.fieldNames(T)) |field_name| {
            const val = try newValue(ctx, @field(value, field_name));
            errdefer c.JS_FreeValue(ctx, val);
            if (c.JS_SetPropertyStr(ctx, obj, field_name, val) == -1) {
                return error.FailedToSetPropertyStr;
            }
        }
        return obj;
    } else if (T == type and @typeInfo(value) == .@"enum") {
        const obj = c.JS_NewObject(ctx);
        errdefer c.JS_FreeValue(ctx, obj);
        if (!c.JS_IsObject(obj)) return error.FailedToNewObject;
        inline for (comptime std.meta.fields(value)) |field| {
            const val = try newValue(ctx, @as(i32, field.value));
            errdefer c.JS_FreeValue(ctx, val);
            if (c.JS_SetPropertyStr(ctx, obj, field.name, val) == -1) {
                return error.FailedToSetPropertyStr;
            }
        }
        return obj;
    } else return switch (T) {
        i8, i16, i32, c_int => c.JS_NewInt32(ctx, value),
        u8, u16, u32, c_uint => c.JS_NewUint32(ctx, value),
        i64 => c.JS_NewInt64(ctx, value),
        u64, usize, isize, c_long, c_ulong => c.JS_NewInt64(ctx, @intCast(value)),
        f32, f64 => c.JS_NewFloat64(ctx, value),
        bool => .{ // marco translated wrongly
            .u = .{ .int32 = @intFromBool(value) },
            .tag = c.JS_TAG_BOOL,
        },
        []const u8, []u8, [:0]const u8, [:0]u8 => blk: {
            const obj = c.JS_NewStringLen(ctx, value.ptr, value.len);
            errdefer c.JS_FreeValue(ctx, obj);
            if (!c.JS_IsString(obj)) break :blk error.FailedToNewStringLen;
            break :blk obj;
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    };
}
/// an exception will be thrown when a error returned
/// if T==JSValue, it will NOT increase ref
pub fn castValue(T: type, ctx: *c.JSContext, val: c.JSValueConst) !T {
    const check = struct {
        fn check(ret: c_int) !void {
            if (ret != 0) return error.FailedToCastValue;
        }
    }.check;
    switch (@typeInfo(T)) {
        .int, .float => {
            if (!c.JS_IsNumber(val)) {
                _ = c.JS_ThrowTypeError(ctx, "not a number");
                return error.NotANumber;
            }
            var ret: T = undefined;
            switch (T) {
                i32, c_int => try check(c.JS_ToInt32(ctx, &ret, val)),
                u32, c_uint => try check(c.JS_ToUint32(ctx, &ret, val)),
                i64 => try check(c.JS_ToInt64(ctx, &ret, val)),
                f64 => try check(c.JS_ToFloat64(ctx, &ret, val)),
                else => @compileError("unsupported type: " ++ @typeName(T)),
            }
            return ret;
        },
        else => switch (T) {
            bool => {
                if (!c.JS_IsBool(val)) {
                    _ = c.JS_ThrowTypeError(ctx, "not a boolean");
                    return error.NotABool;
                }
                return c.JS_ToBool(ctx, val) != 0;
            },
            c.JSValue => {
                return val;
            },
            else => @compileError("unsupported type: " ++ @typeName(T)),
        },
    }
}
pub fn toString(ctx: *c.JSContext, val: c.JSValueConst) ![]const u8 {
    var len: usize = undefined;
    const ptr = c.JS_ToCStringLen(ctx, &len, val);
    if (ptr) |str| {
        return str[0..len];
    } else {
        return error.FailedToCStringLen;
    }
}
pub fn getBuffer(ctx: *c.JSContext, val: c.JSValueConst) ![]const u8 {
    var obj = val;
    if (!c.JS_IsArrayBuffer(obj)) {
        obj = c.JS_GetPropertyStr(ctx, obj, "buffer");
        c.JS_FreeValue(ctx, obj);
    }
    if (!c.JS_IsArrayBuffer(obj)) {
        _ = c.JS_ThrowTypeError(ctx, "not a ArrayBuffer");
        return error.NotArrayBufferOrDataView;
    }
    var len: usize = undefined;
    const cbuf = c.JS_GetArrayBuffer(ctx, &len, obj);
    return cbuf[0..len];
}
pub fn toBuffer(ctx: *c.JSContext, val: c.JSValueConst, allocator: std.mem.Allocator) ![]const u8 {
    const cbuf = try getBuffer(ctx, val);
    const buf = try allocator.alloc(u8, cbuf.len);
    @memcpy(buf, cbuf);
    return buf;
}

// opaque utils
pub fn getOpaque(T: type, obj: c.JSValueConst) ?*T {
    var class_id: c.JSClassID = undefined;
    return @ptrCast(@alignCast(c.JS_GetAnyOpaque(obj, &class_id)));
}
/// set opaque only after a object created successfully
/// or may cause double free (from constructor & finalizer)
pub fn setOpaque(obj: c.JSValueConst, @"opaque": ?*anyopaque) !void {
    if (c.JS_SetOpaque(obj, @"opaque") != 0) {
        return error.FailedToSetOpaque;
    }
}

// property utils
pub fn getProperty(T: type, ctx: *c.JSContext, this_obj: c.JSValueConst, prop: []const u8) !?T {
    const val = c.JS_GetPropertyStr(ctx, this_obj, prop.ptr);
    errdefer c.JS_FreeValue(ctx, val);
    if (c.JS_IsNull(val) or c.JS_IsUndefined(val)) return null;
    return try castValue(T, ctx, val);
}

// function utils
pub const Function = fn (*c.JSContext, c.JSValueConst, []c.JSValueConst) anyerror!?c.JSValue;
pub const JSFunction = fn (ctx: ?*c.JSContext, this_obj: c.JSValueConst, argc: c_int, argv: [*c]c.JSValueConst) callconv(.c) c.JSValue;
/// an undefined will be returned when a null is returned
/// an exception will be thrown when an error is returned without exception thrown
pub fn wrapFunctionReturnValue(ctx: ?*c.JSContext, value: anyerror!?c.JSValue) c.JSValue {
    if (value) |ret| {
        return ret orelse values.undefined();
    } else |err| {
        if (!c.JS_HasException(ctx.?)) {
            if (err == std.mem.Allocator.Error.OutOfMemory) {
                return c.JS_ThrowOutOfMemory(ctx.?);
            } else {
                return c.JS_ThrowInternalError(ctx.?, "%s", @errorName(err).ptr);
            }
        } else {
            return values.exception();
        }
    }
}
pub fn wrapFunction(func: Function) JSFunction {
    return struct {
        fn js_func(ctx: ?*c.JSContext, this_obj: c.JSValueConst, argc: c_int, argv: [*c]c.JSValueConst) callconv(.c) c.JSValue {
            if (argc != 0) {
                return wrapFunctionReturnValue(ctx, func(ctx orelse unreachable, this_obj, argv[0..@intCast(argc)]));
            } else {
                return wrapFunctionReturnValue(ctx, func(ctx orelse unreachable, this_obj, &[0]c.JSValueConst{}));
            }
        }
    }.js_func;
}
pub fn newFunction(arg_ctx: *c.JSContext, func: Function, cproto: comptime_int, comptime name: ?[]const u8) c.JSValue {
    // why couldn't add a function to get symbol name?
    const symname: []const u8 = name orelse ("[0x" ++ std.fmt.hex(@bitReverse(@intFromPtr(&func))) ++ "]");
    return c.JS_NewCFunction2(arg_ctx, &wrapFunction(func), symname.ptr, 0, cproto, 0);
}

pub fn throwTooFewArgs(ctx: *c.JSContext, min_args: usize, passed_args: usize) c.JSValue {
    return c.JS_ThrowReferenceError(ctx, "at least %d arguments required, but %d passed", min_args, passed_args);
}
fn removeOptional(T: type) type {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .optional => |optional| optional.child,
        else => T,
    };
}
pub fn getArgs(ctx: *c.JSContext, js_args: []c.JSValueConst, types: []const type) !std.meta.Tuple(types) {
    var args: std.meta.Tuple(types) = undefined;
    var min_args: usize = 0;
    inline for (types) |T| {
        if (@typeInfo(T) == .optional) break;
        min_args += 1;
    }
    if (js_args.len < min_args) {
        _ = throwTooFewArgs(ctx, min_args, js_args.len);
        return error.TooFewArgumentsPassed;
    }
    var casted_args: usize = 0;
    errdefer inline for (types, 0..) |T, i| {
        if (i == casted_args) break;
        if (removeOptional(T) == []const u8) {
            if (args[i]) |str| {
                c.JS_FreeCString(ctx, str.ptr);
            }
        }
    };
    inline for (types, 0..) |T, i| {
        if (i < js_args.len) {
            args[i] = try castValue(removeOptional(T), ctx, js_args[i]);
        } else if (@typeInfo(T) == .optional) {
            args[i] = null;
        } else unreachable;
        casted_args += 1;
    }
    return args;
}

// promise utils
pub const Promise = struct {
    resolve_func: c.JSValue,
    reject_func: c.JSValue,
    backtrace: ?c.JSValue,
    is_freed: bool,
    pub fn free(self: *Promise, ctx: *c.JSContext) void {
        if (self.is_freed) return;
        self.is_freed = true;
        c.JS_FreeValue(ctx, self.resolve_func);
        c.JS_FreeValue(ctx, self.reject_func);
        if (self.backtrace) |backtrace| c.JS_FreeValue(ctx, backtrace);
    }
    /// val will be released
    /// JS_EXCEPTION is allowed to pass
    pub fn resolve(self: *Promise, ctx: *c.JSContext, error_optional_val: ?anyerror!c.JSValue) void {
        std.debug.assert(self.is_freed == false);
        var ret: c.JSValue = undefined;
        defer c.JS_FreeValue(ctx, ret);
        if (error_optional_val) |error_val| {
            if (error_val) |val| {
                defer c.JS_FreeValue(ctx, val);
                if (!c.JS_IsException(val)) {
                    ret = c.JS_Call(ctx, self.resolve_func, values.undefined(), 1, @constCast(@ptrCast(&val)));
                } else {
                    @branchHint(.unlikely);
                    var obj: c.JSValue = undefined;
                    defer c.JS_FreeValue(ctx, obj);
                    if (c.JS_HasException(ctx)) {
                        obj = c.JS_GetException(ctx);
                    } else {
                        obj = c.JS_NewInternalError(ctx, "FailedToResolvePromise");
                    }
                    ret = c.JS_Call(ctx, self.reject_func, values.undefined(), 1, @constCast(@ptrCast(&obj)));
                }
            } else |e| {
                @branchHint(.unlikely);
                var obj: c.JSValue = undefined;
                defer c.JS_FreeValue(ctx, obj);
                if (c.JS_HasException(ctx)) {
                    obj = c.JS_GetException(ctx);
                } else {
                    obj = c.JS_NewInternalError(ctx, "%s", @errorName(e).ptr);
                }
                ret = c.JS_Call(ctx, self.reject_func, values.undefined(), 1, @constCast(@ptrCast(&obj)));
            }
        } else {
            ret = c.JS_Call(ctx, self.resolve_func, values.undefined(), 0, null);
        }
        self.free(ctx);
    }
    /// val will be released
    pub fn reject(self: *Promise, ctx: *c.JSContext, val: c.JSValue) void {
        std.debug.assert(self.is_freed == false);
        defer c.JS_FreeValue(ctx, val);
        _ = c.JS_SetPropertyStr(ctx, val, "stack", self.backtrace.?);
        self.backtrace = null;
        const ret = c.JS_Call(ctx, self.reject_func, values.undefined(), 1, @constCast(@ptrCast(&val)));
        defer c.JS_FreeValue(ctx, ret);
        self.free(ctx);
    }
};
pub fn newPromise(ctx: *c.JSContext, promise: *Promise) !c.JSValue {
    var resolving_funcs: [2]c.JSValue = undefined;
    errdefer {
        c.JS_FreeValue(ctx, resolving_funcs[0]);
        c.JS_FreeValue(ctx, resolving_funcs[1]);
    }
    const result_promise = c.JS_NewPromiseCapability(ctx, &resolving_funcs);
    if (!c.JS_IsPromise(result_promise)) return error.FailedToNewPromiseCapability;
    promise.* = .{
        .resolve_func = resolving_funcs[0],
        .reject_func = resolving_funcs[1],
        .backtrace = try getStacktrace(ctx),
        .is_freed = false,
    };
    return result_promise;
}
pub fn getStacktrace(ctx: *c.JSContext) !c.JSValue {
    const err_obj = c.JS_NewError(ctx);
    defer c.JS_FreeValue(ctx, err_obj);
    if (!c.JS_IsError(ctx, err_obj)) return error.FailedToNewError;
    const backtrace = c.JS_GetPropertyStr(ctx, err_obj, "stack");
    errdefer c.JS_FreeValue(ctx, backtrace);
    return backtrace;
}

// special value utils
pub const values = struct {
    fn JS_MKVAL(tag: i64, val: i32) c.JSValue {
        return .{
            .u = .{ .int32 = val },
            .tag = tag,
        };
    }
    pub fn @"undefined"() c.JSValue {
        return JS_MKVAL(c.JS_TAG_UNDEFINED, 0);
    }
    pub fn exception() c.JSValue {
        return JS_MKVAL(c.JS_TAG_EXCEPTION, 0);
    }
    pub fn @"null"() c.JSValue {
        return JS_MKVAL(c.JS_TAG_NULL, 0);
    }
};
