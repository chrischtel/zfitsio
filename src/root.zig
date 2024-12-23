//! This module provides functions for retrieving the current date and
//! time with varying degrees of precision and accuracy. It does not
//! depend on libc, but will use functions from it if available.
const std = @import("std");
const c = @import("util/util.zig").c;

/// Main FITS file handling module that provides core functionality for reading and writing FITS files.
/// Includes operations for opening, reading, and manipulating FITS files.
pub const FitsFile = @import("fitsfile.zig").FitsFile;

/// FITS header manipulation module that handles reading, writing, and modifying FITS headers.
/// Provides functionality for working with FITS keywords, values, and comments.
pub const FITSHeader = @import("FITSHeader.zig").FITSHeader;

/// Contains definitions and utilities for handling FITS data types.
/// Includes type conversion, validation, and size calculations for FITS data formats.
pub const DataTypes = @import("datatypes.zig").FitsType;

/// Image processing and manipulation functionality for FITS image data.
/// Provides operations for reading image data, pixel manipulation, and basic image processing.
pub const ImageOperations = @import("Image.zig");

// Re-export commonly used constants from cfitsio

// Re-export commonly used constants from cfitsio
pub const Mode = struct {
    pub const READ_ONLY: c_int = c.READONLY;
    pub const READ_WRITE: c_int = c.READWRITE;
};

pub fn openFits(allocator: std.mem.Allocator, path: []const u8, mode: c_int) !*FitsFile {
    return FitsFile.open(allocator, path.ptr, mode);
}
test "imports" {
    const fitsH = @import("FITSHeader.zig");
    const fitsF = @import("fitsfile.zig");
    const dT = @import("datatypes.zig");
    const image = @import("Image.zig");
    _ = dT.FitsType;
    _ = dT.getSizeForType;
    _ = dT.getZigType;
    _ = dT.readFitsData;
    _ = fitsF.Mode;
    _ = fitsF.FitsFile;
    _ = fitsH.FITSHeader;
    _ = fitsH.CardImage;
    _ = fitsH.Coordinates;
    _ = fitsH.HeaderError;
    _ = image.ImageOperations;
    _ = image.ImageSection;
    _ = image.PhysicalCoords;
}
