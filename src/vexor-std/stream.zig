const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const errno = @import("vexor").utils.uv.newErrno;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const StreamClass = struct {
    header: Vexor.UVDataHeader,
    ctx: *qjs.JSContext,
    handle: *uv.uv_stream_t,
    read: struct {
        data: struct {
            mem: []u8, // allocated buffer
            buf: struct { l: usize, r: usize }, // filled buffer
        },
        option: ?struct {
            mode: union(ReadMode) {
                once: void,
                fixed: usize,
                until: u8,
            },
            type: ReadType,
            promise: qjs.zig_utils.Promise,
        },
    },
    pub fn init(sh: *StreamClass, header: Vexor.UVDataHeader, ctx: *qjs.JSContext, handle: *uv.uv_stream_t) !void {
        sh.header = header;
        sh.ctx = ctx;
        sh.handle = handle;
        sh.read = .{
            .data = .{
                .mem = try smp_allocator.alloc(u8, 0),
                .buf = .{ .l = 0, .r = 0 },
            },
            .option = null,
        };
    }
    pub fn deinit(sh: *StreamClass) void {
        sh.read.option = null;
        smp_allocator.free(sh.read.data.mem);
    }

    // read functions
    fn readable(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst) !?qjs.JSValue {
        const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);
        return qjs.zig_utils.newValue(ctx, uv.uv_is_readable(sh.handle) != 0);
    }
    const ReadMode = enum {
        once,
        fixed,
        until,
    };
    const ReadType = enum {
        byte,
        text,
    };
    const alloc_size: usize = if (@import("builtin").is_test) 4 else 65536;
    const reuse_size: usize = if (@import("builtin").is_test) 1 else 4096;
    fn allocCallback(handle: [*c]uv.uv_handle_t, _: usize, buf: [*c]uv.uv_buf_t) callconv(.c) void {
        const sh = uv.zig_utils.getData(StreamClass, handle);
        const data = &sh.read.data;
        std.debug.assert(data.buf.r <= data.mem.len);
        if (data.buf.r == data.mem.len) {
            if (data.buf.l >= reuse_size) {
                std.mem.copyForwards(u8, data.mem, data.mem[data.buf.l..data.buf.r]);
                data.buf.r -= data.buf.l;
                data.buf.l = 0;
            } else if (smp_allocator.realloc(data.mem, data.mem.len + alloc_size)) |new_mem| {
                data.mem = new_mem;
            } else |_| {}
        }
        buf.* = .{
            .base = data.mem.ptr + data.buf.r,
            .len = data.mem.len - data.buf.r,
        };
    }
    fn doReadResolve(sh: *StreamClass, buf: []const u8, err: *?qjs.JSValue) !void {
        // std.debug.print("{any}\n", .{buf});
        const val = switch (sh.read.option.?.type) {
            .byte => qjs.JS_NewUint8ArrayCopy(sh.ctx, buf.ptr, buf.len),
            .text => qjs.JS_NewStringLen(sh.ctx, buf.ptr, buf.len),
        };
        if (qjs.JS_IsException(val)) {
            err.* = qjs.JS_GetException(sh.ctx);
            return error.FailedToNewUint8Array;
        }
        sh.read.option.?.promise.resolve(sh.ctx, val);
        sh.read.data.buf.l += buf.len;
    }
    fn readResolve(sh: *StreamClass, len: usize) void {
        var optional_obj: ?qjs.JSValue = undefined;
        doReadResolve(sh, sh.read.data.mem[sh.read.data.buf.l .. sh.read.data.buf.l + len], &optional_obj) catch {
            if (optional_obj) |obj| {
                sh.read.option.?.promise.reject(sh.ctx, obj);
            } else {
                // todo: reject a InternalError
                sh.read.option.?.promise.reject(sh.ctx, qjs.JS_NewError(sh.ctx));
            }
        };
        sh.read.option.?.promise.free(sh.ctx);
        sh.read.option = null;
        _ = uv.uv_read_stop(sh.handle);
    }
    fn doReadCallback(sh: *StreamClass, start_pos: usize) void {
        // start_pos: the start position of new data
        const data = sh.read.data;
        switch (sh.read.option.?.mode) {
            .once => if (data.buf.l != data.buf.r) {
                readResolve(sh, data.buf.r - data.buf.l);
            },
            .fixed => |len| if (data.buf.r - data.buf.l >= len) {
                readResolve(sh, len);
            },
            .until => |end_byte| for (data.mem[data.buf.l + start_pos ..], start_pos..) |byte, i| {
                if (end_byte == byte) {
                    readResolve(sh, i + 1); // include delimiter
                    break;
                }
            },
        }
    }
    fn readCallback(handle: [*c]uv.uv_stream_t, result: isize, _: [*c]const uv.uv_buf_t) callconv(.c) void {
        const sh = uv.zig_utils.getData(StreamClass, handle);
        if (result <= 0) {
            if (result < 0) {
                sh.read.option.?.promise.reject(
                    sh.ctx,
                    errno(sh.ctx, @intCast(result)) catch qjs.zig_utils.values.null(),
                );
            }
            return;
        }
        if (result == uv.UV_EOF) {
            readResolve(sh, sh.read.data.buf.r - sh.read.data.buf.l);
            return;
        }
        const start_pos = sh.read.data.buf.r - sh.read.data.buf.l;
        sh.read.data.buf.r += @intCast(result);
        doReadCallback(sh, start_pos);
    }
    fn readFn(comptime read_mode: ReadMode, comptime read_type: ReadType) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, this_val: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                const sh = try qjs.zig_utils.getOpaque(StreamClass, this_val);
                if (sh.read.option != null) {
                    try check(ctx, uv.UV_EALREADY);
                }

                errdefer sh.read.option = null;
                sh.read.option = .{
                    .mode = switch (read_mode) {
                        .once => .{ .once = {} },
                        .fixed => blk: {
                            const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{i32});
                            const length = args[0];
                            if (length <= 0) {
                                _ = qjs.JS_ThrowRangeError(ctx, "cannot be a negative");
                                return error.CannotBeNagetive;
                            }
                            break :blk .{ .fixed = @intCast(length) };
                        },
                        .until => blk: {
                            const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{i32});
                            const end_byte = args[0];
                            if (!(end_byte >= 0 and end_byte < 256)) {
                                _ = qjs.JS_ThrowRangeError(ctx, "not a byte");
                                return error.NotByte;
                            }
                            break :blk .{ .until = @intCast(end_byte) };
                        },
                    },
                    .type = read_type,
                    .promise = undefined,
                };

                const result = try qjs.zig_utils.newPromise(ctx, &sh.read.option.?.promise);
                errdefer {
                    sh.read.option.?.promise.free(ctx);
                    qjs.JS_FreeValue(ctx, result);
                }

                try check(ctx, uv.uv_read_start(sh.handle, &allocCallback, &readCallback));
                errdefer _ = uv.uv_read_stop(sh.handle);

                doReadCallback(sh, 0);

                return result;
            }
        }.func;
    }
    pub fn readLine(ctx: *qjs.JSContext, this_val: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const read = readFn(.until, .text);
        var js_args = [_]qjs.JSValue{qjs.zig_utils.newValue(ctx, @as(u8, '\n'))};
        return try read(ctx, this_val, &js_args);
    }

    pub const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defGetSet("readable", readable, null),
        qjs.zig_utils.defFunc("readOnce", 0, readFn(.once, .byte)),
        qjs.zig_utils.defFunc("readTextOnce", 0, readFn(.once, .text)),
        qjs.zig_utils.defFunc("read", 0, readFn(.fixed, .byte)),
        qjs.zig_utils.defFunc("readText", 0, readFn(.fixed, .text)),
        qjs.zig_utils.defFunc("readUntil", 0, readFn(.until, .byte)),
        qjs.zig_utils.defFunc("readTextUntil", 0, readFn(.until, .text)),
        qjs.zig_utils.defFunc("readLine", 0, readLine),
    };
};

comptime {
    Vexor.UVDataHeader.check(StreamClass);
}
