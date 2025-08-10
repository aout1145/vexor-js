const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:tty";
const internal_name = "std:internal:tty";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        internal_name,
        &[_]qjs.zig_utils.FuncDef{},
        &TTYClass.class_defs,
        .{TTYClass.value_def},
    );
    try vexor.addModule(module_name, @embedFile("tty.js.compiled"));
}

const TTYClass = struct {
    const StreamClass = @import("./stream.zig").StreamClass;
    stream: StreamClass,
    handle: uv.uv_tty_t,

    fn closeCallback(handle: [*c]uv.uv_handle_t) callconv(.c) void {
        const th = uv.zig_utils.getData(TTYClass, handle);
        th.stream.deinit();
        th.stream.header.is_closed = true;
        th.stream.header.unref(TTYClass, smp_allocator);
    }
    fn constructor(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);

        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{uv.uv_file});
        const fd = args[0];

        const th = try smp_allocator.create(TTYClass);
        errdefer smp_allocator.destroy(th);
        try th.stream.init(Vexor.UVDataHeader.init(&closeCallback), ctx, @ptrCast(&th.handle));
        errdefer th.stream.deinit();

        try check(ctx, uv.uv_tty_init(&vexor.loop, &th.handle, fd, 0));
        errdefer uv.uv_close(@ptrCast(&th.handle), null);
        th.handle.data = th.stream.header.ref(TTYClass);

        try qjs.zig_utils.setOpaque(this_obj, th.stream.header.ref(TTYClass));
        return null;
    }
    fn finalizer(_: *qjs.JSRuntime, this_obj: qjs.JSValueConst) void {
        if (qjs.zig_utils.getOpaque(TTYClass, this_obj)) |th| {
            th.stream.header.close(&th.handle);
            th.stream.header.unref(TTYClass, smp_allocator);
        } else |_| {}
    }
    fn setMode(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const th = try qjs.zig_utils.getOpaque(TTYClass, this_obj);

        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{uv.uv_tty_mode_t});
        const mode = args[0];

        try check(ctx, uv.uv_tty_set_mode(&th.handle, mode));

        return null;
    }
    fn getWindowSize(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        const th = try qjs.zig_utils.getOpaque(TTYClass, this_obj);

        const WindowSize = struct { width: c_int, height: c_int };
        var wndsize: WindowSize = undefined;
        try check(ctx, uv.uv_tty_get_winsize(&th.handle, &wndsize.width, &wndsize.height));

        return try qjs.zig_utils.newValue(ctx, wndsize);
    }

    const class_defs = [_]qjs.zig_utils.ClassDef{
        qjs.zig_utils.defClass(
            "TTY",
            TTYClass.constructor,
            TTYClass.finalizer,
            &[_]qjs.zig_utils.FuncDef{
                qjs.zig_utils.defFunc("setMode", 0, setMode),
                qjs.zig_utils.defFunc("getWindowSize", 0, getWindowSize),
            } ++ &StreamClass.func_defs,
        ),
    };
    const value_def = .{
        .mode = enum(uv.uv_tty_mode_t) {
            NORMAL = uv.UV_TTY_MODE_NORMAL,
            RAW = uv.UV_TTY_MODE_RAW,
        },
    };
};

comptime {
    Vexor.UVDataHeader.check(TTYClass);
}

test TTYClass {
    const testRun = @import("vexor").debug.testRun;
    const testStdin = struct {
        fn func(vexor: *Vexor, js_str: []const u8, input_str: []const u8, expected_err: ?[]const u8) !void {
            if (@import("builtin").os.tag == .windows) return;
            const pipe = try std.posix.pipe();
            defer std.posix.close(pipe[0]);
            defer std.posix.close(pipe[1]);
            const oldfd = try std.posix.dup(std.posix.STDIN_FILENO);
            try std.posix.dup2(pipe[0], std.posix.STDIN_FILENO);
            defer std.posix.dup2(oldfd, std.posix.STDIN_FILENO) catch {};
            _ = try std.posix.write(pipe[1], input_str);
            try testRun(vexor, js_str, expected_err);
        }
    }.func;
    const testStdout = struct {
        fn func(vexor: *Vexor, js_str: []const u8, comptime output_str: []const u8, expected_err: ?[]const u8) !void {
            if (@import("builtin").os.tag == .windows) return;
            const pipe = try std.posix.pipe();
            defer std.posix.close(pipe[0]);
            const oldfd = try std.posix.dup(std.posix.STDOUT_FILENO);
            try std.posix.dup2(pipe[1], std.posix.STDOUT_FILENO);
            defer std.posix.dup2(oldfd, std.posix.STDOUT_FILENO) catch {};
            try testRun(vexor, js_str, expected_err);
            std.posix.close(pipe[1]);
            var buf: [output_str.len]u8 = undefined;
            @memset(&buf, 0);
            _ = try std.posix.read(pipe[0], &buf);
            if (!std.mem.eql(u8, &buf, output_str)) {
                return error.WrongStdout;
            }
        }
    }.func;

    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\expect(stdin.readable);
    , "", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(3);
    , "", null);
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readTextOnce(), 'abcd');
        \\expectEql(await stdin.readTextOnce(), 'efgh');
    , "abcdefgh", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readText(3), 'abc');
        \\expectEql(await stdin.readText(1), 'd');
        \\expectEql(await stdin.readText(5), 'efgh\n');
    , "abcdefgh\n", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readTextUntil(32), 'abcde ');
        \\expectEql(await stdin.readTextUntil(32), 'uvw ');
        \\expectEql(await stdin.readTextUntil(10), 'xyz\n');
        \\expectEql(await stdin.readLine(), 'hellox\n');
    , "abcde uvw xyz\nhellox\n", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\const result = await stdin.read(11);
        \\expectEql(result.length, 11);
        \\expectEql(result.toString(), '104,101,108,108,111,32,119,111,114,108,100');
    , "hello world", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdin = new TTY(0);
        \\stdin.read(7);
        \\stdin.close();
        \\stdin.close();
    , "hello world", null);
    try testStdout(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdout = new TTY(1);
        \\await stdout.writeText("abc\n");
        \\await stdout.write(Uint8Array.of(97, 98, 99, 10));
    , "abc\nabc\n", "");
    try testStdout(vexor,
        \\import { TTY } from 'std:internal:tty';
        \\const stdout = new TTY(1);
        \\await stdout.tryWriteText("abc\n");
        \\await stdout.tryWrite(Uint8Array.of(97, 98, 99, 10));
    , "abc\nabc\n", "");
    try testRun(vexor,
        \\import { TTY, mode } from 'std:internal:tty';
        \\const stdout = new TTY(1);
        \\expectEql(mode.NORMAL, 0);
        \\expectEql(mode.RAW, 1);
        \\stdout.setMode(mode.NORMAL);
    , "");
}
