const std = @import("std");
const Vexor = @import("vexor").Vexor;

const strip = if (@import("builtin").strip_debug_info) 1 else 0;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    const input_path = args[1];
    const output_path = args[2];
    // std.debug.print("{s}\n{s}\n", .{ input_path, output_path });

    const input_str = try std.fs.cwd().readFileAlloc(arena, input_path, std.math.maxInt(usize));
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    const output_writer = output_file.writer();
    // std.debug.print("{any}\n", .{input_str});

    const vexor = try Vexor.init();
    defer vexor.deinit();

    try vexor.compile(
        try std.fmt.allocPrintZ(arena, "{s}", .{input_str}),
        std.fs.path.basename(input_path),
        strip,
        output_writer.any(),
        std.io.getStdErr().writer().any(),
    );
}
