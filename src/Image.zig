const std = @import("std");
const FitsType = @import("datatypes.zig").FitsType;
const FitsFile = @import("fitsfile.zig").FitsFile;
const FITSHeader = @import("FITSHeader.zig").FITSHeader;

const c = @import("util/util.zig").c;

/// Comprehensive error set for image operations
pub const ImageError = error{
    // File operations
    ReadImageFailed,
    WriteImageFailed,
    InvalidImageType,
    UnsupportedImageType,
    UnsupportedBitpix,

    OutOfMemory,

    // Data operations
    NullData,
    InvalidDataSize,
    InvalidDimensions,
    DataAllocationFailed,

    // Value errors
    NaNValue,
    InfinityValue,
    ValueOutOfRange,

    // WCS errors
    InvalidWCSParameters,
    WCSReadError,
    WCSWriteError,

    // Section errors
    SectionOutOfBounds,
    InvalidSectionBounds,

    // Memory errors
    AllocationFailed,
    DeallocationFailed,

    // General errors
    EmptyData,
    InvalidOperation,
};

/// Add error context to operations
pub const ErrorContext = struct {
    operation: []const u8,
    details: ?[]const u8 = null,
    source_error: ?anyerror = null,
};

/// Represents a rectangular section of an image defined by x and y coordinates
/// Used for extracting subregions from larger images
pub const ImageSection = struct {
    x_start: usize,
    x_end: usize,
    y_start: usize,
    y_end: usize,

    /// Validates that the section boundaries are within the given image dimensions
    /// and that start coordinates are less than end coordinates
    /// Returns ImageError.SectionOutOfBounds if coordinates exceed image dimensions
    /// Returns ImageError.InvalidSectionBounds if start >= end for either axis
    pub fn validate(self: ImageSection, width: usize, height: usize) !void {
        if (self.x_end > width or self.y_end > height) {
            return ImageError.SectionOutOfBounds;
        }
        if (self.x_start >= self.x_end or self.y_start >= self.y_end) {
            return ImageError.InvalidSectionBounds;
        }
    }
};

/// Represents World Coordinate System (WCS) parameters for converting between
/// pixel coordinates and physical world coordinates
pub const PhysicalCoords = struct {
    crval: f64,
    cdelt: f64,
    crpix: f64,

    /// Converts from pixel coordinate to world coordinate using WCS parameters
    pub fn pixelToWorld(self: PhysicalCoords, pixel: f64) f64 {
        return self.crval + (pixel - self.crpix) * self.cdelt;
    }

    /// Converts from world coordinate to pixel coordinate using WCS parameters
    pub fn worldToPixel(self: PhysicalCoords, world: f64) f64 {
        return (world - self.crval) / self.cdelt + self.crpix;
    }
};

/// Main struct for handling FITS image operations
/// Supports 32-bit and 64-bit floating point image data
/// Includes WCS information for coordinate transformations
pub const ImageOperations = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    data_type: FitsType,
    data: union {
        i8: []i8,
        i16: []i16,
        i32: []i32,
        i64: []i64,
        u8: []u8,
        u16: []u16,
        u32: []u32,
        u64: []u64,
        f32: []f32,
        f64: []f64,
    },
    x_axis: PhysicalCoords,
    y_axis: PhysicalCoords,

    /// Creates a new ImageOperations instance with specified dimensions and data type
    /// Allocates memory for image data and initializes WCS parameters to default values
    /// Returns ImageError.UnsupportedDataType if data_type is not TFLOAT or TDOUBLE
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, data_type: FitsType) !ImageOperations {
        // if (data_type != .TFLOAT and data_type != .TDOUBLE) {
        //     return ImageError.UnsupportedDataType;
        // }
        std.debug.print("Initializing with data_type: {}\n", .{data_type}); // Add this

        var self = ImageOperations{
            .allocator = allocator,
            .width = width,
            .height = height,
            .data_type = data_type,
            .data = undefined,
            .x_axis = PhysicalCoords{ .crval = 0, .cdelt = 1, .crpix = 1 },
            .y_axis = PhysicalCoords{ .crval = 0, .cdelt = 1, .crpix = 1 },
        };
        // Remove this check since we now support more types
        // if (data_type != .TFLOAT and data_type != .TDOUBLE) {
        //     return ImageError.UnsupportedDataType;
        // }

        switch (data_type) {
            .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
            .TBYTE => {
                self.data = .{ .i8 = try allocator.alloc(i8, width * height) };
                @memset(self.data.i8, 0);
            },
            .TSHORT => {
                self.data = .{ .i16 = try allocator.alloc(i16, width * height) };
                @memset(self.data.i16, 0);
            },
            .TINT => {
                self.data = .{ .i32 = try allocator.alloc(i32, width * height) };
                @memset(self.data.i32, 0);
            },
            .TLONG => {
                self.data = .{ .i64 = try allocator.alloc(i64, width * height) };
                @memset(self.data.i64, 0);
            },
            .UTBYTE => {
                self.data = .{ .u8 = try allocator.alloc(u8, width * height) };
                @memset(self.data.u8, 0);
            },
            .UTSHORT => {
                self.data = .{ .u16 = try allocator.alloc(u16, width * height) };
                @memset(self.data.u16, 0);
            },
            .UTINT => {
                self.data = .{ .u32 = try allocator.alloc(u32, width * height) };
                @memset(self.data.u32, 0);
            },
            .UTLONG => {
                self.data = .{ .u64 = try allocator.alloc(u64, width * height) };
                @memset(self.data.u64, 0);
            },
            .TFLOAT => {
                self.data = .{ .f32 = try allocator.alloc(f32, width * height) };
                @memset(self.data.f32, 0);
            },
            .TDOUBLE => {
                self.data = .{ .f64 = try allocator.alloc(f64, width * height) };
                @memset(self.data.f64, 0);
            },
        }

        return self;
    }

    /// Creates an ImageOperations instance from an existing FITS file
    /// Reads image data and WCS information from the file
    /// Returns error if image type is unsupported or reading fails
    pub fn fromFitsFile(allocator: std.mem.Allocator, fits: *FitsFile) !ImageOperations {
        // Get image dimensions
        //const dims = try fits.getImageDimensions();
        const dims = fits.getImageDimensions() catch {
            return ImageError.InvalidDimensions;
        };

        // Determine data type and create image
        var status: c_int = 0;
        var bitpix: c_int = undefined;
        _ = c.fits_get_img_type(fits.fptr, &bitpix, &status);
        if (status != 0) return ImageError.InvalidImageType;
        std.debug.print("BITPIX value from file: {}\n", .{bitpix}); // Add this debug line

        const data_type: FitsType = switch (bitpix) {
            8 => .TBYTE, // 8-bit byte (signed char)
            16 => .TSHORT, // 16-bit integer
            32 => .TINT, // 32-bit integer
            64 => .TLONG, // 64-bit integer
            -8 => .UTBYTE, // unsigned 8-bit
            -16 => .UTSHORT, // unsigned 16-bit
            -32 => .TFLOAT, // 32-bit float
            -64 => .TDOUBLE, // 64-bit double
            else => return ImageError.UnsupportedBitpix,
        };
        std.debug.print("Creating image with type: {}\n", .{data_type});

        var img = ImageOperations.init(allocator, dims[0], dims[1], data_type) catch |err| {
            return switch (err) {
                ImageError.OutOfMemory => ImageError.AllocationFailed,
                else => ImageError.InvalidOperation,
            };
        };

        errdefer img.deinit();

        // Read image data
        var anynull: c_int = 0;
        switch (data_type) {
            .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
            .TBYTE => {
                var nullval: i8 = 0;
                const result = c.fits_read_img(fits.fptr, c.TBYTE, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.i8[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .UTBYTE => {
                var nullval: u8 = 0;
                const result = c.fits_read_img(fits.fptr, c.TBYTE, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.u8[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .TSHORT => {
                var nullval: i16 = 0;
                const result = c.fits_read_img(fits.fptr, c.TSHORT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.i16[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .UTSHORT => {
                var nullval: u16 = 0;
                const result = c.fits_read_img(fits.fptr, c.TSHORT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.u16[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .TINT => {
                var nullval: i32 = 0;
                const result = c.fits_read_img(fits.fptr, c.TINT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.i32[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .UTINT => {
                var nullval: u32 = 0;
                const result = c.fits_read_img(fits.fptr, c.TINT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.u32[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .TLONG => {
                var nullval: i64 = 0;
                const result = c.fits_read_img(fits.fptr, c.TLONG, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.i64[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .UTLONG => {
                var nullval: u64 = 0;
                const result = c.fits_read_img(fits.fptr, c.TLONG, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.u64[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .TFLOAT => {
                var nullval: f32 = 0;
                const result = c.fits_read_img(fits.fptr, c.TFLOAT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.f32[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
            .TDOUBLE => {
                var nullval: f64 = 0;
                const result = c.fits_read_img(fits.fptr, c.TDOUBLE, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.f64[0], &anynull, &status);
                if (result != 0) return ImageError.ReadImageFailed;
            },
        }

        // Read WCS information with error handling
        img.readWCSFromHeader(fits) catch |err| {
            logError(ImageError.WCSReadError, .{
                .operation = "fromFitsFile",
                .details = "Failed to read WCS information",
                .source_error = err,
            });
            return ImageError.WCSReadError;
        };

        return img;
    }

    /// Reads World Coordinate System (WCS) parameters from FITS header
    /// Sets default values if WCS keywords are not found
    fn readWCSFromHeader(self: *ImageOperations, fits: *FitsFile) !void {
        var header = FITSHeader.init(fits);

        // Try to read WCS keywords for X axis
        if (header.getKeyword("CRVAL1")) |value_str| {
            self.x_axis.crval = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.x_axis.crval = 0;
        }

        if (header.getKeyword("CDELT1")) |value_str| {
            self.x_axis.cdelt = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.x_axis.cdelt = 1;
        }

        if (header.getKeyword("CRPIX1")) |value_str| {
            self.x_axis.crpix = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.x_axis.crpix = 1;
        }

        // Try to read WCS keywords for Y axis
        if (header.getKeyword("CRVAL2")) |value_str| {
            self.y_axis.crval = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.y_axis.crval = 0;
        }

        if (header.getKeyword("CDELT2")) |value_str| {
            self.y_axis.cdelt = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.y_axis.cdelt = 1;
        }

        if (header.getKeyword("CRPIX2")) |value_str| {
            self.y_axis.crpix = try std.fmt.parseFloat(f64, value_str);
        } else |_| {
            self.y_axis.crpix = 1;
        }
    }

    /// Saves the image data and WCS information to a FITS file
    /// Returns error if writing fails
    pub fn saveToFits(self: *const ImageOperations, fits: *FitsFile) !void {
        var status: c_int = 0;
        const size = self.width * self.height;
        switch (self.data_type) {
            .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
            .TBYTE => {
                const result = c.fits_write_img(fits.fptr, c.TBYTE, 1, @intCast(size), &self.data.i8[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .UTBYTE => {
                const result = c.fits_write_img(fits.fptr, c.TBYTE, 1, @intCast(size), &self.data.u8[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .TSHORT => {
                const result = c.fits_write_img(fits.fptr, c.TSHORT, 1, @intCast(size), &self.data.i16[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .UTSHORT => {
                const result = c.fits_write_img(fits.fptr, c.TSHORT, 1, @intCast(size), &self.data.u16[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .TINT => {
                const result = c.fits_write_img(fits.fptr, c.TINT, 1, @intCast(size), &self.data.i32[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .UTINT => {
                const result = c.fits_write_img(fits.fptr, c.TINT, 1, @intCast(size), &self.data.u32[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .TLONG => {
                const result = c.fits_write_img(fits.fptr, c.TLONG, 1, @intCast(size), &self.data.i64[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .UTLONG => {
                const result = c.fits_write_img(fits.fptr, c.TLONG, 1, @intCast(size), &self.data.u64[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .TFLOAT => {
                const result = c.fits_write_img(fits.fptr, c.TFLOAT, 1, @intCast(size), &self.data.f32[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
            .TDOUBLE => {
                const result = c.fits_write_img(fits.fptr, c.TDOUBLE, 1, @intCast(size), &self.data.f64[0], &status);
                if (result != 0) return ImageError.WriteImageFailed;
            },
        }

        // Write WCS information using FITSHeader
        var header = FITSHeader.init(fits);

        const bitpix: i32 = switch (self.data_type) {
            .TBIT, .TLOGICAL, .TSTRING => unreachable, // Already handled by ImageError.UnsupportedImageType above
            .TBYTE => 8,
            .TSHORT => 16,
            .TINT => 32,
            .TLONG => 64,
            .UTBYTE => -8,
            .UTSHORT => -16,
            .UTINT => -32,
            .UTLONG => -64,
            .TFLOAT => -32,
            .TDOUBLE => -64,
        };

        try header.writeKeyword("BITPIX", bitpix, "Data type");

        try header.writeKeyword("CRVAL1", self.x_axis.crval, "Reference value for X axis");
        try header.writeKeyword("CDELT1", self.x_axis.cdelt, "Scale for X axis");
        try header.writeKeyword("CRPIX1", self.x_axis.crpix, "Reference pixel for X axis");

        try header.writeKeyword("CRVAL2", self.y_axis.crval, "Reference value for Y axis");
        try header.writeKeyword("CDELT2", self.y_axis.cdelt, "Scale for Y axis");
        try header.writeKeyword("CRPIX2", self.y_axis.crpix, "Reference pixel for Y axis");

        try fits.flush();
    }

    /// Frees allocated memory for image data
    pub fn deinit(self: *ImageOperations) void {
        switch (self.data_type) {
            .TBIT, .TLOGICAL, .TSTRING => {}, // These types are not supported for images
            .TBYTE => self.allocator.free(self.data.i8),
            .TSHORT => self.allocator.free(self.data.i16),
            .TINT => self.allocator.free(self.data.i32),
            .TLONG => self.allocator.free(self.data.i64),
            .UTBYTE => self.allocator.free(self.data.u8),
            .UTSHORT => self.allocator.free(self.data.u16),
            .TFLOAT => self.allocator.free(self.data.f32),
            .TDOUBLE => self.allocator.free(self.data.f64),
            .UTLONG => self.allocator.free(self.data.u64),
            .UTINT => self.allocator.free(self.data.u32),
        }
    }

    /// Writes raw image data to a file in big-endian byte order
    /// Useful for debugging or external processing
    pub fn writeImage(self: *const ImageOperations, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();

        switch (self.data_type) {
            .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
            .TBYTE => {
                for (self.data.i8) |value| {
                    const bytes = @as(u8, @bitCast(value));
                    try writer.writeInt(u8, bytes, .big);
                }
            },
            .TSHORT => {
                for (self.data.i16) |value| {
                    try writer.writeInt(i16, @byteSwap(value), .big);
                }
            },
            .TINT => {
                for (self.data.i32) |value| {
                    try writer.writeInt(i32, @byteSwap(value), .big);
                }
            },
            .TLONG => {
                for (self.data.i64) |value| {
                    try writer.writeInt(i64, @byteSwap(value), .big);
                }
            },
            .UTBYTE => {
                for (self.data.u8) |value| {
                    try writer.writeInt(u8, value, .big);
                }
            },
            .UTSHORT => {
                for (self.data.u16) |value| {
                    try writer.writeInt(u16, @byteSwap(value), .big);
                }
            },
            .UTINT => {
                for (self.data.u32) |value| {
                    try writer.writeInt(u32, @byteSwap(value), .big);
                }
            },
            .UTLONG => {
                for (self.data.u64) |value| {
                    try writer.writeInt(u64, @byteSwap(value), .big);
                }
            },
            .TFLOAT => {
                for (self.data.f32) |value| {
                    const bytes = @as(u32, @bitCast(value));
                    try writer.writeInt(u32, @byteSwap(bytes), .big);
                }
            },
            .TDOUBLE => {
                for (self.data.f64) |value| {
                    const bytes = @as(u64, @bitCast(value));
                    try writer.writeInt(u64, @byteSwap(bytes), .big);
                }
            },
        }
    }

    /// Extracts a rectangular section of the image and returns it as a new ImageOperations instance
    /// Preserves WCS information and updates it for the new section
    /// Returns error if section coordinates are invalid
    pub fn getSection(self: *const ImageOperations, section: ImageSection) !ImageOperations {
        try section.validate(self.width, self.height);

        const new_width = section.x_end - section.x_start;
        const new_height = section.y_end - section.y_start;

        var result = try ImageOperations.init(
            self.allocator,
            new_width,
            new_height,
            self.data_type,
        );
        errdefer result.deinit();

        // Copy section data
        var y: usize = 0;
        while (y < new_height) : (y += 1) {
            const src_y = section.y_start + y;
            var x: usize = 0;
            while (x < new_width) : (x += 1) {
                const src_x = section.x_start + x;
                const src_idx = src_y * self.width + src_x;
                const dst_idx = y * new_width + x;

                // Inside getSection() in the data copying loop:
                switch (self.data_type) {
                    .TBYTE => {
                        result.data.i8[dst_idx] = self.data.i8[src_idx];
                    },
                    .TSHORT => {
                        result.data.i16[dst_idx] = self.data.i16[src_idx];
                    },
                    .TINT => {
                        result.data.i32[dst_idx] = self.data.i32[src_idx];
                    },
                    .TLONG => {
                        result.data.i64[dst_idx] = self.data.i64[src_idx];
                    },
                    .UTBYTE => {
                        result.data.u8[dst_idx] = self.data.u8[src_idx];
                    },
                    .UTSHORT => {
                        result.data.u16[dst_idx] = self.data.u16[src_idx];
                    },
                    .TFLOAT => {
                        result.data.f32[dst_idx] = self.data.f32[src_idx];
                    },
                    .TDOUBLE => {
                        result.data.f64[dst_idx] = self.data.f64[src_idx];
                    },
                    .UTINT => {
                        result.data.u32[dst_idx] = self.data.u32[src_idx];
                    },
                    .UTLONG => {
                        result.data.u64[dst_idx] = self.data.u64[src_idx];
                    },
                }
            }
        }

        // Update physical coordinates for the section
        result.x_axis = .{
            .crval = self.x_axis.pixelToWorld(@as(f64, @floatFromInt(section.x_start))),
            .cdelt = self.x_axis.cdelt,
            .crpix = 1,
        };
        result.y_axis = .{
            .crval = self.y_axis.pixelToWorld(@as(f64, @floatFromInt(section.y_start))),
            .cdelt = self.y_axis.cdelt,
            .crpix = 1,
        };

        return result;
    }

    /// Sets WCS parameters for a specific axis
    /// axis must be 1 (X) or 2 (Y) for FITS image data
    /// Returns ImageError.InvalidAxis for other axis values
    pub fn setPhysicalAxis(self: *ImageOperations, axis: u8, crval: f64, cdelt: f64, crpix: f64) !void {
        const coords = PhysicalCoords{ .crval = crval, .cdelt = cdelt, .crpix = crpix };
        switch (axis) {
            1 => self.x_axis = coords,
            2 => self.y_axis = coords,
            else => return ImageError.InvalidAxis,
        }
    }
};

/// Add error logging capability
pub fn logError(err: ImageError, context: ErrorContext) void {
    std.log.err("{s} failed: {s}", .{
        context.operation,
        @errorName(err),
    });
    if (context.details) |details| {
        std.log.err("Details: {s}", .{details});
    }
    if (context.source_error) |source| {
        std.log.err("Source error: {s}", .{@errorName(source)});
    }
}

/// Holds basic statistical measures for image data
pub const ImageStats = struct {
    min: f64,
    max: f64,
    mean: f64,
    median: f64,
    stddev: f64,
};

fn calculateTypeStats(comptime T: type, data: []const T, allocator: std.mem.Allocator) !ImageStats {
    if (data.len == 0) return ImageError.EmptyData;

    var stats: ImageStats = undefined;
    const size = data.len;

    // Initial values from first element
    const first_val = switch (@typeInfo(T)) {
        .Float => @as(f64, @floatCast(data[0])),
        .Int => @as(f64, @floatFromInt(data[0])),
        else => @compileError("Unsupported type"),
    };

    stats.min = first_val;
    stats.max = first_val;
    var sum: f64 = first_val;

    // Calculate min, max, and sum
    for (data[1..]) |val| {
        const float_val = switch (@typeInfo(T)) {
            .Float => @as(f64, @floatCast(val)),
            .Int => @as(f64, @floatFromInt(val)),
            else => unreachable,
        };
        stats.min = @min(stats.min, float_val);
        stats.max = @max(stats.max, float_val);
        sum += float_val;
    }

    // Calculate mean
    stats.mean = sum / @as(f64, @floatFromInt(size));

    // Calculate median
    const sorted = try allocator.alloc(T, size);
    defer allocator.free(sorted);
    @memcpy(sorted, data);
    std.sort.insertion(T, sorted, {}, std.sort.asc(T));

    // For even-length arrays, average the middle two values
    stats.median = if (size % 2 == 0)
        (switch (@typeInfo(T)) {
            .Float => @as(f64, @floatCast(sorted[size / 2 - 1])),
            .Int => @as(f64, @floatFromInt(sorted[size / 2 - 1])),
            else => unreachable,
        } +
            switch (@typeInfo(T)) {
            .Float => @as(f64, @floatCast(sorted[size / 2])),
            .Int => @as(f64, @floatFromInt(sorted[size / 2])),
            else => unreachable,
        }) / 2.0
    else switch (@typeInfo(T)) {
        .Float => @as(f64, @floatCast(sorted[size / 2])),
        .Int => @as(f64, @floatFromInt(sorted[size / 2])),
        else => unreachable,
    };

    // Calculate standard deviation
    var sum_sq: f64 = 0;
    for (data) |val| {
        const float_val = switch (@typeInfo(T)) {
            .Float => @as(f64, @floatCast(val)),
            .Int => @as(f64, @floatFromInt(val)),
            else => unreachable,
        };
        const diff = float_val - stats.mean;
        sum_sq += diff * diff;
    }
    stats.stddev = @sqrt(sum_sq / @as(f64, @floatFromInt(size)));

    return stats;
}

pub fn calculateStatistics(self: *const ImageOperations) !ImageStats {
    return switch (self.data_type) {
        // These types are not valid for image data
        .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
        .TBYTE => calculateTypeStats(i8, self.data.i8, self.allocator),
        .TSHORT => calculateTypeStats(i16, self.data.i16, self.allocator),
        .TINT => calculateTypeStats(i32, self.data.i32, self.allocator),
        .TLONG => calculateTypeStats(i64, self.data.i64, self.allocator),
        .UTBYTE => calculateTypeStats(u8, self.data.u8, self.allocator),
        .UTSHORT => calculateTypeStats(u16, self.data.u16, self.allocator),
        .UTINT => calculateTypeStats(u32, self.data.u32, self.allocator),
        .UTLONG => calculateTypeStats(u64, self.data.u64, self.allocator),
        .TFLOAT => calculateTypeStats(f32, self.data.f32, self.allocator),
        .TDOUBLE => calculateTypeStats(f64, self.data.f64, self.allocator),
    };
}

pub const ImageValidationError = error{
    InvalidDimensions,
    ZeroDimension,
    DimensionTooLarge,
    NullData,
    NaNValue,
    InfinityValue,
    ValueOutOfRange,
};

pub fn validateImageData(self: *const ImageOperations) !void {
    if (self.width == 0 or self.height == 0) return ImageValidationError.ZeroDimension;
    // Use a reasonable max dimension (e.g., 65535 x 65535)
    const max_dimension: usize = 65535;
    if (self.width > max_dimension or self.height > max_dimension) {
        return ImageValidationError.DimensionTooLarge;
    }

    // Validate data based on type
    switch (self.data_type) {
        .TBIT, .TLOGICAL, .TSTRING => return ImageError.UnsupportedImageType,
        .TFLOAT => {
            // Check for NaN and Infinity
            for (self.data.f32) |value| {
                if (std.math.isNan(value)) {
                    return ImageValidationError.NaNValue;
                }
                if (std.math.isInf(value)) {
                    return ImageValidationError.InfinityValue;
                }
            }
        },
        .TDOUBLE => {
            // Check for NaN and Infinity
            for (self.data.f64) |value| {
                if (std.math.isNan(value)) {
                    return ImageValidationError.NaNValue;
                }
                if (std.math.isInf(value)) {
                    return ImageValidationError.InfinityValue;
                }
            }
        },
        // For integer types, we might want to check value ranges
        // depending on the application requirements
        .TBYTE, .TSHORT, .TINT, .TLONG, .UTBYTE, .UTSHORT, .UTINT, .UTLONG => {},
    }
}

test "image operations with FITS integration" {
    const allocator = std.testing.allocator;

    // Open existing FITS file
    var fits_file = try FitsFile.open(allocator, "examples/data/M51_lum.fit", c.READONLY);
    defer fits_file.close() catch unreachable;

    // Load image
    var img = try ImageOperations.fromFitsFile(allocator, fits_file);
    defer img.deinit();

    // Create new FITS file in current directory
    var new_fits = try FitsFile.createFits(allocator, "test_output.fits");
    defer new_fits.close() catch unreachable;

    // Initialize required FITS headers
    var header = FITSHeader.init(new_fits);
    try header.writeKeyword("SIMPLE", true, "Standard FITS format");
    try header.writeKeyword("BITPIX", -32, "32-bit floating point");
    try header.writeKeyword("NAXIS", 2, "Number of dimensions");
    try header.writeKeyword("NAXIS1", @as(i32, @intCast(img.width)), "Image width");
    try header.writeKeyword("NAXIS2", @as(i32, @intCast(img.height)), "Image height");
    try header.writeKeyword("EXTEND", true, "Extensions are permitted");

    // Save image data and WCS information
    try img.saveToFits(new_fits);

    // Verify dimensions
    const dims = try new_fits.getImageDimensions();
    try std.testing.expectEqual(dims[0], img.width);
    try std.testing.expectEqual(dims[1], img.height);

    // Clean up test file
    std.fs.cwd().deleteFile("test_output.fits") catch {};
}

test "ImageOperations statistics calculations" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;

    // Test with different data types
    {
        // Create a small f32 image
        var img = try ImageOperations.init(allocator, 3, 2, .TFLOAT);
        defer img.deinit();

        const test_data = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
        @memcpy(img.data.f32, &test_data);

        const stats = try calculateStatistics(&img);
        std.debug.print("Calculated stddev: {d}\n", .{stats.stddev});

        try expectEqual(stats.min, 1.0);
        try expectEqual(stats.max, 6.0);
        try expectEqual(stats.mean, 3.5);
        try expectEqual(stats.median, 3.5); // Changed from 3.5 to 4.0
        try expect(@abs(stats.stddev - 1.707825127659933) < 0.00001);
    }

    {
        // Test with integer type
        var img = try ImageOperations.init(allocator, 2, 2, .TSHORT);
        defer img.deinit();

        const test_data = [_]i16{ 1, 2, 3, 4 }; // Changed to i16
        @memcpy(img.data.i16, &test_data); // Use i16 data

        const stats = try calculateStatistics(&img);
        try expectEqual(stats.min, 1.0);
        try expectEqual(stats.max, 4.0);
        try expectEqual(stats.mean, 2.5);
        try expectEqual(stats.median, 2.5);
        try expect(@abs(stats.stddev - 1.1180339887499) < 0.00001);
    }

    {
        // Test with unsigned type
        var img = try ImageOperations.init(allocator, 3, 1, .UTBYTE);
        defer img.deinit();

        const test_data = [_]u8{ 0, 128, 255 };
        @memcpy(img.data.u8, &test_data);

        const stats = try calculateStatistics(&img);
        try expectEqual(stats.min, 0.0);
        try expectEqual(stats.max, 255.0);
        const tolerance = 0.000001;
        try std.testing.expectApproxEqAbs(stats.mean, 127.666666666667, tolerance);
        try expectEqual(stats.median, 128.0);
        try expect(@abs(stats.stddev - 104.10358089689) < 0.1);
    }

    {
        // Test empty image error
        var img = try ImageOperations.init(allocator, 0, 0, .TFLOAT);
        defer img.deinit();

        try std.testing.expectError(ImageError.EmptyData, calculateStatistics(&img));
    }

    {
        // Test with large integers
        var img = try ImageOperations.init(allocator, 2, 2, .TLONG);
        defer img.deinit();

        const test_data = [_]i64{ 1000000, 2000000, 3000000, 4000000 };
        @memcpy(img.data.i64, &test_data);

        const stats = try calculateStatistics(&img);
        try expectEqual(stats.min, 1000000.0);
        try expectEqual(stats.max, 4000000.0);
        try expectEqual(stats.mean, 2500000.0);
        try expectEqual(stats.median, 2500000.0);
        try expect(@abs(stats.stddev - 1118033.9887499) < 1.0);
    }
}

test "Image data validation" {
    const allocator = std.testing.allocator;

    // Test valid image
    {
        var img = try ImageOperations.init(allocator, 2, 2, .TFLOAT);
        defer img.deinit();
        const test_data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
        @memcpy(img.data.f32, &test_data);
        try validateImageData(&img);
    }

    // Test zero dimension
    {
        var img = try ImageOperations.init(allocator, 0, 2, .TFLOAT);
        defer img.deinit();
        try std.testing.expectError(ImageValidationError.ZeroDimension, validateImageData(&img));
    }

    // Test NaN value
    {
        var img = try ImageOperations.init(allocator, 2, 2, .TFLOAT);
        defer img.deinit();
        const test_data = [_]f32{ 1.0, std.math.nan(f32), 3.0, 4.0 };
        @memcpy(img.data.f32, &test_data);
        try std.testing.expectError(ImageValidationError.NaNValue, validateImageData(&img));
    }

    // Test infinity value
    {
        var img = try ImageOperations.init(allocator, 2, 2, .TFLOAT);
        defer img.deinit();
        const test_data = [_]f32{ 1.0, 2.0, std.math.inf(f32), 4.0 };
        @memcpy(img.data.f32, &test_data);
        try std.testing.expectError(ImageValidationError.InfinityValue, validateImageData(&img));
    }
}
