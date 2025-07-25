pub const timer = @import("./timer.zig");

test {
    _ = @import("std").testing.refAllDecls(@This());
}
