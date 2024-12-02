const std = @import("std");
const u = @import("util//util.zig");
const fitsheader = @import("FITSHeader.zig").FITSHeader;

const c = u.c;

pub const Mode = struct {
    READ_ONLY: bool = true,
    ALLOW_HEADER_MODS: bool = false,
    ALLOW_DATA_MODS: bool = false,
};

pub const FitsFile = struct {
    fptr: *c.fitsfile,
    allocator: std.mem.Allocator,

    pub fn validateRequiredHeaders(self: *FitsFile) !bool {
        var header = fitsheader.init(self);
        const required = [_][]const u8{ "SIMPLE", "BITPIX", "NAXIS" };
        for (required) |key| {
            if (!try header.hasKeyword(key)) return false;
        }

        return true;
    }

    pub fn canModifyHeaders(self: *FitsFile) !void {
        if (self.mode.READ_ONLY or !self.mode.ALLOW_HEADER_MODS) {
            return error.HeaderModificationNotAllowed;
        }
    }

    pub fn createFits(allocator: std.mem.Allocator, path: [*c]const u8) !*FitsFile {
        var status: c_int = 0;

        // Convert input path to slice
        const path_slice = std.mem.span(path);

        // Add ! prefix and null terminator in one allocation
        const c_path = try std.fmt.allocPrint(allocator, "!{s}\x00", .{path_slice});
        defer allocator.free(c_path);

        var fptr: ?*c.fitsfile = null;
        const result = c.fits_create_file(&fptr, @ptrCast(c_path), &status);
        if (result != 0) return error.CreateFileFailed;

        const fits = try allocator.create(FitsFile);
        fits.* = .{
            .fptr = fptr.?,
            .allocator = allocator,
        };
        return fits;
    }

    pub fn open(allocator: std.mem.Allocator, path: [*c]const u8, mode: c_int) !*FitsFile {
        var status: c_int = 0;
        const c_path = try u.addNullByte(allocator, path);
        defer allocator.free(c_path);
        const c_path_c: [*c]const u8 = @ptrCast(c_path);
        var fptr: ?*c.fitsfile = null;

        const result = c.fits_open_file(&fptr, c_path_c, mode, &status);
        if (result != 0) {
            std.debug.print("Open failed with status: {d}\n", .{status});
            return error.OpenFileFailed;
        }

        const fits = try allocator.create(FitsFile);
        fits.* = .{
            .fptr = fptr.?,
            .allocator = allocator,
        };

        return fits;
    }

    pub fn close(self: *FitsFile) !void {
        var status: c_int = 0;
        const result = c.fits_close_file(self.fptr, &status);
        self.allocator.destroy(self);
        if (result != 0) return error.CloseFileFailed;
    }

    pub fn readImage(self: *FitsFile) ![]i32 {
        var status: c_int = 0;
        var anynull: c_int = 0;
        var nullval: i32 = 0;

        const img_len = 1000;
        var img: [img_len]i32 = undefined;

        const result = c.fits_read_img(self.fptr, c.TINT, 1, img_len, &nullval, &img[0], &anynull, &status);
        if (result != 0) return error.ReadImageFailed;

        return img[0..];
    }

    pub fn getHDUCount(self: *FitsFile) !usize {
        var hdu_count: c_long = 0;
        var status: c_int = 0;

        const result = c.fits_get_num_hdus(self.fptr, &hdu_count, &status);
        if (result != 0) {
            return error.InvalidFile;
        }

        return @intCast(hdu_count);
    }

    pub fn getImageDimensions(self: *FitsFile) ![2]usize {
        var status: c_int = 0;
        const naxis = 2;
        var dims: [naxis]c_long = undefined;

        const result = c.fits_get_img_size(self.fptr, naxis, &dims[0], &status);
        if (result != 0) {
            return error.InvalidImageData;
        }

        return .{
            @intCast(dims[0]),
            @intCast(dims[1]),
        };
    }

    pub fn flush(self: *FitsFile) !void {
        var status: c_int = 0;
        const result = c.fits_flush_file(self.fptr, &status);
        if (result != 0) return error.FlushFailed;
    }
};

test "FitsFile open and metadata retrieval" {
    const allocator = std.testing.allocator;

    std.debug.print("\nRunning FitsFile test...\n", .{});
    var fits_file = try FitsFile.open(allocator, "examples/data/M51_lum.fit", c.READONLY);
    defer fits_file.close() catch |err| {
        std.debug.print("Failed to close FITS fiele: {}\n", .{err});
    };

    const hdu_count = try fits_file.getHDUCount();
    try std.testing.expect(hdu_count > 0);

    const dimensions = try fits_file.getImageDimensions();
    try std.testing.expect(dimensions[0] > 0);
    try std.testing.expect(dimensions[1] > 0);
}
