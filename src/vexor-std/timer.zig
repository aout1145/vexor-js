const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:timer";
const internal_name = "std:internal:timer";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        internal_name,
        &SleepHandle.func_defs,
        &TimerClass.class_defs,
        .{},
    );
    try vexor.addModule(module_name, @embedFile("timer.js.compiled"));
}

const SleepHandle = struct {
    header: Vexor.UVDataHeader,
    ctx: *qjs.JSContext,
    promise: qjs.zig_utils.Promise,
    handle: uv.uv_timer_t,

    fn closeCallback(handle: [*c]uv.uv_handle_t) callconv(.c) void {
        const sh = uv.zig_utils.getData(SleepHandle, handle);
        sh.promise.free(sh.ctx);
        smp_allocator.destroy(sh);
    }
    fn callback(handle: [*c]uv.uv_timer_t) callconv(.c) void {
        const sh = uv.zig_utils.getData(SleepHandle, handle);
        const vexor = getVexor(sh.ctx);

        _ = qjs.zig_utils.executePendingJob(vexor.ctx) catch {};

        sh.promise.resolve(sh.ctx, null);

        uv.uv_close(@ptrCast(&sh.handle), &closeCallback);
    }
    fn sleep(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{i32});
        const delay = args[0];
        if (delay < 0) return qjs.JS_ThrowRangeError(ctx, "cannot be a negative");

        const sh = try smp_allocator.create(SleepHandle);
        errdefer smp_allocator.destroy(sh);
        sh.ctx = ctx;
        sh.header = .init(&closeCallback);

        const result = try qjs.zig_utils.newPromise(ctx, &sh.promise);
        errdefer sh.promise.free(ctx);
        errdefer qjs.JS_FreeValue(ctx, result);

        try check(ctx, uv.uv_timer_init(&vexor.loop, &sh.handle));
        errdefer uv.uv_close(@ptrCast(&sh.handle), null);
        sh.handle.data = sh;
        try check(ctx, uv.uv_timer_start(&sh.handle, &callback, @intCast(delay), 0));

        return result;
    }

    const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("sleep", 0, SleepHandle.sleep),
    };
};

comptime {
    Vexor.UVDataHeader.check(SleepHandle);
}

test SleepHandle {
    const testRun = @import("vexor").debug.testRun;

    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);
    try testRun(vexor,
        \\import { sleep } from 'std:timer';
        \\await sleep(1);
    , "");
    try testRun(vexor,
        \\import { sleep } from 'std:timer';
        \\try {
        \\  await sleep(-1);
        \\} catch (e) {
        \\  expect(e instanceof RangeError);
        \\}
    , "");
    try testRun(vexor,
        \\import { sleep } from 'std:timer';
        \\const awaiter = sleep(1);
        \\throw new Error();
        \\await awaiter;
    , null);
}

const TimerClass = struct {
    header: Vexor.UVDataHeader,
    ctx: *qjs.JSContext,
    handle: uv.uv_timer_t,
    obj: qjs.JSValue,
    func: qjs.JSValue,

    fn closeCallback(handle: [*c]uv.uv_handle_t) callconv(.c) void {
        const th = uv.zig_utils.getData(TimerClass, handle);
        qjs.JS_FreeValue(th.ctx, th.func);
        qjs.JS_FreeValue(th.ctx, th.obj);
        th.header.unref(TimerClass, smp_allocator);
    }
    fn close(_: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const th = try qjs.zig_utils.getOpaque(TimerClass, this_obj);
        uv.uv_close(@ptrCast(&th.handle), &closeCallback);
        return null;
    }
    fn callback(handle: [*c]uv.uv_timer_t) callconv(.c) void {
        const th = uv.zig_utils.getData(TimerClass, handle);
        const vexor = getVexor(th.ctx);

        _ = qjs.zig_utils.executePendingJob(vexor.ctx) catch {};

        const ret = qjs.JS_Call(th.ctx, th.func, th.obj, 0, null);
        defer qjs.JS_FreeValue(th.ctx, ret);
        if (qjs.JS_IsException(ret)) {
            qjs.zig_utils.dumpError(th.ctx, vexor.err_writer.?) catch {};
            vexor.stop();
        }

        if (uv.uv_timer_get_repeat(handle) == 0) {
            uv.uv_close(@ptrCast(&th.handle), &closeCallback);
        }
    }
    fn constructor(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);

        const func, const delay, const optional_options = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ qjs.JSValueConst, i32, ?qjs.JSValueConst });
        if (delay < 0) return qjs.JS_ThrowRangeError(ctx, "cannot be a negative");
        if (!qjs.JS_IsFunction(ctx, func)) return qjs.JS_ThrowTypeError(ctx, "not a function");
        var is_repeat, var is_daemon = .{ true, false };
        if (optional_options) |options| {
            if (!qjs.JS_IsObject(options)) return qjs.JS_ThrowTypeError(ctx, "not an object");
            if (try qjs.zig_utils.getProperty(bool, ctx, options, "repeat")) |val| {
                is_repeat = val;
            }
            if (try qjs.zig_utils.getProperty(bool, ctx, options, "daemon")) |val| {
                is_daemon = val;
            }
        }

        const th = try smp_allocator.create(TimerClass);
        errdefer smp_allocator.destroy(th);
        th.ctx = ctx;
        th.header = .init(&closeCallback);
        th.obj = qjs.JS_DupValue(ctx, this_obj);
        errdefer qjs.JS_FreeValue(ctx, th.obj);
        th.func = qjs.JS_DupValue(ctx, func);
        errdefer qjs.JS_FreeValue(ctx, th.func);

        try check(ctx, uv.uv_timer_init(&vexor.loop, &th.handle));
        errdefer uv.uv_close(@ptrCast(&th.handle), null);
        if (is_daemon) uv.uv_unref(@ptrCast(&th.handle));
        try check(ctx, uv.uv_timer_start(&th.handle, callback, @intCast(delay), @intCast(if (is_repeat) delay else 0)));

        try qjs.zig_utils.setOpaque(this_obj, th.header.ref(TimerClass));
        th.handle.data = th.header.ref(TimerClass);

        return null;
    }
    fn finalizer(_: *qjs.JSRuntime, this_obj: qjs.JSValueConst) void {
        const th = qjs.zig_utils.getOpaque(TimerClass, this_obj) catch unreachable;
        th.header.unref(TimerClass, smp_allocator);
    }

    const class_defs = [_]qjs.zig_utils.ClassDef{
        qjs.zig_utils.defClass("Timer", TimerClass.constructor, TimerClass.finalizer, &[_]qjs.zig_utils.FuncDef{
            qjs.zig_utils.defFunc("close", 0, TimerClass.close),
        }),
    };
};

comptime {
    Vexor.UVDataHeader.check(TimerClass);
}

test TimerClass {
    const testRun = @import("vexor").debug.testRun;

    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);
    try testRun(vexor,
        \\import { setTimer } from 'std:timer';
        \\var count = 0;
        \\setTimer(() => {
        \\  expectEql(count, 0);
        \\  count++;
        \\}, 1, { repeat: false });
    , "");
    try testRun(vexor,
        \\import { setTimer } from 'std:timer';
        \\var count = 0;
        \\const timer = setTimer(() => {
        \\  timer.close(); 
        \\  expectEql(count, 0);
        \\  count++;
        \\}, 1);
    , "");
    try testRun(vexor,
        \\import { setTimer } from 'std:timer';
        \\setTimer(() => {}, 1, { daemon: true });
    , "");
    try testRun(vexor,
        \\import { setTimer } from 'std:timer';
        \\setTimer(() => { throw new Error(); }, 1);
    , null);
}
