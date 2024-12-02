const std = @import("std");
const c = @import("util/util.zig").c;

pub const FitsFile = @import("fitsfile.zig").FitsFile;
pub const FITSHeader = @import("FITSHeader.zig").FITSHeader;

// Re-export commonly used constants from cfitsio
pub const Mode = struct {
    pub const READ_ONLY: c_int = c.READONLY;
    pub const READ_WRITE: c_int = c.READWRITE;
};

pub const DataType = struct {
    pub const BYTE: c_int = c.TBYTE;
    pub const SHORT: c_int = c.TSHORT;
    pub const INT: c_int = c.TINT;
    pub const LONG: c_int = c.TLONG;
    pub const FLOAT: c_int = c.TFLOAT;
    pub const DOUBLE: c_int = c.TDOUBLE;
};

// Custom errors
pub const FitsError = error{
    OpenFileFailed,
    CloseFileFailed,
    ReadImageFailed,
    InvalidFile,
    InvalidImageData,
};

// High-level helper functions
pub fn openFits(allocator: std.mem.Allocator, path: []const u8, mode: c_int) !*FitsFile {
    return FitsFile.open(allocator, path.ptr, mode);
}

pub fn getKeyword(file: *FitsFile, keyword: []const u8) ![]const u8 {
    var header = FITSHeader.init(file);

    return try header.getKeyword(keyword);
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
