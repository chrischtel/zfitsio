const std = @import("std");
pub const c = @import("../wrapper.zig");

pub fn addNullByte(allocator: std.mem.Allocator, s: [*c]const u8) ![]const u8 {
    const ss = std.mem.span(s);
    const result = try allocator.alloc(u8, ss.len + 1);
    @memcpy(result[0..ss.len], ss);
    result[ss.len] = 0;
    return result;
}
