const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    _ = try root.testfu();
}
