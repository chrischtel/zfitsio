const std = @import("std");
const fits = @import("zfitsio");

pub fn main() !void {
    _ = fits.FitsFile;
    _ = fits.FITSHeader;
    _ = fits.DataTypes;
    _ = fits.ImageOperations;
}
