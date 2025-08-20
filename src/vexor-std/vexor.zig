const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;
const smp_allocator = Vexor.smp_allocator;
const getVexor = @import("vexor").utils.getVexor;

pub const module_name = "vexor";
pub fn init(vexor: *Vexor) !void {
    _ = try qjs.zig_utils.newModule(
        vexor.ctx,
        module_name,
        .{},
        .{},
        .{},
    );
}

const VexorClass = struct {
    fn constructor(_: *qjs.JSContext, this_obj: qjs.JSValueConst, _: []qjs.JSValueConst) !?qjs.JSValue {
        try qjs.zig_utils.setOpaque(this_obj, try Vexor.init());
        return null;
    }
    fn compile(ctx: *qjs.JSContext, this_obj: qjs.JSValueConst, js_args: []qjs.JSValueConst) !?qjs.JSValue {
        const vexor = qjs.zig_utils.getOpaque(Vexor, this_obj).?;
        const args = try qjs.zig_utils.getArgs(ctx, js_args, &[_]type{ qjs.JSValue, qjs.JSValue, i32 });

        const str = try qjs.zig_utils.toString(ctx, args[0]);
        defer qjs.JS_FreeCString(ctx, str.ptr);
        const filename = try qjs.zig_utils.toString(ctx, args[1]);
        defer qjs.JS_FreeCString(ctx, filename.ptr);
        const strip: u8 = @intCast(args[2]);

        const output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(smp_allocator);
        const error_ = std.ArrayListUnmanaged(u8){};
        defer error_.deinit(smp_allocator);

        try vexor.compile(
            str,
            filename,
            strip,
            output.writer(smp_allocator).any(),
            error_.writer(smp_allocator).any(),
        );
        if (error_.items.len != 0) {
            return qjs.JS_ThrowPlainError(ctx, "%.*s", error_.items.len, error_.items.ptr);
        } else {
            return qjs.JS_NewUint8ArrayCopy(ctx, output.items, output.items.len);
        }
    }
    fn finalizer(_: *qjs.JSRuntime, this_obj: qjs.JSValueConst) void {
        if (qjs.zig_utils.getOpaque(Vexor, this_obj)) |vexor| {
            vexor.deinit();
        }
    }
};
