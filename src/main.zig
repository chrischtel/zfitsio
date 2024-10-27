const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var alloc = std.heap.page_allocator;

    _ = try root.testfu(&alloc);
}
