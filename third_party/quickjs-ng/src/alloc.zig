const std = @import("std");
const c = @import("./c.zig");

/// then pass a pointer to std.mem.Allocator as opaque to JS_NewRuntime2
pub const malloc_functions: c.JSMallocFunctions = .{
    .js_malloc = &c_malloc,
    .js_calloc = &c_calloc,
    .js_realloc = &c_realloc,
    .js_free = &c_free,
    .js_malloc_usable_size = &c_malloc_usable_size,
};

const Header = packed struct {
    size: usize,
};
const header_size = @sizeOf(Header);
fn c_malloc(@"opaque": ?*const anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(@"opaque" orelse unreachable));

    const allocated = allocator.alloc(u8, size + header_size) catch return null;
    const header: *Header = @ptrCast(@alignCast(allocated.ptr));
    header.size = allocated.len;

    return allocated[header_size..].ptr;
}
fn c_calloc(@"opaque": ?*const anyopaque, count: usize, size: usize) callconv(.c) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(@"opaque" orelse unreachable));

    const allocated = allocator.alloc(u8, count * size + header_size) catch return null;
    const header: *Header = @ptrCast(@alignCast(allocated.ptr));
    header.size = allocated.len;

    @memset(allocated[header_size..], 0);

    return allocated[header_size..].ptr;
}
fn c_realloc(@"opaque": ?*const anyopaque, ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(@"opaque" orelse unreachable));

    if (ptr == null) {
        return c_malloc(@"opaque", size);
    }

    const allocated: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - header_size);
    const header: *Header = @ptrCast(@alignCast(allocated));

    if (size == 0) {
        c_free(@"opaque", ptr);
    }

    const new_allocated = allocator.realloc(allocated[0..header.size], size + header_size) catch return null;
    const new_header: *Header = @ptrCast(@alignCast(new_allocated.ptr));
    new_header.size = new_allocated.len;

    return new_allocated[header_size..].ptr;
}
fn c_free(@"opaque": ?*const anyopaque, ptr: ?*anyopaque) callconv(.c) void {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(@"opaque" orelse unreachable));

    if (ptr == null) {
        return;
    }

    const allocated: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - header_size);
    const header: *Header = @ptrCast(@alignCast(allocated));

    allocator.free(allocated[0..header.size]);
}
fn c_malloc_usable_size(ptr: ?*const anyopaque) callconv(.c) usize {
    if (ptr == null) {
        return 0;
    }

    const allocated: [*]const u8 = @ptrFromInt(@intFromPtr(ptr) - header_size);
    const header: *const Header = @ptrCast(@alignCast(allocated));

    return header.size;
}
