const std = @import("std");

pub const FitsType = enum(i32) {
    TBIT = 1, // Logical value stored as bit
    TBYTE = 11, // 8-bit byte
    TLOGICAL = 14, // Logical value stored as byte
    TSTRING = 16, // Character string
    TSHORT = 21, // 16-bit integer
    TINT = 31, // 32-bit integer
    TLONG = 41, // 64-bit integer
    TFLOAT = 42, // 32-bit floating point
    TDOUBLE = 82, // 64-bit floating point
};

pub fn getZigType(comptime datatype: FitsType) type {
    return switch (datatype) {
        .TBIT, .TLOGICAL => bool,
        .TBYTE, .TSTRING => u8,
        .TSHORT => i16,
        .TINT => i32,
        .TLONG => i64,
        .TFLOAT => f32,
        .TDOUBLE => f64,
    };
}

pub fn readFitsData(
    allocator: std.mem.Allocator,
    comptime T: type,
    data: []u8,
    comptime datatype: FitsType,
) ![]T {
    if (T != getZigType(datatype)) {
        @compileError("Type mismatch: expected " ++ @typeName(getZigType(datatype)) ++ " but got " ++ @typeName(T));
    }

    const size = getSizeForType(datatype);
    if (data.len % size != 0) return error.InvalidDataSize;

    const count = data.len / size;
    const result = try allocator.alloc(T, count);
    errdefer allocator.free(result);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const slice = data[i * size .. (i + 1) * size];
        result[i] = switch (datatype) {
            .TBIT, .TLOGICAL => slice[0] != 0,
            .TBYTE, .TSTRING => slice[0],
            .TSHORT => @byteSwap(std.mem.readInt(i16, slice[0..2], .little)),
            .TINT => @byteSwap(std.mem.readInt(i32, slice[0..4], .little)),
            .TLONG => @byteSwap(std.mem.readInt(i64, slice[0..8], .little)),
            .TFLOAT => @bitCast(@byteSwap(std.mem.readInt(u32, slice[0..4], .little))),
            .TDOUBLE => @bitCast(@byteSwap(std.mem.readInt(u64, slice[0..8], .little))),
        };
    }
    return result;
}

pub fn getSizeForType(datatype: FitsType) usize {
    return switch (datatype) {
        .TBIT, .TLOGICAL, .TBYTE, .TSTRING => 1,
        .TSHORT => 2,
        .TINT, .TFLOAT => 4,
        .TLONG, .TDOUBLE => 8,
    };
}

test "FITS data type conversion" {
    std.debug.print("Running datatyp tests", .{});
    const allocator = std.testing.allocator;

    var int_data = [_]u8{ 0x00, 0x00, 0x00, 0x2A }; // 42 in big-endian
    const ints = try readFitsData(allocator, i32, &int_data, .TINT);
    defer allocator.free(ints);
    try std.testing.expectEqual(ints[0], 42);

    var bool_data = [_]u8{1};
    const bools = try readFitsData(allocator, bool, &bool_data, .TLOGICAL);
    defer allocator.free(bools);
    try std.testing.expectEqual(bools[0], true);
}
