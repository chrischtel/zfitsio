const std = @import("std");
const c = @import("utility.zig").c;

/// Adds a null terminator to a C-style string.
///
/// - `allocator`: Allocator used to create the new buffer with a null terminator.
/// - `s`: Original C-style string without a null terminator.
/// Returns: A new `[]const u8` slice with a null byte appended at the end.
fn addNullByte(allocator: *std.mem.Allocator, s: [*c]const u8) ![]const u8 {
    const ss = std.mem.span(s); // Calculate the length of the string
    const result = try allocator.alloc(u8, ss.len + 1); // Allocate space for the original string + null byte
    @memcpy(result[0..ss.len], ss); // Copy original string into result buffer
    result[ss.len] = 0; // Add null terminator
    return result;
}

/// A wrapper struct around a FITS file, providing methods to open, close,
/// and retrieve information from the file.
pub const FitsFile = struct {
    fptr: *c.fitsfile, // Pointer to the C FITS file structure

    /// Opens a FITS file at the given path in the specified mode.
    ///
    /// - `allocator`: Allocator used for managing memory.
    /// - `path`: Path to the FITS file.
    /// - `mode`: Mode to open the file (e.g., `c.READONLY`).
    /// Returns: A `FitsFile` instance on success, or an error otherwise.
    pub fn open(allocator: *std.mem.Allocator, path: [*c]const u8, mode: c_int) !*FitsFile {
        var status: c_int = 0;

        // Ensure the path is null-terminated
        const c_path = try addNullByte(allocator, path);
        defer allocator.free(c_path); // Free allocated memory for path

        // Cast to the correct C pointer type
        const c_path_c: [*c]const u8 = @ptrCast(c_path);
        var fptr: ?*c.fitsfile = null;

        // Open the FITS file using the cfitsio library function
        const result = c.fits_open_file(&fptr, c_path_c, mode, &status);
        if (result != 0) return error.OpenFileFailed;

        // Wrap the opened FITS file in a FitsFile struct
        var fitsFile = FitsFile{ .fptr = fptr.? };
        return &fitsFile;
    }

    /// Closes the FITS file, freeing resources.
    ///
    /// Returns: `void` on success, or an error if the file couldn't be closed.
    pub fn close(self: *FitsFile) !void {
        var status: c_int = 0;
        const result = c.fits_close_file(self.fptr, &status);
        if (result != 0) return error.CloseFileFailed;
    }

    /// Reads image data from the FITS file.
    ///
    /// Returns: An array of `i32` image data or an error if the read fails.
    pub fn readImage(self: *FitsFile) ![]i32 {
        var status: c_int = 0;
        var anynull: c_int = 0;
        var nullval: i32 = 0;

        const img_len = 1000; // Set based on expected image size
        var img: [img_len]i32 = undefined;

        // Read image data as integers
        const result = c.fits_read_img(self.fptr, c.TINT, 1, img_len, &nullval, &img[0], &anynull, &status);
        if (result != 0) return error.ReadImageFailed;

        return img[0..]; // Return the image data as a slice
    }

    /// Retrieves the number of Header Data Units (HDUs) in the FITS file.
    ///
    /// Returns: The HDU count as `usize`, or an error if retrieval fails.
    pub fn getHDUCount(self: *FitsFile) !usize {
        var hdu_count: c_long = 0;
        var status: c_int = 0;

        const result = c.fits_get_num_hdus(self.fptr, &hdu_count, &status);
        if (result != 0) {
            return error.InvalidFile;
        }

        // Cast the HDU count to `usize` and return it
        const hdu_c: usize = @intCast(hdu_count);
        return hdu_c;
    }

    /// Gets the image dimensions of the primary image HDU in the FITS file.
    ///
    /// Returns: A fixed-size array `[2]usize` with `[width, height]`, or an error if retrieval fails.
    pub fn getImageDimensions(self: *FitsFile) ![]usize {
        var status: c_int = 0;
        const naxis = 2; // Number of dimensions (width and height)
        var dims: [naxis]c_long = undefined;

        const result = c.fits_get_img_size(self.fptr, naxis, &dims[0], &status);
        if (result != 0) {
            return error.InvalidImageData;
        }

        // Cast each dimension to usize
        const dim_x: usize = @intCast(dims[0]);
        const dim_y: usize = @intCast(dims[1]);
        return [_]usize{ dim_x, dim_y };
    }
};

// Test block to verify FitsFile functionality
test "FitsFile open and metadata retrieval" {
    const allocator = std.testing.allocator;

    // Open the FITS file for testing
    var fits_file = try FitsFile.open(allocator, "test.fit", c.READONLY);
    defer fits_file.close() catch |err| {
        std.debug.print("Failed to close FITS file: {}\n", .{err});
    };

    // Test retrieving the HDU count
    const hdu_count = try fits_file.getHDUCount();
    std.testing.expect(hdu_count > 0); // Expect at least one HDU

    // Test retrieving image dimensions
    const dimensions = try fits_file.getImageDimensions();
    std.testing.expect(dimensions.len == 2); // Ensure dimensions have two values
    std.testing.expect(dimensions[0] > 0); // Expect non-zero width
    std.testing.expect(dimensions[1] > 0); // Expect non-zero height

    // Uncomment to test image type if implemented
    // const img_type = try fits_file.getImageType();
    // std.testing.expect(img_type == c.FLOAT_IMG or img_type == c.SHORT_IMG or img_type == c.LONG_IMG);
}
