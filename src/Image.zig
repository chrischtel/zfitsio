const std = @import("std");
const FitsType = @import("datatypes.zig").FitsType;
const FitsFile = @import("fitsfile.zig").FitsFile;
const FITSHeader = @import("FITSHeader.zig").FITSHeader;

const c = @import("util/util.zig").c;

pub const ImageSection = struct {
    x_start: usize,
    x_end: usize,
    y_start: usize,
    y_end: usize,

    pub fn validate(self: ImageSection, width: usize, height: usize) !void {
        if (self.x_end > width or self.y_end > height) {
            return error.SectionOutOfBounds;
        }
        if (self.x_start >= self.x_end or self.y_start >= self.y_end) {
            return error.InvalidSectionBounds;
        }
    }
};

pub const PhysicalCoords = struct {
    crval: f64,
    cdelt: f64,
    crpix: f64,

    pub fn pixelToWorld(self: PhysicalCoords, pixel: f64) f64 {
        return self.crval + (pixel - self.crpix) * self.cdelt;
    }

    pub fn worldToPixel(self: PhysicalCoords, world: f64) f64 {
        return (world - self.crval) / self.cdelt + self.crpix;
    }
};

pub const ImageOperations = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    data_type: FitsType,
    data: union {
        f32: []f32,
        f64: []f64,
    },
    x_axis: PhysicalCoords,
    y_axis: PhysicalCoords,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, data_type: FitsType) !ImageOperations {
        if (data_type != .TFLOAT and data_type != .TDOUBLE) {
            return error.UnsupportedDataType;
        }

        var self = ImageOperations{
            .allocator = allocator,
            .width = width,
            .height = height,
            .data_type = data_type,
            .data = undefined,
            .x_axis = PhysicalCoords{ .crval = 0, .cdelt = 1, .crpix = 1 },
            .y_axis = PhysicalCoords{ .crval = 0, .cdelt = 1, .crpix = 1 },
        };

        switch (data_type) {
            .TFLOAT => {
                self.data.f32 = try allocator.alloc(f32, width * height);
                @memset(self.data.f32, 0);
            },
            .TDOUBLE => {
                self.data.f64 = try allocator.alloc(f64, width * height);
                @memset(self.data.f64, 0);
            },
            else => unreachable,
        }

        return self;
    }

    pub fn fromFitsFile(allocator: std.mem.Allocator, fits: *FitsFile) !ImageOperations {
        // Get image dimensions
        const dims = try fits.getImageDimensions();

        // Determine data type and create image
        var status: c_int = 0;
        var bitpix: c_int = undefined;
        _ = c.fits_get_img_type(fits.fptr, &bitpix, &status);
        if (status != 0) return error.InvalidImageType;

        const data_type: FitsType = switch (bitpix) {
            -32 => .TFLOAT,
            -64 => .TDOUBLE,
            else => return error.UnsupportedBitpix,
        };

        var img = try ImageOperations.init(allocator, dims[0], dims[1], data_type);
        errdefer img.deinit();

        // Read image data
        var anynull: c_int = 0;
        switch (data_type) {
            .TFLOAT => {
                var nullval: f32 = 0;
                const result = c.fits_read_img(fits.fptr, c.TFLOAT, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.f32[0], &anynull, &status);
                if (result != 0) return error.ReadImageFailed;
            },
            .TDOUBLE => {
                var nullval: f64 = 0;
                const result = c.fits_read_img(fits.fptr, c.TDOUBLE, 1, @intCast(dims[0] * dims[1]), &nullval, &img.data.f64[0], &anynull, &status);
                if (result != 0) return error.ReadImageFailed;
            },
            else => unreachable,
        }

        // Try to read WCS information
        try img.readWCSFromHeader(fits);

        return img;
    }

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

    pub fn saveToFits(self: *const ImageOperations, fits: *FitsFile) !void {
        var status: c_int = 0;

        // Write image data
        const size = self.width * self.height;
        switch (self.data_type) {
            .TFLOAT => {
                const result = c.fits_write_img(fits.fptr, c.TFLOAT, 1, @intCast(size), &self.data.f32[0], &status);
                if (result != 0) return error.WriteImageFailed;
            },
            .TDOUBLE => {
                const result = c.fits_write_img(fits.fptr, c.TDOUBLE, 1, @intCast(size), &self.data.f64[0], &status);
                if (result != 0) return error.WriteImageFailed;
            },
            else => unreachable,
        }

        // Write WCS information using FITSHeader
        var header = FITSHeader.init(fits);

        try header.writeKeyword("CRVAL1", self.x_axis.crval, "Reference value for X axis");
        try header.writeKeyword("CDELT1", self.x_axis.cdelt, "Scale for X axis");
        try header.writeKeyword("CRPIX1", self.x_axis.crpix, "Reference pixel for X axis");

        try header.writeKeyword("CRVAL2", self.y_axis.crval, "Reference value for Y axis");
        try header.writeKeyword("CDELT2", self.y_axis.cdelt, "Scale for Y axis");
        try header.writeKeyword("CRPIX2", self.y_axis.crpix, "Reference pixel for Y axis");

        try fits.flush();
    }

    pub fn deinit(self: *ImageOperations) void {
        switch (self.data_type) {
            .TFLOAT => self.allocator.free(self.data.f32),
            .TDOUBLE => self.allocator.free(self.data.f64),
            else => unreachable,
        }
    }

    pub fn writeImage(self: *const ImageOperations, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();

        // Write data based on type
        switch (self.data_type) {
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
            else => unreachable,
        }
    }

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

                switch (self.data_type) {
                    .TFLOAT => {
                        result.data.f32[dst_idx] = self.data.f32[src_idx];
                    },
                    .TDOUBLE => {
                        result.data.f64[dst_idx] = self.data.f64[src_idx];
                    },
                    else => unreachable,
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

    pub fn setPhysicalAxis(self: *ImageOperations, axis: u8, crval: f64, cdelt: f64, crpix: f64) !void {
        const coords = PhysicalCoords{ .crval = crval, .cdelt = cdelt, .crpix = crpix };
        switch (axis) {
            1 => self.x_axis = coords,
            2 => self.y_axis = coords,
            else => return error.InvalidAxis,
        }
    }
};

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
