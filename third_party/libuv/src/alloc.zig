const std = @import("std");
const c = @import("./c.zig");

pub fn replaceAllocator(comptime allocator: std.mem.Allocator) !void {
    const funcs = struct {
        const Header = packed struct {
            size: usize,
        };
        const header_size = @sizeOf(Header);
        fn c_malloc(size: usize) callconv(.c) ?*anyopaque {
            const allocated = allocator.alloc(u8, size + header_size) catch return null;
            const header: *Header = @ptrCast(@alignCast(allocated.ptr));
            header.size = allocated.len;

            return allocated[header_size..].ptr;
        }
        fn c_realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
            if (ptr == null) {
                return c_malloc(size);
            }

            const allocated: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - header_size);
            const header: *Header = @ptrCast(@alignCast(allocated));

            if (size == 0) {
                c_free(ptr);
            }

            const new_allocated = allocator.realloc(allocated[0..header.size], size + header_size) catch return null;
            const new_header: *Header = @ptrCast(@alignCast(new_allocated.ptr));
            new_header.size = new_allocated.len;

            return new_allocated[header_size..].ptr;
        }
        fn c_calloc(count: usize, size: usize) callconv(.c) ?*anyopaque {
            const allocated = allocator.alloc(u8, count * size + header_size) catch return null;
            const header: *Header = @ptrCast(@alignCast(allocated.ptr));
            header.size = allocated.len;

            @memset(allocated[header_size..], 0);

            return allocated[header_size..].ptr;
        }
        fn c_free(ptr: ?*anyopaque) callconv(.c) void {
            if (ptr == null) {
                return;
            }

            const allocated: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - header_size);
            const header: *Header = @ptrCast(@alignCast(allocated));

            allocator.free(allocated[0..header.size]);
        }
    };
    try @import("./error.zig").check(c.uv_replace_allocator(
        funcs.c_malloc,
        funcs.c_realloc,
        funcs.c_calloc,
        funcs.c_free,
    ));
}
