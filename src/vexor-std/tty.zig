const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const check = @import("vexor").utils.uv.checkThrow;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "std:tty";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        module_name,
        &[_]qjs.zig_utils.FuncDef{},
        &TTYClass.class_defs,
    );
}

const TTYClass = struct {
    const StreamClass = @import("./stream.zig").StreamClass;
    stream: StreamClass,
    handle: uv.uv_tty_t,

    fn closeCallback(handle: [*c]uv.uv_handle_t) callconv(.c) void {
        const th = uv.zig_utils.getData(TTYClass, handle);
        th.stream.header.unref(TTYClass, smp_allocator);
    }
    fn constructor(ctx: *qjs.JSContext, this_val: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = getVexor(ctx);

        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{uv.uv_file});
        const fd = args[0];

        const obj = try qjs.zig_utils.newObjectFromConstructor(ctx, this_val);
        errdefer qjs.JS_FreeValue(ctx, obj);

        const th = try smp_allocator.create(TTYClass);
        errdefer smp_allocator.destroy(th);
        try th.stream.init(Vexor.UVDataHeader.init(&closeCallback), ctx, @ptrCast(&th.handle));
        errdefer th.stream.deinit();

        try check(ctx, uv.uv_tty_init(&vexor.loop, &th.handle, fd, 0));

        try qjs.zig_utils.setOpaque(obj, th.stream.header.ref(TTYClass));
        th.handle.data = th.stream.header.ref(TTYClass);
        return obj;
    }
    fn finalizer(_: *qjs.JSRuntime, this_val: qjs.JSValueConst) void {
        if (qjs.zig_utils.getOpaque(TTYClass, this_val)) |th| {
            th.stream.deinit();
            th.stream.header.unref(TTYClass, smp_allocator);
        } else |_| {}
    }

    const class_defs = [_]qjs.zig_utils.ClassDef{
        qjs.zig_utils.defClass(
            "TTY",
            TTYClass.constructor,
            TTYClass.finalizer,
            &[_]qjs.zig_utils.FuncDef{} ++ &StreamClass.func_defs,
        ),
    };
};

comptime {
    Vexor.UVDataHeader.check(TTYClass);
}

test TTYClass {
    const testStdin = struct {
        fn func(vexor: *Vexor, js_str: []const u8, input_str: []const u8, expected_err: ?[]const u8) !void {
            const pipe = try std.posix.pipe();
            defer std.posix.close(pipe[0]);
            defer std.posix.close(pipe[1]);
            const oldfd = try std.posix.dup(std.posix.STDIN_FILENO);
            try std.posix.dup2(pipe[0], std.posix.STDIN_FILENO);
            defer std.posix.dup2(oldfd, std.posix.STDIN_FILENO) catch {};
            _ = try std.posix.write(pipe[1], input_str);
            try @import("vexor").debug.testRun(vexor, js_str, expected_err);
        }
    }.func;

    const vexor = try Vexor.init();
    defer vexor.deinit();
    @import("vexor").debug.init(vexor);
    try init(vexor);
    try testStdin(vexor,
        \\import { TTY } from 'std:tty';
        \\const stdin = new TTY(0);
        \\expect(stdin.readable);
    , "", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readTextOnce(), 'abcd');
        \\expectEql(await stdin.readTextOnce(), 'efgh');
    , "abcdefgh", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readText(3), 'abc');
        \\expectEql(await stdin.readText(1), 'd');
        \\expectEql(await stdin.readText(5), 'efgh\n');
    , "abcdefgh\n", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:tty';
        \\const stdin = new TTY(0);
        \\expectEql(await stdin.readTextUntil(32), 'abcde ');
        \\expectEql(await stdin.readTextUntil(32), 'uvw ');
        \\expectEql(await stdin.readTextUntil(10), 'xyz\n');
        \\expectEql(await stdin.readLine(), 'hellox\n');
    , "abcde uvw xyz\nhellox\n", "");
    try testStdin(vexor,
        \\import { TTY } from 'std:tty';
        \\const stdin = new TTY(0);
        \\expectEql((await stdin.read(11)).length, 11);
    , "hello world", "");
}
