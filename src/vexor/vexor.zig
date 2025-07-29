const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Self = @This();

pub const smp_allocator = if (@import("builtin").is_test) std.testing.allocator else std.heap.smp_allocator;

/// to ensure uv handles to be released safely
/// the header should be the first field
pub const UVDataHeader = struct {
    pub const CloseCallback = *const fn (handle: [*c]uv.uv_handle_t) callconv(.c) void;
    close_cb: CloseCallback,
    ref_count: u8,

    pub fn init(close_cb: CloseCallback) UVDataHeader {
        return .{
            .close_cb = close_cb,
            .ref_count = 0,
        };
    }
    pub fn check(comptime T: type) void {
        inline for (std.meta.fields(T)) |field| {
            if (@offsetOf(T, field.name) == 0) {
                if (field.type == UVDataHeader) {
                    // do nothing
                } else if (@typeInfo(field.type) == .@"struct") {
                    check(field.type);
                } else {
                    @compileError(@typeName(T) ++ " does not have a UVDataHeader field firstly");
                }
                return;
            }
        }
        comptime unreachable;
    }
    pub fn ref(self: *UVDataHeader, T: type) *T {
        self.ref_count += 1;
        return @ptrCast(@alignCast(self));
    }
    pub fn unref(self: *UVDataHeader, T: type, allocator: std.mem.Allocator) void {
        std.debug.assert(self.ref_count > 0);
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            const ptr: *T = @ptrCast(@alignCast(self));
            allocator.destroy(ptr);
        }
    }
};

rt: *qjs.JSRuntime,
ctx: *qjs.JSContext,
loop: uv.uv_loop_t,
check: uv.uv_check_t,
err_writer: std.io.AnyWriter,

pub fn init() !*Self {
    const self = try smp_allocator.create(Self);
    self.rt = (if (@import("builtin").is_test) qjs.JS_NewRuntime2(&qjs.zig_utils.malloc_functions, @constCast(&std.testing.allocator)) else qjs.JS_NewRuntime()) orelse unreachable;
    errdefer qjs.JS_FreeRuntime(self.rt);
    self.ctx = qjs.JS_NewContext(self.rt) orelse unreachable;
    errdefer qjs.JS_FreeContext(self.ctx);

    const uvcheck = @import("uv").zig_utils.check;
    try uvcheck(uv.uv_loop_init(&self.loop));
    errdefer _ = uv.uv_loop_close(&self.loop);
    return self;
}

fn checkCallback(check: [*c]uv.uv_check_t) callconv(.c) void {
    // std.debug.print("checkCallback\n", .{});
    const self: *Self = @ptrCast(@alignCast(check.*.data));
    if (!(qjs.zig_utils.executePendingJob(self.ctx, self.err_writer) catch false)) {
        self.stop();
    }
}
fn walkCallback(handle: [*c]uv.uv_handle_t, _: ?*anyopaque) callconv(.c) void {
    // std.debug.print("walkCallback\n", .{});
    const header: *UVDataHeader = @ptrCast(@alignCast(handle.*.data));
    if (uv.uv_is_closing(handle) == 0) {
        uv.uv_close(handle, header.close_cb);
    }
}
fn promiseRejectionTracker(ctx: ?*qjs.JSContext, _: qjs.JSValueConst, reason: qjs.JSValueConst, is_handled: bool, @"opaque": ?*anyopaque) callconv(.c) void {
    // std.debug.print("promiseRejectionTracker {}\n", .{is_handled});
    const self: *Self = @ptrCast(@alignCast(@"opaque"));
    if (!is_handled) {
        qjs.zig_utils.dumpErrorVal(ctx orelse unreachable, reason, self.err_writer) catch {};
        self.stop();
    }
}
pub fn run(self: *Self, str: []const u8, filename: ?[]const u8, err_writer: ?std.io.AnyWriter) !void {
    self.err_writer = err_writer orelse (if (@import("builtin").is_test) std.io.null_writer.any() else std.io.getStdErr().writer().any());
    qjs.JS_SetRuntimeOpaque(self.rt, self);
    qjs.JS_SetContextOpaque(self.ctx, self);
    qjs.JS_SetHostPromiseRejectionTracker(self.rt, &promiseRejectionTracker, self);
    self.loop.data = self;

    var ret = qjs.JS_Eval(
        self.ctx,
        str.ptr,
        str.len,
        (filename orelse "<unnamed>").ptr,
        qjs.JS_EVAL_TYPE_MODULE | qjs.JS_EVAL_FLAG_COMPILE_ONLY | qjs.JS_EVAL_FLAG_STRICT,
    );
    defer qjs.JS_FreeValue(self.ctx, ret);
    if (!qjs.JS_IsException(ret)) {
        ret = qjs.JS_EvalFunction(self.ctx, ret);
    }
    if (qjs.JS_IsException(ret)) {
        try qjs.zig_utils.dumpError(self.ctx, self.err_writer);
    } else switch (qjs.JS_PromiseState(self.ctx, ret)) {
        // return value is a promise, so we get its result
        qjs.JS_PROMISE_FULFILLED, qjs.JS_PROMISE_PENDING => {
            if (try qjs.zig_utils.executePendingJob(self.ctx, self.err_writer)) {
                const uvcheck = @import("uv").zig_utils.check;
                // init uv check
                try uvcheck(uv.uv_check_init(&self.loop, &self.check));
                errdefer _ = uv.uv_close(@ptrCast(&self.check), null);
                try uvcheck(uv.uv_check_start(&self.check, &checkCallback));
                uv.uv_unref(@ptrCast(&self.check)); // avoid blocking event loop stop
                self.check.data = self;
                // start event loop
                try uvcheck(uv.uv_run(&self.loop, uv.UV_RUN_DEFAULT));
                // release handles
                uv.uv_close(@ptrCast(&self.check), null);
                uv.uv_walk(&self.loop, walkCallback, self);
                try uvcheck(uv.uv_run(&self.loop, uv.UV_RUN_NOWAIT));
            }
        },
        qjs.JS_PROMISE_REJECTED => {
            const val = qjs.JS_PromiseResult(self.ctx, ret);
            defer qjs.JS_FreeValue(self.ctx, val);
            try qjs.zig_utils.dumpErrorVal(self.ctx, val, self.err_writer);
        },
        else => unreachable,
    }
}

/// if event loop is not running, result is undefined
pub fn stop(self: *Self) void {
    uv.uv_stop(&self.loop);
}

pub fn deinit(self: *Self) void {
    const err = uv.uv_loop_close(&self.loop);
    if (@import("builtin").is_test and err < 0) {
        uv.uv_print_all_handles(&self.loop, uv.stderr);
        @panic("uv handles leak");
    }

    qjs.JS_FreeContext(self.ctx);
    qjs.JS_FreeRuntime(self.rt);

    smp_allocator.destroy(self);
}

test Self {
    const vexor = try Self.init();
    defer vexor.deinit();
    try vexor.run("", null, null);
    try vexor.run("){}};", null, null);
}
