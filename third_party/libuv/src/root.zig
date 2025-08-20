pub usingnamespace @import("./c.zig");
pub const zig_utils = struct {
    pub fn getData(T: type, ptr: anytype) *T {
        return @ptrCast(@alignCast(ptr.*.data));
    }
    pub fn initBuf(buf: anytype) @import("./c.zig").uv_buf_t {
        return .{
            .base = @ptrCast(@constCast(buf.ptr)),
            .len = @intCast(buf.len),
        };
    }
    pub fn bufToSlice(buf: @import("./c.zig").uv_buf_t) []u8 {
        return buf.base[0..buf.len];
    }
    pub usingnamespace @import("./error.zig");
    pub usingnamespace @import("./alloc.zig");
};
