//! FITS Data Types Module
//! Handles all FITS data type conversions, validations and manipulations.
//!
//! Common data types include:
//! - Basic types (integers, floats)
//! - Logical values
//! - String data
//! - Complex numbers

const std = @import("std");

/// FITS Data Type Handling
/// This module provides functionality for handling FITS data types and their conversion
/// to native Zig types.
/// Represents the standard FITS data types as defined in the FITS standard.
/// Each variant corresponds to a specific data type with its associated type code.
pub const FitsType = enum(i32) {
    /// Logical value stored as a single bit
    TBIT = 1,
    /// 8-bit unsigned byte
    TBYTE = 11,
    /// Logical value stored as a full byte
    TLOGICAL = 14,
    /// ASCII character string
    TSTRING = 16,
    /// 16-bit signed integer
    TSHORT = 21,
    /// 32-bit signed integer
    TINT = 31,
    /// 64-bit signed integer
    TLONG = 41,
    /// 32-bit floating point number
    TFLOAT = 42,
    /// 64-bit floating point number
    TDOUBLE = 82,
};

/// Maps a FITS data type to its corresponding Zig type.
///
/// Parameters:
///  - datatype: The FITS data type to convert
///
/// Returns: The corresponding Zig type
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

/// Reads FITS binary data and converts it to a Zig slice of the specified type.
/// Handles byte-swapping as FITS data is stored in big-endian format.
///
/// Parameters:
///  - allocator: Memory allocator for the result array
///  - T: The Zig type to convert the data to
///  - data: Raw bytes of FITS data
///  - datatype: The FITS data type of the input data
///
/// Returns: A slice of converted values of type T
///
/// Errors:
///  - InvalidDataSize: If the input data size is not a multiple of the type size
///  - OutOfMemory: If allocation fails
///  - Type mismatch at compile time if T doesn't match the FITS type
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

/// Returns the size in bytes for a given FITS data type.
///
/// Parameters:
///  - datatype: The FITS data type to get the size for
///
/// Returns: Size in bytes for the specified type
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

    // Test integer conversion (42 in big-endian format)
    var int_data = [_]u8{ 0x00, 0x00, 0x00, 0x2A };
    const ints = try readFitsData(allocator, i32, &int_data, .TINT);
    defer allocator.free(ints);
    try std.testing.expectEqual(ints[0], 42);

    // Test boolean conversion
    var bool_data = [_]u8{1};
    const bools = try readFitsData(allocator, bool, &bool_data, .TLOGICAL);
    defer allocator.free(bools);
    try std.testing.expectEqual(bools[0], true);
}
