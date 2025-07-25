pub usingnamespace @import("./c.zig");
pub const zig_utils = struct {
    pub fn getData(T: type, ptr: anytype) *T {
        return @ptrCast(@alignCast(ptr.*.data));
    }
    pub usingnamespace @import("./error.zig");
};
