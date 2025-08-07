const std = @import("std");
const c = @import("./c.zig");
const value = @import("./value.zig");

pub fn newModule(
    ctx: *c.JSContext,
    comptime name: []const u8,
    comptime func_defs: []const FuncDef,
    comptime class_defs: []const ClassDef,
    comptime value_defs: anytype,
) !*c.JSModuleDef {
    const init_func = struct {
        fn inner_func(ctx2: ?*c.JSContext, m: ?*c.JSModuleDef) callconv(.c) c_int {
            var ret: c_int = 0;
            inline for (class_defs) |def| {
                // register class & id
                var class_id: c.JSClassID = 0;
                _ = c.JS_NewClassID(c.JS_GetRuntime(ctx2), &class_id);
                ret |= c.JS_NewClass(c.JS_GetRuntime(ctx2), class_id, &std.mem.zeroInit(c.JSClassDef, .{
                    .class_name = def.name.ptr,
                    .finalizer = ClassDef.wrapFinalizer(def.finalizer),
                }));
                // create proto & constructor
                const proto = c.JS_NewObject(ctx2);
                ret |= c.JS_SetPropertyFunctionList(ctx2, proto, def.func_defs.ptr, def.func_defs.len);
                const constructor = c.JS_NewCFunction2(ctx2, value.wrapFunction(def.constructor), def.name.ptr, 0, c.JS_CFUNC_constructor, 0);
                c.JS_SetConstructor(ctx2, constructor, proto);
                c.JS_SetClassProto(ctx2, class_id, proto);
                ret |= c.JS_SetModuleExport(ctx2, m, def.name.ptr, constructor);
                // save class_id in constructor
                ret |= c.JS_DefinePropertyValueStr(ctx2, constructor, class_id_prop_name, value.newValue(ctx2.?, class_id), 0);
            }
            inline for (value_defs) |value_def| {
                inline for (comptime std.meta.fieldNames(@TypeOf(value_def))) |field_name| {
                    const val = value.newValue(ctx2.?, @field(value_def, field_name));
                    ret |= c.JS_SetModuleExport(ctx2, m, field_name, val);
                }
            }
            return ret | c.JS_SetModuleExportList(ctx2, m, func_defs.ptr, @intCast(func_defs.len));
        }
    }.inner_func;
    const optional_m = c.JS_NewCModule(ctx, name.ptr, &init_func);
    if (optional_m) |m| {
        inline for (class_defs) |def| {
            if (c.JS_AddModuleExport(ctx, m, def.name.ptr) != 0) {
                return error.FailedToAddExport;
            }
        }
        if (c.JS_AddModuleExportList(ctx, m, func_defs.ptr, @intCast(func_defs.len)) != 0) {
            return error.FailedToAddExportList;
        }
        inline for (value_defs) |value_def| {
            inline for (comptime std.meta.fieldNames(@TypeOf(value_def))) |field_name| {
                if (c.JS_AddModuleExport(ctx, m, field_name) != 0) {
                    return error.FailedToAddExport;
                }
            }
        }
        return m;
    } else {
        return error.FailedToCreateCModule;
    }
}
pub fn setPropertyFunctionList(ctx: *c.JSContext, obj: c.JSValue, comptime tab: []const FuncDef) c_int {
    return c.JS_SetPropertyFunctionList(ctx, obj, tab.ptr, @intCast(tab.len));
}

pub const class_id_prop_name = "__vexor_class_id__";
pub const ClassDef = struct {
    pub const Finalizer = fn (*c.JSRuntime, c.JSValueConst) void;
    pub const JSFinalizer = fn (rt: ?*c.JSRuntime, val: c.JSValueConst) callconv(.c) void;
    pub fn wrapFinalizer(finalizer: Finalizer) JSFinalizer {
        return struct {
            fn func(rt: ?*c.JSRuntime, val: c.JSValueConst) callconv(.c) void {
                finalizer(rt orelse unreachable, val);
            }
        }.func;
    }
    name: []const u8,
    constructor: value.Function,
    finalizer: Finalizer,
    func_defs: []const FuncDef,
};
pub fn getClassID(ctx: *c.JSContext, constructor: c.JSValueConst) !c.JSClassID {
    const prop = c.JS_GetPropertyStr(ctx, constructor, class_id_prop_name);
    defer c.JS_FreeValue(ctx, prop);
    return try value.castValue(c.JSClassID, ctx, prop);
}
pub fn newObjectFromConstructor(ctx: *c.JSContext, constructor: c.JSValueConst) !c.JSValue {
    const obj = c.JS_NewObjectClass(ctx, @intCast(try getClassID(ctx, constructor)));
    errdefer c.JS_FreeValue(ctx, obj);
    if (c.JS_IsException(obj)) return error.FailedToNewObjectClass;
    return obj;
}
pub fn defClass(comptime name: []const u8, constructor: value.Function, finalizer: ClassDef.Finalizer, func_defs: []const FuncDef) ClassDef {
    return .{
        .name = name,
        .constructor = constructor,
        .finalizer = finalizer,
        .func_defs = func_defs,
    };
}

pub const FuncDef = c.JSCFunctionListEntry;
pub fn defFunc(comptime name: []const u8, comptime length: u8, func: value.Function) FuncDef {
    return .{
        .name = name.ptr,
        .prop_flags = c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE,
        .def_type = c.JS_DEF_CFUNC,
        .magic = 0,
        .u = .{
            .func = .{
                .length = length,
                .cproto = c.JS_CFUNC_generic,
                .cfunc = .{
                    .generic = value.wrapFunction(func),
                },
            },
        },
    };
}
pub const Getter = fn (ctx: *c.JSContext, this_obj: c.JSValueConst) anyerror!?c.JSValue;
pub const JSGetter = fn (ctx: ?*c.JSContext, this_obj: c.JSValueConst) callconv(.c) c.JSValue;
pub const Setter = fn (ctx: *c.JSContext, this_obj: c.JSValueConst, val: c.JSValueConst) anyerror!?c.JSValue;
pub const JSSetter = fn (ctx: ?*c.JSContext, this_obj: c.JSValueConst, val: c.JSValueConst) callconv(.c) c.JSValue;
pub fn defGetSet(comptime name: []const u8, optional_getter: ?Getter, optional_setter: ?Setter) FuncDef {
    const js_getter = if (optional_getter) |getter| &struct {
        fn func(ctx: ?*c.JSContext, this_obj: c.JSValueConst) callconv(.c) c.JSValue {
            return value.wrapFunctionReturnValue(ctx, getter(ctx orelse unreachable, this_obj));
        }
    }.func else null;
    const js_setter = if (optional_setter) |setter| &struct {
        fn func(ctx: ?*c.JSContext, this_obj: c.JSValueConst, val: c.JSValueConst) callconv(.c) c.JSValue {
            return value.wrapFunctionReturnValue(ctx, setter(ctx orelse unreachable, this_obj, val));
        }
    }.func else null;
    return .{
        .name = name.ptr,
        .prop_flags = c.JS_PROP_CONFIGURABLE,
        .def_type = c.JS_DEF_CGETSET,
        .magic = 0,
        .u = .{
            .getset = .{
                .get = .{
                    .getter = js_getter,
                },
                .set = .{
                    .setter = js_setter,
                },
            },
        },
    };
}
