pub const timer = @import("./timer.zig");
pub const tty = @import("./tty.zig");

test {
    _ = @import("std").testing.refAllDecls(@This());
}
