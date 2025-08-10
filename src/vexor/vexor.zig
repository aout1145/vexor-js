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
    is_closed: bool,

    pub fn init(close_cb: CloseCallback) UVDataHeader {
        return .{
            .close_cb = close_cb,
            .ref_count = 0,
            .is_closed = false,
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
    pub fn close(self: *UVDataHeader, handle: *anyopaque) void {
        const h: *uv.uv_handle_t = @ptrCast(@alignCast(handle));
        if (!self.is_closed and uv.uv_is_closing(h) == 0) {
            uv.uv_close(h, self.close_cb);
        }
    }
};

rt: *qjs.JSRuntime,
ctx: *qjs.JSContext,
loop: uv.uv_loop_t,
module_defs: std.StringHashMapUnmanaged([]const u8),
// init when run
check: uv.uv_check_t,
err_writer: ?std.io.AnyWriter,

pub fn init() !*Self {
    const self = try smp_allocator.create(Self);
    self.err_writer = null;
    self.module_defs = std.StringHashMapUnmanaged([]const u8){};

    self.rt = (if (@import("builtin").is_test) qjs.JS_NewRuntime2(&qjs.zig_utils.malloc_functions, @constCast(&std.testing.allocator)) else qjs.JS_NewRuntime()) orelse unreachable;
    errdefer qjs.JS_FreeRuntime(self.rt);
    self.ctx = qjs.JS_NewContext(self.rt) orelse unreachable;
    errdefer qjs.JS_FreeContext(self.ctx);

    if (@import("builtin").is_test) try uv.zig_utils.replaceAllocator(std.testing.allocator);
    const uvcheck = @import("uv").zig_utils.check;
    try uvcheck(uv.uv_loop_init(&self.loop));
    errdefer _ = uv.uv_loop_close(&self.loop);
    return self;
}

fn comptimeModuleLoader(ctx: ?*qjs.JSContext, _: [*c]const u8, _: ?*anyopaque) callconv(.c) ?*qjs.JSModuleDef {
    const obj = qjs.JS_Eval(ctx, "", 0, null, qjs.JS_EVAL_TYPE_MODULE | qjs.JS_EVAL_FLAG_COMPILE_ONLY);
    defer qjs.JS_FreeValue(ctx, obj);
    return @ptrCast(obj.u.ptr);
}
pub fn compile(self: *Self, str: []const u8, filename: ?[]const u8, strip: u8, output_writer: std.io.AnyWriter, err_writer: std.io.AnyWriter) !void {
    qjs.JS_SetModuleLoaderFunc(self.rt, null, comptimeModuleLoader, null);
    const obj = qjs.JS_Eval(
        self.ctx,
        str.ptr,
        str.len,
        (filename orelse "<unnamed>").ptr,
        qjs.JS_EVAL_TYPE_MODULE | qjs.JS_EVAL_FLAG_COMPILE_ONLY | qjs.JS_EVAL_FLAG_STRICT,
    );
    defer qjs.JS_FreeValue(self.ctx, obj);
    if (qjs.JS_IsException(obj)) {
        try qjs.zig_utils.dumpError(self.ctx, err_writer);
        return error.CompileError;
    } else {
        var flags = qjs.JS_WRITE_OBJ_BYTECODE;
        if (strip >= 1) {
            flags |= qjs.JS_WRITE_OBJ_STRIP_SOURCE;
            if (strip >= 2) {
                flags |= qjs.JS_WRITE_OBJ_STRIP_DEBUG;
            }
        }
        var len: usize = undefined;
        const buf = qjs.JS_WriteObject(self.ctx, &len, obj, flags);
        if (buf == null) {
            try qjs.zig_utils.dumpError(self.ctx, err_writer);
            return error.CompileError;
        }
        defer qjs.js_free(self.ctx, buf);
        try output_writer.writeAll(buf[0..len]);
    }
}

fn checkCallback(check: [*c]uv.uv_check_t) callconv(.c) void {
    // std.debug.print("checkCallback\n", .{});
    const self: *Self = @ptrCast(@alignCast(check.*.data));
    _ = qjs.zig_utils.executePendingJob(self.ctx) catch {};
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
        qjs.zig_utils.dumpErrorVal(ctx orelse unreachable, reason, self.err_writer.?) catch {};
        self.stop();
    }
}
fn moduleLoader(ctx: ?*qjs.JSContext, c_name: [*c]const u8, @"opaque": ?*anyopaque) callconv(.c) ?*qjs.JSModuleDef {
    const self: *Self = @ptrCast(@alignCast(@"opaque"));
    const name = std.mem.span(c_name);
    // std.debug.print("moduleLoader {s}\n", .{name});

    if (self.module_defs.get(name)) |bytecode| {
        const obj = qjs.JS_ReadObject(self.ctx, bytecode.ptr, bytecode.len, qjs.JS_READ_OBJ_BYTECODE);
        defer qjs.JS_FreeValue(ctx, obj);
        if (!qjs.JS_IsModule(obj)) {
            return null;
        }
        if (qjs.JS_ResolveModule(ctx, obj) != 0) {
            return null;
        }
        return @ptrCast(@alignCast(obj.u.ptr));
    }
    return null;
}
pub fn addModule(self: *Self, name: []const u8, bytecode: []const u8) !void {
    if (self.module_defs.contains(name))
        return error.ModuleExists;
    try self.module_defs.put(smp_allocator, name, bytecode);
}

fn runBytecodeObj(self: *Self, obj: qjs.JSValue, err_writer: std.io.AnyWriter) !void {
    self.err_writer = err_writer;
    defer self.err_writer = null;
    qjs.JS_SetRuntimeOpaque(self.rt, self);
    defer qjs.JS_SetRuntimeOpaque(self.rt, null);
    qjs.JS_SetContextOpaque(self.ctx, self);
    defer qjs.JS_SetContextOpaque(self.ctx, null);
    qjs.JS_SetHostPromiseRejectionTracker(self.rt, null, null);
    defer qjs.JS_SetHostPromiseRejectionTracker(self.rt, null, null);
    qjs.JS_SetModuleLoaderFunc(self.rt, null, moduleLoader, self);
    defer qjs.JS_SetModuleLoaderFunc(self.rt, null, null, null);
    self.loop.data = self;
    defer self.loop.data = null;

    const ret = qjs.JS_EvalFunction(self.ctx, obj);
    defer qjs.JS_FreeValue(self.ctx, ret);
    if (!qjs.JS_IsException(ret)) switch (qjs.JS_PromiseState(self.ctx, ret)) {
        // return value is a promise, so we get its result
        qjs.JS_PROMISE_FULFILLED, qjs.JS_PROMISE_REJECTED, qjs.JS_PROMISE_PENDING => |state| {
            if (state == qjs.JS_PROMISE_REJECTED) {
                const val = qjs.JS_PromiseResult(self.ctx, ret);
                defer qjs.JS_FreeValue(self.ctx, val);
                try qjs.zig_utils.dumpErrorVal(self.ctx, val, self.err_writer.?);
            }
            qjs.JS_SetHostPromiseRejectionTracker(self.rt, &promiseRejectionTracker, self);
            if (state == qjs.JS_PROMISE_PENDING) {
                _ = try qjs.zig_utils.executePendingJob(self.ctx);
            }
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
            // reset
            try uvcheck(uv.uv_tty_reset_mode());
        },
        else => unreachable,
    };
}
pub fn run(self: *Self, str: []const u8, filename: ?[]const u8, err_writer: std.io.AnyWriter) !void {
    qjs.JS_SetModuleLoaderFunc(self.rt, null, moduleLoader, self);
    defer qjs.JS_SetModuleLoaderFunc(self.rt, null, null, null);
    const obj = qjs.JS_Eval(
        self.ctx,
        str.ptr,
        str.len,
        (filename orelse "<unnamed>").ptr,
        qjs.JS_EVAL_TYPE_MODULE | qjs.JS_EVAL_FLAG_COMPILE_ONLY | qjs.JS_EVAL_FLAG_STRICT,
    );
    if (qjs.JS_IsException(obj)) {
        try qjs.zig_utils.dumpError(self.ctx, err_writer);
    } else {
        try self.runBytecodeObj(obj, err_writer);
    }
}
pub fn runBytecode(self: *Self, bytecode: []const u8, err_writer: std.io.AnyWriter) !void {
    const obj = qjs.JS_ReadObject(self.ctx, bytecode.ptr, bytecode.len, qjs.JS_READ_OBJ_BYTECODE);
    if (qjs.JS_IsException(obj)) {
        try qjs.zig_utils.dumpError(self.ctx, err_writer);
    } else {
        try self.runBytecodeObj(obj, err_writer);
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

    self.module_defs.deinit(smp_allocator);
    smp_allocator.destroy(self);
}

test run {
    const testRun = @import("./debug.zig").testRun;
    const vexor = try Self.init();
    defer vexor.deinit();
    try testRun(vexor, "", "");
    try testRun(vexor, "axy();", null);
}

test compile {
    const vexor = try Self.init();
    defer vexor.deinit();
    @import("./debug.zig").init(vexor);
    var buffer1: [65536]u8 = undefined;
    var buffer2: [65536]u8 = undefined;
    var bytecode_stream = std.io.fixedBufferStream(&buffer1);
    var error_stream = std.io.fixedBufferStream(&buffer2);
    try vexor.compile(
        \\let x = 1;
        \\x++;
        \\expectEql(x, 2);
    , null, 0, bytecode_stream.writer().any(), error_stream.writer().any());
    try vexor.runBytecode(bytecode_stream.getWritten(), error_stream.writer().any());
    if (error_stream.pos != 0) return error.Error;
}
