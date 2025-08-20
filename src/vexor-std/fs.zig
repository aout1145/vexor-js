const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

// fix fucking loop dependency bug
const uv_fix = struct {
    const uv_loop_t = uv.uv_loop_t;
    const uv_fs_t = uv.uv_fs_t;
    const uv_file = uv.uv_file;
    const uv_fs_cb = *const anyopaque;
    const uv_buf_t = uv.uv_buf_t;
    const uv_dirent_t = uv.uv_dirent_t;
    const uv_dir_t = uv.uv_dir_t;
    const uv_uid_t = uv.uv_uid_t;
    const uv_gid_t = uv.uv_gid_t;
    // following copy from uv.h
    pub extern fn uv_fs_close(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_open(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, flags: c_int, mode: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_read(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, bufs: [*c]const uv_buf_t, nbufs: c_uint, offset: i64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_unlink(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_write(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, bufs: [*c]const uv_buf_t, nbufs: c_uint, offset: i64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_copyfile(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, new_path: [*c]const u8, flags: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_mkdir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, mode: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_mkdtemp(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, tpl: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_mkstemp(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, tpl: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_rmdir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_scandir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, flags: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_scandir_next(req: [*c]uv_fs_t, ent: [*c]uv_dirent_t) c_int;
    pub extern fn uv_fs_opendir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_readdir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, dir: [*c]uv_dir_t, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_closedir(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, dir: [*c]uv_dir_t, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_stat(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_fstat(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_rename(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, new_path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_fsync(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_fdatasync(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_ftruncate(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, offset: i64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_sendfile(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, out_fd: uv_file, in_fd: uv_file, in_offset: i64, length: usize, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_access(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, mode: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_chmod(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, mode: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_utime(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, atime: f64, mtime: f64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_futime(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, atime: f64, mtime: f64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_lutime(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, atime: f64, mtime: f64, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_lstat(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_link(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, new_path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_symlink(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, new_path: [*c]const u8, flags: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_readlink(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_realpath(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_fchmod(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, mode: c_int, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_chown(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, uid: uv_uid_t, gid: uv_gid_t, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_fchown(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, file: uv_file, uid: uv_uid_t, gid: uv_gid_t, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_lchown(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, uid: uv_uid_t, gid: uv_gid_t, cb: uv_fs_cb) c_int;
    pub extern fn uv_fs_statfs(loop: [*c]uv_loop_t, req: [*c]uv_fs_t, path: [*c]const u8, cb: uv_fs_cb) c_int;
};
fn makeStat(statbuf: uv.uv_stat_t) struct {
    dev: u64,
    mode: u64,
    nlink: u64,
    uid: u64,
    gid: u64,
    rdev: u64,
    ino: u64,
    size: u64,
    blksize: u64,
    blocks: u64,
    flags: u64,
    gen: u64,
    atime: struct { sec: c_long, nsec: c_long },
    mtime: struct { sec: c_long, nsec: c_long },
    ctime: struct { sec: c_long, nsec: c_long },
    birthtime: struct { sec: c_long, nsec: c_long },
} {
    return .{
        .dev = statbuf.st_dev,
        .mode = statbuf.st_mode,
        .nlink = statbuf.st_nlink,
        .uid = statbuf.st_uid,
        .gid = statbuf.st_gid,
        .rdev = statbuf.st_rdev,
        .ino = statbuf.st_ino,
        .size = statbuf.st_size,
        .blksize = statbuf.st_blksize,
        .blocks = statbuf.st_blocks,
        .flags = statbuf.st_flags,
        .gen = statbuf.st_gen,
        .atime = .{
            .sec = statbuf.st_atim.tv_sec,
            .nsec = statbuf.st_atim.tv_nsec,
        },
        .mtime = .{
            .sec = statbuf.st_mtim.tv_sec,
            .nsec = statbuf.st_mtim.tv_nsec,
        },
        .ctime = .{
            .sec = statbuf.st_ctim.tv_sec,
            .nsec = statbuf.st_ctim.tv_nsec,
        },
        .birthtime = .{
            .sec = statbuf.st_birthtim.tv_sec,
            .nsec = statbuf.st_birthtim.tv_nsec,
        },
    };
}

pub const module_name = "std:fs";
const internal_name = "std:internal:fs";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        internal_name,
        &fs.func_defs ++ &path.func_defs,
        &FileClass.class_defs ++ &DirClass.class_defs,
        .{fs.value_defs},
    );
    try vexor.addModule(module_name, @embedFile("fs.js.compiled"));
}

const FileClass = struct {
    ctx: *qjs.JSContext,
    fd: ?uv.uv_file, // null means file closed

    /// fd's owner will be transfered
    /// that means caller should not to close passed fd
    fn constructor(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{uv.uv_file});
        const fd = args[0];
        errdefer {
            var req: uv.uv_fs_t = undefined;
            _ = uv.uv_fs_close(null, &req, fd, null);
            uv.uv_fs_req_cleanup(&req);
        }

        const fh = try smp_allocator.create(FileClass);
        errdefer smp_allocator.destroy(fh);
        fh.* = .{ .ctx = ctx, .fd = fd };

        try qjs.zig_utils.setOpaque(this_obj, fh);
        return null;
    }
    fn finalizer(_: *qjs.JSRuntime, this_obj: qjs.JSValueConst) void {
        if (qjs.zig_utils.getOpaque(FileClass, this_obj)) |fh| {
            if (fh.fd) |fd| {
                var req: uv.uv_fs_t = undefined;
                _ = uv.uv_fs_close(null, &req, fd, null);
                uv.uv_fs_req_cleanup(&req);
            }
            smp_allocator.destroy(fh);
        }
    }

    fn getfd(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst) !?qjs.JSValue {
        const fh = qjs.zig_utils.getOpaque(FileClass, this_obj).?;
        if (fh.fd) |fd| {
            return try qjs.zig_utils.newValue(ctx, fd);
        } else {
            try @import("vexor").utils.uv.checkThrow(ctx, uv.EBADF);
            unreachable;
        }
    }
    const FileReq = struct {
        fh: *FileClass,
        req: uv.uv_fs_t,
        promise: qjs.zig_utils.Promise,
    };
    fn callback(c_req: [*c]uv.uv_fs_t) callconv(.c) void {
        const req: *uv.uv_fs_t = c_req.?;
        const rh = uv.zig_utils.getData(FileReq, req);
        const fh = rh.fh;
        defer {
            uv.uv_fs_req_cleanup(req);
            rh.promise.free(fh.ctx);
            smp_allocator.destroy(rh);
        }

        if (req.result < 0) {
            const errno = @import("vexor").utils.uv.newErrno;
            rh.promise.reject(fh.ctx, errno(fh.ctx, @intCast(req.result)));
        } else switch (req.fs_type) {
            uv.UV_FS_READ => {},
            uv.UV_FS_CLOSE => {
                fh.fd = null;
                rh.promise.resolve(fh.ctx, null);
            },
            uv.UV_FS_FSTAT => {
                if (qjs.zig_utils.newValue(fh.ctx, makeStat(req.statbuf))) |obj| {
                    rh.promise.resolve(fh.ctx, obj);
                } else |_| {
                    @branchHint(.unlikely);
                    rh.promise.reject(fh.ctx, qjs.JS_GetException(fh.ctx));
                }
            },
            uv.UV_FS_FSYNC,
            uv.UV_FS_FDATASYNC,
            uv.UV_FS_FTRUNCATE,
            uv.UV_FS_FCHMOD,
            uv.UV_FS_FUTIME,
            uv.UV_FS_FCHOWN,
            => {
                rh.promise.resolve(fh.ctx, null);
            },
            else => unreachable,
        }
    }
    fn fileFn(comptime uv_func: anytype) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                const vexor = getVexor(ctx);
                const fh = qjs.zig_utils.getOpaque(FileClass, this_obj).?;

                if (fh.fd == null) {
                    try @import("vexor").utils.uv.checkThrow(ctx, uv.EBADF);
                }

                const ti = @typeInfo(@TypeOf(uv_func)).@"fn";
                if (js_args.len < ti.params.len - 4) {
                    return qjs.zig_utils.throwTooFewArgs(ctx, ti.params.len - 4, js_args.len);
                }
                var args: std.meta.ArgsTuple(@TypeOf(uv_func)) = undefined;
                inline for (comptime ti.params[3 .. ti.params.len - 1], 0..) |param, i| {
                    args[i + 3] = try qjs.zig_utils.castValue(param.type.?, ctx, js_args[i]);
                }

                const rh = try smp_allocator.create(FileReq);
                errdefer smp_allocator.destroy(rh);
                rh.fh = fh;
                rh.req.data = rh;

                const result = try qjs.zig_utils.newPromise(ctx, &rh.promise);
                errdefer rh.promise.free(ctx);
                errdefer qjs.JS_FreeValue(ctx, result);

                args[0] = &vexor.loop;
                args[1] = &rh.req;
                args[2] = fh.fd.?;
                args[ti.params.len - 1] = &callback;
                try check(ctx, @call(.auto, uv_func, args));

                return result;
            }
        }.func;
    }
    const ReadWriteReq = struct {
        fh: *FileClass,
        req: uv.uv_fs_t,
        promise: qjs.zig_utils.Promise,
        buf: uv.uv_buf_t,
    };
    fn freeFunc(_: ?*qjs.JSRuntime, @"opaque": ?*anyopaque, c_ptr: ?*anyopaque) callconv(.c) void {
        const ptr: [*]u8 = @ptrCast(@alignCast(c_ptr));
        const len: usize = @intFromPtr(@"opaque");
        smp_allocator.free(ptr[0..len]);
    }
    fn readWriteCb(c_req: [*c]uv.uv_fs_t) callconv(.c) void {
        const req: *uv.uv_fs_t = c_req.?;
        const rh = uv.zig_utils.getData(ReadWriteReq, req);
        const fh = rh.fh;
        defer {
            uv.uv_fs_req_cleanup(req);
            rh.promise.free(fh.ctx);
            smp_allocator.destroy(rh);
        }

        if (req.result < 0) {
            const errno = @import("vexor").utils.uv.newErrno;
            rh.promise.reject(fh.ctx, errno(fh.ctx, @intCast(req.result)));
            smp_allocator.free(uv.zig_utils.bufToSlice(rh.buf));
        } else switch (req.fs_type) {
            uv.UV_FS_READ => {
                const obj = qjs.JS_NewUint8Array(fh.ctx, rh.buf.base, @intCast(req.result), freeFunc, @ptrFromInt(rh.buf.len), false);
                rh.promise.resolve(fh.ctx, obj);
            },
            uv.UV_FS_WRITE => {
                rh.promise.resolve(fh.ctx, qjs.zig_utils.newValue(fh.ctx, req.result));
                smp_allocator.free(uv.zig_utils.bufToSlice(rh.buf));
            },
            else => unreachable,
        }
    }
    fn read(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);
        const fh = qjs.zig_utils.getOpaque(FileClass, this_obj).?;
        if (fh.fd == null) {
            try @import("vexor").utils.uv.checkThrow(ctx, uv.EBADF);
        }

        const length, const offset = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ i64, i64 });
        if (length < 0) return qjs.JS_ThrowRangeError(ctx, "cannot be a negative");

        const rh = try smp_allocator.create(ReadWriteReq);
        errdefer smp_allocator.destroy(rh);
        rh.fh = fh;
        rh.req.data = rh;

        const buf = try smp_allocator.alloc(u8, @intCast(length));
        errdefer smp_allocator.free(buf);
        rh.buf = uv.zig_utils.initBuf(buf);

        const result = try qjs.zig_utils.newPromise(ctx, &rh.promise);
        errdefer rh.promise.free(ctx);
        errdefer qjs.JS_FreeValue(ctx, result);

        try check(ctx, uv.uv_fs_read(&vexor.loop, &rh.req, fh.fd.?, &rh.buf, 1, offset, &readWriteCb));

        return result;
    }
    fn write(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);
        const fh = qjs.zig_utils.getOpaque(FileClass, this_obj).?;
        if (fh.fd == null) {
            try @import("vexor").utils.uv.checkThrow(ctx, uv.EBADF);
        }

        const js_buf, const offset = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ qjs.JSValue, i64 });
        const buf = try qjs.zig_utils.toBuffer(ctx, js_buf, smp_allocator);
        errdefer smp_allocator.free(buf);

        const rh = try smp_allocator.create(ReadWriteReq);
        errdefer smp_allocator.destroy(rh);
        rh.fh = fh;
        rh.req.data = rh;
        rh.buf = uv.zig_utils.initBuf(buf);

        const result = try qjs.zig_utils.newPromise(ctx, &rh.promise);
        errdefer rh.promise.free(ctx);
        errdefer qjs.JS_FreeValue(ctx, result);

        try check(ctx, uv.uv_fs_write(&vexor.loop, &rh.req, fh.fd.?, &rh.buf, 1, offset, &readWriteCb));

        return result;
    }

    const class_defs = [_]qjs.zig_utils.ClassDef{
        qjs.zig_utils.defClass("File", constructor, finalizer, &[_]qjs.zig_utils.FuncDef{
            qjs.zig_utils.defFunc("close", 0, fileFn(uv_fix.uv_fs_close)),
            qjs.zig_utils.defFunc("stat", 0, fileFn(uv_fix.uv_fs_fstat)),
            qjs.zig_utils.defFunc("sync", 0, fileFn(uv_fix.uv_fs_fsync)),
            qjs.zig_utils.defFunc("datasync", 0, fileFn(uv_fix.uv_fs_fdatasync)),
            qjs.zig_utils.defFunc("truncate", 0, fileFn(uv_fix.uv_fs_ftruncate)),
            qjs.zig_utils.defFunc("chmod", 0, fileFn(uv_fix.uv_fs_fchmod)),
            qjs.zig_utils.defFunc("utime", 0, fileFn(uv_fix.uv_fs_futime)),
            qjs.zig_utils.defFunc("chown", 0, fileFn(uv_fix.uv_fs_fchown)),
            qjs.zig_utils.defGetSet("fd", getfd, null),
            qjs.zig_utils.defFunc("read", 0, read),
            qjs.zig_utils.defFunc("write", 0, write),
        }),
    };
};

const DirClass = struct {
    ctx: *qjs.JSContext,
    dir: ?*uv.uv_dir_t,
    ent: uv.uv_dirent_t,

    /// dir's owner will be transfered
    /// that means caller should not to close passed dir
    fn constructor(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{qjs.JSValue});
        const dir: *uv.uv_dir_t = @ptrCast(@alignCast(args[0].u.ptr));
        errdefer {
            var req: uv.uv_fs_t = undefined;
            _ = uv.uv_fs_closedir(null, &req, dir, null);
            uv.uv_fs_req_cleanup(&req);
        }

        const dh = try smp_allocator.create(DirClass);
        errdefer smp_allocator.destroy(dh);
        dh.* = .{ .ctx = ctx, .dir = dir, .ent = undefined };
        dh.dir.?.dirents = &dh.ent;
        dh.dir.?.nentries = 1;

        try qjs.zig_utils.setOpaque(this_obj, dh);
        return null;
    }
    fn finalizer(_: *qjs.JSRuntime, this_obj: qjs.JSValueConst) void {
        if (qjs.zig_utils.getOpaque(DirClass, this_obj)) |dh| {
            if (dh.dir) |dir| {
                var req: uv.uv_fs_t = undefined;
                _ = uv.uv_fs_closedir(null, &req, dir, null);
                uv.uv_fs_req_cleanup(&req);
            }
            smp_allocator.destroy(dh);
        }
    }

    const DirReq = struct {
        dh: *DirClass,
        req: uv.uv_fs_t,
        promise: qjs.zig_utils.Promise,
    };
    fn callback(c_req: [*c]uv.uv_fs_t) callconv(.c) void {
        const req: *uv.uv_fs_t = c_req.?;
        const rh = uv.zig_utils.getData(DirReq, req);
        const dh = rh.dh;
        defer {
            uv.uv_fs_req_cleanup(req);
            rh.promise.free(dh.ctx);
            smp_allocator.destroy(rh);
        }

        if (req.result < 0) {
            const errno = @import("vexor").utils.uv.newErrno;
            rh.promise.reject(dh.ctx, errno(dh.ctx, @intCast(req.result)));
        } else switch (req.fs_type) {
            uv.UV_FS_READDIR => {
                if (req.result != 0) {
                    const obj = qjs.zig_utils.newValue(dh.ctx, .{
                        .value = .{
                            .name = std.mem.span(dh.ent.name),
                            .type = dh.ent.type,
                        },
                    });
                    rh.promise.resolve(dh.ctx, obj);
                } else {
                    const obj = qjs.zig_utils.newValue(dh.ctx, .{
                        .done = true,
                    });
                    rh.promise.resolve(dh.ctx, obj);
                    // close
                    var req2: uv.uv_fs_t = undefined;
                    _ = uv.uv_fs_closedir(null, &req2, dh.dir, null);
                    uv.uv_fs_req_cleanup(&req2);
                    dh.dir = null;
                }
            },
            else => unreachable,
        }
    }
    fn next(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);
        const dh = qjs.zig_utils.getOpaque(DirClass, this_obj).?;

        const rh = try smp_allocator.create(DirReq);
        errdefer smp_allocator.destroy(rh);
        rh.dh = dh;
        rh.req.data = rh;

        const result = try qjs.zig_utils.newPromise(ctx, &rh.promise);
        errdefer rh.promise.free(ctx);
        errdefer qjs.JS_FreeValue(ctx, result);

        if (dh.dir) |dir| {
            try check(ctx, uv.uv_fs_readdir(&vexor.loop, &rh.req, dir, &callback));
        } else {
            rh.promise.resolve(ctx, try qjs.zig_utils.newValue(ctx, .{
                .done = true,
            }));
            rh.promise.free(ctx);
        }

        return result;
    }
    fn asyncIterator(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        return qjs.JS_DupValue(ctx, this_obj);
    }

    const class_defs = [_]qjs.zig_utils.ClassDef{
        qjs.zig_utils.defClass("Dir", constructor, finalizer, &[_]qjs.zig_utils.FuncDef{
            qjs.zig_utils.defFunc("next", 0, next),
            qjs.zig_utils.defFunc("[Symbol.asyncIterator]", 0, asyncIterator),
        }),
    };
};

const fs = struct {
    const FSReq = struct {
        ctx: *qjs.JSContext,
        req: uv.uv_fs_t,
        promise: qjs.zig_utils.Promise,
    };
    fn scandirCallback(ctx: *qjs.JSContext, req: *uv.uv_fs_t) !qjs.JSValue {
        const obj = qjs.JS_NewArray(ctx);
        errdefer qjs.JS_FreeValue(ctx, obj);
        if (qjs.JS_IsException(obj)) {
            return error.FailedToNewArray;
        }
        var ent: uv.uv_dirent_t = undefined;
        var idx: u32 = 0;
        while (uv.uv_fs_scandir_next(req, &ent) != uv.UV_EOF) {
            const val = try qjs.zig_utils.newValue(ctx, .{
                .name = std.mem.span(ent.name),
                .type = ent.type,
            });
            errdefer qjs.JS_FreeValue(ctx, val);
            if (qjs.JS_SetPropertyUint32(ctx, obj, idx, val) != 0) {
                return error.FailedToSetPropertyUint32;
            }
            idx += 1;
        }
        return obj;
    }
    fn callback(c_req: [*c]uv.uv_fs_t) callconv(.c) void {
        const req: *uv.uv_fs_t = c_req.?;
        const rh = uv.zig_utils.getData(FSReq, req);
        defer {
            uv.uv_fs_req_cleanup(req);
            rh.promise.free(rh.ctx);
            smp_allocator.destroy(rh);
        }

        if (req.result < 0) {
            const errno = @import("vexor").utils.uv.newErrno;
            rh.promise.reject(rh.ctx, errno(rh.ctx, @intCast(req.result)));
        } else switch (req.fs_type) {
            // open mkstemp opendir
            uv.UV_FS_OPEN => {
                rh.promise.resolve(rh.ctx, qjs.zig_utils.newValue(rh.ctx, req.result));
            },
            uv.UV_FS_MKSTEMP => {
                const ret = .{
                    .path = std.mem.span(req.path),
                    .fd = req.result,
                };
                rh.promise.resolve(rh.ctx, qjs.zig_utils.newValue(rh.ctx, ret));
            },
            uv.UV_FS_OPENDIR => {
                rh.promise.resolve(rh.ctx, .{
                    .tag = qjs.JS_TAG_NULL,
                    .u = .{ .ptr = req.ptr },
                });
            },
            // others
            uv.UV_FS_UNLINK,
            uv.UV_FS_MKDIR,
            uv.UV_FS_RMDIR,
            uv.UV_FS_RENAME,
            uv.UV_FS_COPYFILE,
            uv.UV_FS_ACCESS,
            uv.UV_FS_CHMOD,
            uv.UV_FS_UTIME,
            uv.UV_FS_LUTIME,
            uv.UV_FS_LINK,
            uv.UV_FS_SYMLINK,
            uv.UV_FS_CHOWN,
            uv.UV_FS_LCHOWN,
            => {
                rh.promise.resolve(rh.ctx, null);
            },
            uv.UV_FS_MKDTEMP => {
                const obj = qjs.JS_NewString(rh.ctx, req.path);
                rh.promise.resolve(rh.ctx, obj);
            },
            uv.UV_FS_STAT, uv.UV_FS_LSTAT => {
                const obj = qjs.zig_utils.newValue(rh.ctx, makeStat(req.statbuf));
                rh.promise.resolve(rh.ctx, obj);
            },
            uv.UV_FS_READLINK, uv.UV_FS_REALPATH => {
                const obj = qjs.JS_NewString(rh.ctx, @ptrCast(@alignCast(req.ptr)));
                rh.promise.resolve(rh.ctx, obj);
            },
            uv.UV_FS_STATFS => {
                const c_statfs: *uv.uv_statfs_t = @ptrCast(@alignCast(req.ptr));
                const statfs = .{
                    .type = c_statfs.f_type,
                    .bsize = c_statfs.f_bsize,
                    .blocks = c_statfs.f_blocks,
                    .bfree = c_statfs.f_bfree,
                    .bavail = c_statfs.f_bavail,
                    .files = c_statfs.f_files,
                    .ffree = c_statfs.f_ffree,
                };
                const obj = qjs.zig_utils.newValue(rh.ctx, statfs);
                rh.promise.resolve(rh.ctx, obj);
            },
            uv.UV_FS_SCANDIR => {
                rh.promise.resolve(rh.ctx, scandirCallback(rh.ctx, req));
            },
            else => unreachable,
        }
    }
    fn fsFn(comptime uv_func: anytype) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
                // std.debug.print("fsFn\n", .{});
                const vexor = getVexor(ctx);

                const ti = @typeInfo(@TypeOf(uv_func)).@"fn";
                if (js_args.len < ti.params.len - 4) {
                    return qjs.zig_utils.throwTooFewArgs(ctx, ti.params.len - 4, js_args.len);
                }
                var args: std.meta.ArgsTuple(@TypeOf(uv_func)) = undefined;
                var finished_arg: usize = 0;
                defer inline for (ti.params[2 .. ti.params.len - 1], 2..) |param, i| {
                    if (i == 2 + finished_arg) break;
                    if (param.type.? == [*c]const u8) {
                        qjs.JS_FreeCString(ctx, args[i]);
                    }
                };
                inline for (comptime ti.params[2 .. ti.params.len - 1], 0..) |param, i| {
                    if (param.type.? == [*c]const u8) {
                        args[i + 2] = (try qjs.zig_utils.toString(ctx, js_args[i])).ptr;
                    } else if (param.type.? == usize) {
                        args[i + 2] = @intCast(try qjs.zig_utils.castValue(i64, ctx, js_args[i]));
                    } else {
                        args[i + 2] = try qjs.zig_utils.castValue(param.type.?, ctx, js_args[i]);
                    }
                    finished_arg += 1;
                }

                const rh = try smp_allocator.create(FSReq);
                errdefer smp_allocator.destroy(rh);
                rh.ctx = ctx;
                rh.req.data = rh;

                const result = try qjs.zig_utils.newPromise(ctx, &rh.promise);
                errdefer rh.promise.free(ctx);
                errdefer qjs.JS_FreeValue(ctx, result);

                args[0] = &vexor.loop;
                args[1] = &rh.req;
                args[ti.params.len - 1] = &callback;
                try check(ctx, @call(.auto, uv_func, args));

                return result;
            }
        }.func;
    }
    const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("open", 0, fsFn(uv_fix.uv_fs_open)),
        qjs.zig_utils.defFunc("mkdtemp", 0, fsFn(uv_fix.uv_fs_mkdtemp)),
        qjs.zig_utils.defFunc("unlink", 0, fsFn(uv_fix.uv_fs_unlink)),
        qjs.zig_utils.defFunc("copyfile", 0, fsFn(uv_fix.uv_fs_copyfile)),
        qjs.zig_utils.defFunc("mkdir", 0, fsFn(uv_fix.uv_fs_mkdir)),
        qjs.zig_utils.defFunc("mkstemp", 0, fsFn(uv_fix.uv_fs_mkstemp)),
        qjs.zig_utils.defFunc("rmdir", 0, fsFn(uv_fix.uv_fs_rmdir)),
        qjs.zig_utils.defFunc("stat", 0, fsFn(uv_fix.uv_fs_stat)),
        qjs.zig_utils.defFunc("rename", 0, fsFn(uv_fix.uv_fs_rename)),
        qjs.zig_utils.defFunc("access", 0, fsFn(uv_fix.uv_fs_access)),
        qjs.zig_utils.defFunc("chmod", 0, fsFn(uv_fix.uv_fs_chmod)),
        qjs.zig_utils.defFunc("utime", 0, fsFn(uv_fix.uv_fs_utime)),
        qjs.zig_utils.defFunc("lutime", 0, fsFn(uv_fix.uv_fs_lutime)),
        qjs.zig_utils.defFunc("lstat", 0, fsFn(uv_fix.uv_fs_lstat)),
        qjs.zig_utils.defFunc("link", 0, fsFn(uv_fix.uv_fs_link)),
        qjs.zig_utils.defFunc("symlink", 0, fsFn(uv_fix.uv_fs_symlink)),
        qjs.zig_utils.defFunc("readlink", 0, fsFn(uv_fix.uv_fs_readlink)),
        qjs.zig_utils.defFunc("realpath", 0, fsFn(uv_fix.uv_fs_realpath)),
        qjs.zig_utils.defFunc("chown", 0, fsFn(uv_fix.uv_fs_chown)),
        qjs.zig_utils.defFunc("lchown", 0, fsFn(uv_fix.uv_fs_lchown)),
        qjs.zig_utils.defFunc("statfs", 0, fsFn(uv_fix.uv_fs_statfs)),
        qjs.zig_utils.defFunc("sendfile", 0, fsFn(uv_fix.uv_fs_sendfile)),
        qjs.zig_utils.defFunc("scandir", 0, fsFn(uv_fix.uv_fs_scandir)),
        qjs.zig_utils.defFunc("opendir", 0, fsFn(uv_fix.uv_fs_opendir)),
    };
    const value_defs = .{
        .constants = .{
            .F_OK = uv.F_OK,
            .R_OK = uv.R_OK,
            .W_OK = uv.W_OK,
            .X_OK = uv.X_OK,
            .O_APPEND = uv.UV_FS_O_APPEND,
            .O_CREAT = uv.UV_FS_O_CREAT,
            .O_DIRECT = uv.UV_FS_O_DIRECT,
            .O_DIRECTORY = uv.UV_FS_O_DIRECTORY,
            .O_DSYNC = uv.UV_FS_O_DSYNC,
            .O_EXCL = uv.UV_FS_O_EXCL,
            .O_EXLOCK = uv.UV_FS_O_EXLOCK,
            .O_NOATIME = uv.UV_FS_O_NOATIME,
            .O_NOCTTY = uv.UV_FS_O_NOCTTY,
            .O_NOFOLLOW = uv.UV_FS_O_NOFOLLOW,
            .O_NONBLOCK = uv.UV_FS_O_NONBLOCK,
            .O_RDONLY = uv.UV_FS_O_RDONLY,
            .O_RDWR = uv.UV_FS_O_RDWR,
            .O_SYMLINK = uv.UV_FS_O_SYMLINK,
            .O_SYNC = uv.UV_FS_O_SYNC,
            .O_TRUNC = uv.UV_FS_O_TRUNC,
            .O_WRONLY = uv.UV_FS_O_WRONLY,
            .O_FILEMAP = uv.UV_FS_O_FILEMAP,
            .O_RANDOM = uv.UV_FS_O_RANDOM,
            .O_SHORT_LIVED = uv.UV_FS_O_SHORT_LIVED,
            .O_SEQUENTIAL = uv.UV_FS_O_SEQUENTIAL,
            .O_TEMPORARY = uv.UV_FS_O_TEMPORARY,
            .COPYFILE_EXCL = uv.UV_FS_COPYFILE_EXCL,
            .COPYFILE_FICLONE = uv.UV_FS_COPYFILE_FICLONE,
            .COPYFILE_FICLONE_FORCE = uv.UV_FS_COPYFILE_FICLONE_FORCE,
            .SYMLINK_DIR = uv.UV_FS_SYMLINK_DIR,
            .SYMLINK_JUNCTION = uv.UV_FS_SYMLINK_JUNCTION,
            .S_IFMT = uv.S_IFMT,
            .S_IFDIR = uv.S_IFDIR,
            .S_IFCHR = uv.S_IFCHR,
            .S_IFBLK = uv.S_IFBLK,
            .S_IFREG = uv.S_IFREG,
            .S_IFIFO = uv.S_IFIFO,
            .S_IFLNK = uv.S_IFLNK,
            .S_IFSOCK = uv.S_IFSOCK,
            .DIRENT_UNKNOWN = uv.UV_DIRENT_UNKNOWN,
            .DIRENT_FILE = uv.UV_DIRENT_FILE,
            .DIRENT_DIR = uv.UV_DIRENT_DIR,
            .DIRENT_LINK = uv.UV_DIRENT_LINK,
            .DIRENT_FIFO = uv.UV_DIRENT_FIFO,
            .DIRENT_SOCKET = uv.UV_DIRENT_SOCKET,
            .DIRENT_CHAR = uv.UV_DIRENT_CHAR,
            .DIRENT_BLOCK = uv.UV_DIRENT_BLOCK,
        },
    };
};

const path = struct {
    fn getStringFn(comptime uv_func: anytype) qjs.zig_utils.Function {
        return struct {
            fn func(ctx: *qjs.JSContext, _: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
                const buffer = try smp_allocator.alloc(u8, 256);
                var size: usize = 256;
                defer smp_allocator.free(buffer);
                switch (uv_func(buffer.ptr, &size)) {
                    0 => {
                        return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
                    },
                    uv.UV_ENOBUFS => {
                        try check(ctx, uv_func(buffer.ptr, &size));
                        return qjs.JS_NewStringLen(ctx, buffer.ptr, size);
                    },
                    else => |err| {
                        try check(ctx, err);
                        unreachable;
                    },
                }
            }
        }.func;
    }
    fn chdir(ctx: *qjs.JSContext, _: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{qjs.JSValue});
        const dir = try qjs.zig_utils.toString(ctx, args[0]);
        defer qjs.JS_FreeCString(ctx, dir.ptr);
        try check(ctx, uv.uv_chdir(dir.ptr));
        return null;
    }

    const func_defs = [_]qjs.zig_utils.FuncDef{
        qjs.zig_utils.defFunc("getcwd", 0, getStringFn(uv.uv_cwd)),
        qjs.zig_utils.defFunc("chdir", 0, chdir),
        qjs.zig_utils.defFunc("gethomedir", 0, getStringFn(uv.uv_os_homedir)),
        qjs.zig_utils.defFunc("gettmpdir", 0, getStringFn(uv.uv_os_tmpdir)),
    };
};

test fs {
    const testRun = @import("vexor").debug.testRun;
    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);

    const global_this = qjs.JS_GetGlobalObject(vexor.ctx);
    defer qjs.JS_FreeValue(vexor.ctx, global_this);
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    var tmp_path: [256]u8 = undefined;
    _ = qjs.JS_SetPropertyStr(
        vexor.ctx,
        global_this,
        "tmpdir",
        try qjs.zig_utils.newValue(vexor.ctx, try tmp_dir.dir.realpath(".", &tmp_path)),
    );

    try testRun(vexor,
        \\import { getcwd, chdir, gethomedir, gettmpdir } from 'std:fs';
        \\
        \\const cwd = getcwd();
        \\expect(typeof cwd === 'string', 'getcwd returns string');
        \\expect(cwd.length > 0, 'getcwd non-empty');
        \\
        \\const home = gethomedir();
        \\expect(home.length > 0, 'homedir non-empty');
        \\
        \\const tmp = gettmpdir();
        \\expect(tmp.length > 0, 'tmpdir non-empty');
        \\
        \\chdir(tmp);
        \\expect(getcwd() === tmp, 'chdir works');
    , "");
    try testRun(vexor,
        \\import { open, unlink, exists, mkdtemp, constants } from 'std:fs';
        \\
        \\const tmpDir = await mkdtemp(tmpdir + '/test-XXXXXX');
        \\const filePath = tmpDir + '/test.txt';
        \\
        \\// Create file
        \\const file = await open(filePath, 'w', 0o644);
        \\expect(file.fd > 0, 'file created');
        \\await file.close();
        \\
        \\// Check existence
        \\expect(await exists(filePath), 'file exists');
        \\
        \\// Delete file
        \\await unlink(filePath);
        \\expect(!await exists(filePath), 'file deleted');
    , "");
    try testRun(vexor,
        \\import { mkdtemp, mkdir, rmdir, exists, opendir, constants } from 'std:fs';
        \\
        \\const baseDir = await mkdtemp(tmpdir + '/parent-XXXXXX');
        \\const subDir = baseDir + '/child';
        \\
        \\// Create directory
        \\await mkdir(subDir, 0o755);
        \\expect(await exists(subDir), 'directory created');
        \\
        \\// List directory
        \\const dir = await opendir(baseDir);
        \\let found = false;
        \\for await (const entry of dir) {
        \\    if (entry.name === 'child') {
        \\        found = true;
        \\        expect(entry.type === constants.DIRENT_DIR, 'directory entry type');
        \\    }
        \\}
        \\expect(found, 'directory listed');
        \\
        \\// Remove directory
        \\await rmdir(subDir);
        \\expect(!await exists(subDir), 'directory removed');
    , "");
    try testRun(vexor,
        \\import { open, symlink, stat, lstat, constants, unlink, mkdtemp } from 'std:fs';
        \\
        \\const tmpDir = await mkdtemp(tmpdir + '/meta-XXXXXX');
        \\const filePath = tmpDir + '/file.txt';
        \\const file = await open(filePath, 'w');
        \\await file.close();
        \\
        \\// Regular stat
        \\const stats = await stat(filePath);
        \\expect(stats.size === 0, 'new file size is 0');
        \\expect((stats.mode & constants.S_IFMT) === constants.S_IFREG, 'regular file type');
        \\
        \\const linkPath = tmpDir + '/link';
        \\await symlink(filePath, linkPath);
        \\const linkStats = await lstat(linkPath);
        \\expect((linkStats.mode & constants.S_IFMT) === constants.S_IFLNK, 'symlink type');
        \\await unlink(linkPath);
        \\
        \\await unlink(filePath);
    , "");
    try testRun(vexor,
        \\import { mkdtemp, open, copyfile, rename, exists, unlink } from 'std:fs';
        \\
        \\const tmpDir = await mkdtemp(tmpdir + '/util-XXXXXX');
        \\const srcPath = tmpDir + '/source.txt';
        \\const copyPath = tmpDir + '/copy.txt';
        \\const renamePath = tmpDir + '/renamed.txt';
        \\
        \\// Create source file
        \\const file = await open(srcPath, 'w');
        \\await file.close();
        \\
        \\// Copy file
        \\await copyfile(srcPath, copyPath);
        \\expect(await exists(copyPath), 'file copied');
        \\
        \\// Rename file
        \\await rename(copyPath, renamePath);
        \\expect(await exists(renamePath), 'file renamed');
        \\expect(!await exists(copyPath), 'original copy gone');
        \\
        \\// Cleanup
        \\await unlink(srcPath);
        \\await unlink(renamePath);
    , "");
    try testRun(vexor,
        \\import { mkdtemp, mkstemp, exists } from 'std:fs';
        \\
        \\// Temporary directory
        \\const tmpDir = await mkdtemp(tmpdir + '/dir-XXXXXX');
        \\expect(await exists(tmpDir), 'temp dir created');
        \\expect(tmpDir.startsWith(tmpdir), 'temp dir in system temp');
        \\
        \\// Temporary file
        \\const { path, file } = await mkstemp('file-XXXXXX');
        \\expect(typeof path === 'string', 'temp file path is string')
        \\expect(file.fd > 0, 'temp file created');
        \\await file.close();
    , "");
    try testRun(vexor,
        \\import { mkdtemp, open, chmod, stat, chown, unlink } from 'std:fs';
        \\
        \\const tmpDir = await mkdtemp(tmpdir + '/perm-XXXXXX');
        \\const filePath = tmpDir + '/perms.txt';
        \\const file = await open(filePath, 'w');
        \\await file.close();
        \\
        \\// Change permissions
        \\await chmod(filePath, 0o600);
        \\const stats = await stat(filePath);
        \\expect((stats.mode & 0o777) === 0o600, 'permissions changed');
        \\
        \\await unlink(filePath);
    , "");
    try testRun(vexor,
        \\import { mkdtemp, symlink, readlink, realpath, lstat, unlink, exists, open, constants } from 'std:fs';
        \\
        \\const tmpDir = await mkdtemp(tmpdir + '/symlink-XXXXXX');
        \\const targetPath = tmpDir + '/target';
        \\const linkPath = tmpDir + '/link';
        \\
        \\const file = await open(targetPath, 'w');
        \\await file.close();
        \\
        \\// Create symlink
        \\await symlink(targetPath, linkPath);
        \\expect(await exists(linkPath), 'symlink created');
        \\
        \\// Read link
        \\const linkTarget = await readlink(linkPath);
        \\expect(linkTarget.endsWith('/target'), 'symlink target correct');
        \\
        \\// Get real path
        \\const real = await realpath(linkPath);
        \\expect(real.endsWith('/target'), 'realpath resolves');
        \\
        \\// Check link type
        \\const lstats = await lstat(linkPath);
        \\expect((lstats.mode & constants.S_IFMT) === constants.S_IFLNK, 'symlink type');
        \\
        \\await unlink(linkPath);
    , "");
    try testRun(vexor,
        \\import { open, mkdtemp, unlink } from 'std:fs';
        \\
        \\const tmpBase = tmpdir;
        \\const tmpDir = await mkdtemp(tmpdir + 'rwtest-XXXXXX');
        \\const filePath = tmpDir + '/test.txt';
        \\
        \\// Open file for writing
        \\const file = await open(filePath, 'w');
        \\
        \\// Write data
        \\const data = new Uint8Array([72, 101, 108, 108, 111]); // "Hello"
        \\const written = await file.write(data, 0);
        \\expectEql(written, 5, 'wrote 5 bytes');
        \\
        \\// Close and reopen for reading
        \\await file.close();
        \\const readFile = await open(filePath, 'r');
        \\
        \\// Read data
        \\const buffer = await readFile.read(5, 0);
        \\expect(buffer instanceof Uint8Array, 'read returns Uint8Array');
        \\expect(buffer.length === 5, 'read returns correct length');
        \\expect(buffer[0] === 72, 'read returns correct data');
        \\expect(buffer[1] === 101, 'read returns correct data');
        \\expect(buffer[2] === 108, 'read returns correct data');
        \\expect(buffer[3] === 108, 'read returns correct data');
        \\expect(buffer[4] === 111, 'read returns correct data');
        \\
        \\// Test partial read
        \\const partial = await readFile.read(3, 2);
        \\expect(partial.length === 3, 'partial read returns correct length');
        \\expect(partial[0] === 108, 'partial read returns correct data');
        \\expect(partial[1] === 108, 'partial read returns correct data');
        \\expect(partial[2] === 111, 'partial read returns correct data');
        \\
        \\// Test read beyond EOF
        \\const beyond = await readFile.read(10, 10);
        \\expect(beyond.length === 0, 'read beyond EOF returns empty buffer');
        \\
        \\await readFile.close();
        \\await unlink(filePath);
    , "");
}
