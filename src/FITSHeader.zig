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

    fn validateCard(self: *Self, card: CardImage) !void {
        if (isReservedKeyword(card.keyword)) return error.ReservedKeywordModification;

        // Check if this is the first line and not SIMPLE
        var nkeys: c_int = 0;
        var status: c_int = 0;
        _ = c.fits_get_hdrspace(self.fits_file.fptr, &nkeys, null, &status);
        if (nkeys == 0 and !std.mem.eql(u8, card.keyword, "SIMPLE")) {
            return error.FirstKeywordMustBeSIMPLE;
        }
    }
    pub fn isReservedKeyword(keyword: []const u8) bool {
        const reserved = [_][]const u8{ "SIMPLE", "BITPIX", "NAXIS", "EXTEND" };
        for (reserved) |k| {
            if (std.mem.eql(u8, k, keyword)) return true;
        }
        return false;
    }

    pub fn init(fitsfile: *FitsFile) Self {
        return .{
            .fits_file = fitsfile,
            .allocator = fitsfile.allocator,
        };
    }

    pub fn insertCardImage(self: *Self, card: CardImage) !void {
        try self.validateCard(card);
        var status: c_int = 0;
        const c_keyword = @as([*c]const u8, @ptrCast(card.keyword));
        const value = @as(?*anyopaque, @constCast(@ptrCast(card.value.ptr)));
        const c_comment = if (card.comment) |comment| @as([*c]const u8, @ptrCast(comment)) else null;

        const result = c.fits_update_key(self.fits_file.fptr, c.TSTRING, c_keyword, value, c_comment, &status);
        if (result != 0) return error.CardImageOperationFailed;
    }

    pub fn updateCardImage(self: *Self, _: []const u8, new_card: CardImage) !void {
        try self.validateCard(new_card);
        try self.writeKeyword(new_card.keyword, new_card.value, new_card.comment);
    }
    pub fn deleteCardImage(self: *Self, keyword: []const u8) !void {
        try self.deleteKeyword(keyword);
    }

    fn formatCardImage(self: *Self, card: CardImage) ![]u8 {
        var buf = try self.allocator.alloc(u8, 80);
        errdefer self.allocator.free(buf);

        const value = switch (@typeInfo(@TypeOf(card.value))) {
            .Bool => if (card.value) "T" else "F",
            else => card.value,
        };

        if (card.comment) |comment| {
            _ = try std.fmt.bufPrint(buf, "{s: <8}= {s} / {s}", .{ card.keyword, value, comment });
        } else {
            _ = try std.fmt.bufPrint(buf, "{s: <8}= {s}", .{ card.keyword, value });
        }

        // Pad to 80 chars
        if (buf.len < 80) {
            @memset(buf[std.mem.indexOf(u8, buf, "\x00").?..], ' ');
        }

        return buf;
    }

    pub fn writeString(self: *Self, keyword: []const u8, value: []const u8, comment: ?[]const u8) !void {
        return self.writeKeyword(keyword, value, comment);
    }

    pub fn writeLogical(self: *Self, keyword: []const u8, value: bool, comment: ?[]const u8) !void {
        return self.writeKeyword(keyword, value, comment);
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
        const c_keyword = try u.addNullByte(self.allocator, @ptrCast(keyword));
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
        //std.debug.print("Reading keyword '{s}': status = {}, result = {}\n", .{ keyword, status, result });
        if (status == 202) return error.KeyNotFound; // KEY_NO_EXIST
        if (result != 0 or status != 0) return error.ReadKeywordFailed;

        // Find value length (excluding null terminator and quotes)
        var len: usize = 0;
        while (len < value_buf.len and value_buf[len] != 0) : (len += 1) {}

        //std.debug.print("Value buffer: '{s}' (len: {d})\n", .{ value_buf[0..len], len });
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
        return if (self.getKeyword(keyword)) |_| true else |err| switch (err) {
            error.KeyNotFound => false,
            else => err,
        };
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

// test "Header security checks" {
//     std.debug.print("Running header security checks...", .{});
//     const allocator = std.testing.allocator;

//     var fits_file = try FitsFile.createFits(allocator, "examples/data/secuewewrity_tdedst.fit");
//     defer fits_file.close() catch {};
//     var header = FITSHeader.init(fits_file);

//     // Test 1: First keyword must be SIMPLE
//     try std.testing.expectError(error.FirstKeywordMustBeSIMPLE, header.insertCardImage(.{
//         .keyword = "RANDOM",
//         .value = "value",
//         .comment = null,
//     }));

//     // Test 2: Cannot modify reserved keywords
//     try header.writeKeyword("SIMPLE", true, null);
//     try std.testing.expectError(error.ReservedKeywordModification, header.insertCardImage(.{
//         .keyword = "SIMPLE",
//         .value = "false",
//         .comment = null,
//     }));
// }
