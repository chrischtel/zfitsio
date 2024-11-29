const std = @import("std");
const FitsFile = @import("fitsfile.zig").FitsFile;
const u = @import("util/util.zig");
const c = u.c;
pub const HeaderError = error{
    ReadKeywordFailed,
    WriteKeywordFailed,
    KeyNotFound,
    InvalidKeywordFormat,
    InvalidDataType,
    AllocateFailed,
};

pub const CardImage = struct {
    keyword: []const u8,
    value: []const u8,
    comment: ?[]const u8,
};

pub const Coordinates = struct {
    ra: f64,
    dec: f64,
    equinox: f64,
};

pub const FITSHeader = struct {
    fits_file: *FitsFile,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(fitsfile: *FitsFile) Self {
        return .{
            .fits_file = fitsfile,
            .allocator = fitsfile.allocator,
        };
    }

    pub fn writeKeyword(self: *Self, keyword: []const u8, value: anytype, comment: ?[]const u8) !void {
        var status: c_int = 0;
        const c_keyword = @as([*c]const u8, @ptrCast(keyword));
        const c_comment = if (comment) |cc| @as([*c]const u8, @ptrCast(cc)) else null;

        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Pointer, .Array => {
                // For string values, we need to quote them for FITS format
                var quoted_value: [81]u8 = undefined;
                const value_str = if (T == []const u8) value else @as([]const u8, value);
                const formatted = std.fmt.bufPrint(&quoted_value, "'{s}'", .{value_str}) catch return error.ValueTooLong;

                const result = c.fits_update_key_str(self.fits_file.fptr, c_keyword, @ptrCast(formatted), c_comment, &status);
                if (result != 0) return error.WriteKeywordFailed;
                return;
            },
            else => switch (T) {
                bool => {
                    const result = c.fits_update_key_log(self.fits_file.fptr, c_keyword, @intFromBool(value), c_comment, &status);
                    if (result != 0) return error.WriteKeywordFailed;
                },
                comptime_int, i32, i64 => {
                    const result = c.fits_update_key_lng(self.fits_file.fptr, c_keyword, @intCast(value), c_comment, &status);
                    if (result != 0) return error.WriteKeywordFailed;
                },
                comptime_float, f32, f64 => {
                    const result = c.fits_update_key_dbl(self.fits_file.fptr, c_keyword, @floatCast(value), 6, c_comment, &status);
                    if (result != 0) return error.WriteKeywordFailed;
                },
                else => return error.InvalidDataType,
            },
        }
    }

    pub fn deleteKeyword(self: *Self, keyword: []const u8) !void {
        var status: c_int = 0;
        const c_keyword = try u.addNullByte(self.allocator, keyword);
        defer self.allocator.free(c_keyword);

        const result = c.fits_delete_key(self.fits_file.fptr, @ptrCast(c_keyword), &status);
        if (result != 0) return error.DeleteKeywordFailed;
    }

    pub fn getKeyword(self: *Self, keyword: []const u8) ![]const u8 {
        var status: c_int = 0;
        const c_keyword = try u.addNullByte(self.allocator, @ptrCast(keyword));
        defer self.allocator.free(c_keyword);

        var value_buf: [71]u8 = undefined;
        var comment_buf: [71]u8 = undefined;

        const result = c.fits_read_keyword(
            self.fits_file.fptr,
            @ptrCast(c_keyword),
            &value_buf,
            &comment_buf,
            &status,
        );
        std.debug.print("Reading keyword '{s}': status = {}, result = {}\n", .{ keyword, status, result });
        if (status == 202) return error.KeyNotFound; // KEY_NO_EXIST
        if (result != 0 or status != 0) return error.ReadKeywordFailed;

        // Find value length (excluding null terminator and quotes)
        var len: usize = 0;
        while (len < value_buf.len and value_buf[len] != 0) : (len += 1) {}

        std.debug.print("Value buffer: '{s}' (len: {d})\n", .{ value_buf[0..len], len });
        // Remove surrounding quotes if present
        var start: usize = 0;
        var end: usize = len;
        if (len > 0 and value_buf[0] == '\'') {
            start = 1;
            if (end > 1) end -= 1; // Only remove trailing quote if we have more than one character
        }

        const value = try self.allocator.alloc(u8, end - start);
        @memcpy(value, value_buf[start..end]);
        return value;
    }

    pub fn hasKeyword(self: *Self, keyword: []const u8) !bool {
        return self.getKeyword(keyword) catch |err| {
            return switch (err) {
                error.KeyNotFound => false,
                else => err,
            };
        } != null;
    }

    pub fn printAllHeaders(self: *Self) !void {
        var status: c_int = 0;
        var nkeys: c_int = 0;
        _ = c.fits_get_hdrspace(self.fits_file.fptr, &nkeys, null, &status);
        if (status != 0) return error.ReadKeywordFailed;

        std.debug.print("\nAll FITS Headers:\n", .{});
        std.debug.print("----------------\n", .{});

        var i: c_int = 1;
        while (i <= nkeys) : (i += 1) {
            var card: [81]u8 = undefined;
            status = 0;
            _ = c.fits_read_record(self.fits_file.fptr, i, &card, &status);
            if (status != 0) continue;

            // Find the actual length of the card (excluding trailing nulls)
            var len: usize = 0;
            while (len < card.len and card[len] != 0) : (len += 1) {}

            std.debug.print("{d}: {s}\n", .{ i, card[0..len] });
        }
        std.debug.print("----------------\n", .{});
    }
};
