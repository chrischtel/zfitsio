const std = @import("std");
const u = @import("util//util.zig");
const fitsheader = @import("FITSHeader.zig").FITSHeader;

const c = u.c;

/// Defines access modes for FITS files
/// Controls read/write permissions for both header and data
pub const Mode = struct {
    /// If true, file is opened in read-only mode
    READ_ONLY: bool = true,
    /// If true, header modifications are allowed
    ALLOW_HEADER_MODS: bool = false,
    /// If true, data modifications are allowed
    ALLOW_DATA_MODS: bool = false,
};

/// Core struct for FITS file operations
/// Provides functions for file I/O, metadata retrieval, and validation
pub const FitsFile = struct {
    /// Pointer to the underlying CFITSIO file structure
    fptr: *c.fitsfile,
    /// Memory allocator used for dynamic allocations
    allocator: std.mem.Allocator,

    /// Validates that all required FITS headers are present
    /// Returns true if all required headers exist, false otherwise
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: bool indicating if all required headers are present
    pub fn validateRequiredHeaders(self: *FitsFile) !bool {
        var header = fitsheader.init(self);
        const required = [_][]const u8{ "SIMPLE", "BITPIX", "NAXIS" };
        for (required) |key| {
            if (!try header.hasKeyword(key)) return false;
        }

        return true;
    }
    /// Checks if header modifications are allowed based on file mode
    /// Returns error.HeaderModificationNotAllowed if modifications are not permitted
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    pub fn canModifyHeaders(self: *FitsFile) !void {
        if (self.mode.READ_ONLY or !self.mode.ALLOW_HEADER_MODS) {
            return error.HeaderModificationNotAllowed;
        }
    }
    /// Creates a new FITS file
    /// Parameters:
    ///   - allocator: Memory allocator for dynamic allocations
    ///   - path: File path for the new FITS file
    /// Returns: Pointer to new FitsFile instance or error
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
    /// Opens an existing FITS file
    /// Parameters:
    ///   - allocator: Memory allocator for dynamic allocations
    ///   - path: Path to existing FITS file
    ///   - mode: File access mode (e.g., READONLY, READWRITE)
    /// Returns: Pointer to FitsFile instance or error
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
    /// Closes an open FITS file and frees associated resources
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: error if close operation fails
    pub fn close(self: *FitsFile) !void {
        var status: c_int = 0;
        const result = c.fits_close_file(self.fptr, &status);
        self.allocator.destroy(self);
        if (result != 0) return error.CloseFileFailed;
    }
    /// Reads image data from the current HDU
    /// Currently supports only 32-bit integer data
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: Slice containing image data or error
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
    /// Gets the total number of HDUs (Header Data Units) in the file
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: Number of HDUs or error
    pub fn getHDUCount(self: *FitsFile) !usize {
        var hdu_count: c_long = 0;
        var status: c_int = 0;

        const result = c.fits_get_num_hdus(self.fptr, &hdu_count, &status);
        if (result != 0) {
            return error.InvalidFile;
        }

        return @intCast(hdu_count);
    }
    /// Gets the dimensions of the current image HDU
    /// Currently supports only 2D images
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: Array containing [width, height] or error
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
    /// Flushes any pending changes to disk
    /// Parameters:
    ///   - self: Pointer to FitsFile instance
    /// Returns: error if flush operation fails
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
