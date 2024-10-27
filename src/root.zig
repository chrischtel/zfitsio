const std = @import("std");
const util = @import("utility.zig");
const c = util.c;
pub const fitsfile = @import("fitsfile.zig");
pub fn testfu(alloc: *std.mem.Allocator) !void {
    // Example of using a cfitsio function
    var fits_file = try fitsfile.FitsFile.open(alloc, "test.fit", c.READONLY);
    defer fits_file.close() catch |err| {
        std.debug.print("Failed to close FITS file: {any}\n", .{err});
    };
}
