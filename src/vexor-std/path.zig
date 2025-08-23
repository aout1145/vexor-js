const std = @import("std");
const qjs = @import("qjs");
const uv = @import("uv");

const Vexor = @import("vexor").Vexor;

// dep: std:os
pub const module_name = "std:path";
pub fn init(vexor: *Vexor) !void {
    try vexor.addModule(module_name, @embedFile("path.js.compiled"));
}
