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
        if (sh.read.option) |*option| {
            option.promise.reject(sh.ctx, errno(sh.ctx, uv.UV_ECANCELED));
            option.promise.free(sh.ctx);
        }
        smp_allocator.free(sh.read.data.mem);
    }

    fn close(_: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);
        sh.header.close(sh.handle);
        return null;
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
    const reuse_size: usize = if (@import("builtin").is_test) 2 else 32768;
    fn readAllocCallback(handle: [*c]uv.uv_handle_t, _: usize, buf: [*c]uv.uv_buf_t) callconv(.c) void {
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
        doReadResolve(sh, sh.read.data.mem[sh.read.data.buf.l .. sh.read.data.buf.l + len], &optional_obj) catch |err| {
            if (optional_obj) |obj| {
                sh.read.option.?.promise.reject(sh.ctx, obj);
            } else {
                sh.read.option.?.promise.reject(sh.ctx, qjs.JS_NewInternalError(sh.ctx, "%s", @errorName(err).ptr));
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
        // std.debug.print("readCb {}\n", .{result});
        const sh = uv.zig_utils.getData(StreamClass, handle);
        if (result <= 0) {
            if (result < 0) {
                sh.read.option.?.promise.reject(sh.ctx, errno(sh.ctx, @intCast(result)));
                sh.header.close(sh.handle);
            }
            return;
        }
        if (result == uv.UV_EOF) {
            readResolve(sh, sh.read.data.buf.r - sh.read.data.buf.l);
            sh.header.close(sh.handle);
            return;
        }
        const start_pos = sh.read.data.buf.r - sh.read.data.buf.l;
        sh.read.data.buf.r += @intCast(result);
        doReadCallback(sh, start_pos);
    }
    fn readFn(comptime read_mode: ReadMode, comptime read_type: ReadType) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);
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

                try check(ctx, uv.uv_read_start(sh.handle, &readAllocCallback, &readCallback));
                errdefer _ = uv.uv_read_stop(sh.handle);

                doReadCallback(sh, 0);

                return result;
            }
        }.func;
    }
    fn readLine(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const read = readFn(.until, .text);
        var js_args = [_]qjs.JSValue{qjs.zig_utils.newValue(ctx, @as(u8, '\n'))};
        return try read(ctx, this_obj, &js_args);
    }

    // write functions
    fn writable(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst) !?qjs.JSValue {
        const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);
        return qjs.zig_utils.newValue(ctx, uv.uv_is_writable(sh.handle) != 0);
    }
    const WriteHandle = struct {
        ctx: *qjs.JSContext,
        promise: qjs.zig_utils.Promise,
        req: uv.uv_write_t,
        type: WriteType,
        buf: uv.uv_buf_t,
    };
    const WriteType = enum {
        byte,
        text,
    };
    fn writeCallback(req: [*c]uv.uv_write_t, status: c_int) callconv(.c) void {
        const wh = uv.zig_utils.getData(WriteHandle, req);

        if (status == 0) {
            wh.promise.resolve(wh.ctx, null);
        }
        if (status < 0) {
            wh.promise.reject(wh.ctx, errno(wh.ctx, status));
        }

        wh.promise.free(wh.ctx);
        switch (wh.type) {
            .byte => smp_allocator.free(wh.buf.base[0..wh.buf.len]),
            .text => qjs.JS_FreeCString(wh.ctx, wh.buf.base),
        }
        smp_allocator.destroy(wh);
    }
    fn writeFn(comptime write_type: WriteType) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);

                const wh = try smp_allocator.create(WriteHandle);
                errdefer smp_allocator.destroy(wh);
                wh.ctx = ctx;
                wh.type = write_type;
                wh.req.data = wh;

                const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{qjs.JSValue});
                const buffer = switch (write_type) {
                    .byte => try qjs.zig_utils.toBuffer(ctx, args[0], smp_allocator),
                    .text => try qjs.zig_utils.toString(ctx, args[0]),
                };
                errdefer switch (write_type) {
                    .byte => smp_allocator.free(buffer),
                    .text => qjs.JS_FreeCString(ctx, buffer.ptr),
                };
                wh.buf = uv.zig_utils.initBuf(buffer);

                const result = try qjs.zig_utils.newPromise(ctx, &wh.promise);
                errdefer wh.promise.free(ctx);
                errdefer qjs.JS_FreeValue(ctx, result);

                try check(ctx, uv.uv_write(&wh.req, sh.handle, &wh.buf, 1, &writeCallback));

                return result;
            }
        }.func;
    }
    fn tryWriteFn(comptime write_type: WriteType) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                const sh = try qjs.zig_utils.getOpaque(StreamClass, this_obj);

                const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{qjs.JSValue});
                const buffer = switch (write_type) {
                    .byte => try qjs.zig_utils.getBuffer(ctx, args[0]),
                    .text => try qjs.zig_utils.toString(ctx, args[0]),
                };
                errdefer switch (write_type) {
                    .byte => {},
                    .text => qjs.JS_FreeCString(ctx, buffer.ptr),
                };

                const buf: uv.uv_buf_t = uv.zig_utils.initBuf(buffer);

                try check(ctx, uv.uv_try_write(sh.handle, &buf, 1));

                return null;
            }
        }.func;
    }
    pub const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("close", 0, close),
        qjs.zig_utils.defGetSet("readable", readable, null),
        qjs.zig_utils.defFunc("readOnce", 0, readFn(.once, .byte)),
        qjs.zig_utils.defFunc("readTextOnce", 0, readFn(.once, .text)),
        qjs.zig_utils.defFunc("read", 0, readFn(.fixed, .byte)),
        qjs.zig_utils.defFunc("readText", 0, readFn(.fixed, .text)),
        qjs.zig_utils.defFunc("readUntil", 0, readFn(.until, .byte)),
        qjs.zig_utils.defFunc("readTextUntil", 0, readFn(.until, .text)),
        qjs.zig_utils.defFunc("readLine", 0, readLine),
        qjs.zig_utils.defGetSet("writable", writable, null),
        qjs.zig_utils.defFunc("write", 0, writeFn(.byte)),
        qjs.zig_utils.defFunc("writeText", 0, writeFn(.text)),
        qjs.zig_utils.defFunc("tryWrite", 0, tryWriteFn(.byte)),
        qjs.zig_utils.defFunc("tryWriteText", 0, tryWriteFn(.text)),
    };
};

comptime {
    Vexor.UVDataHeader.check(StreamClass);
}
