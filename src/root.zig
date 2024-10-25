const std = @import("std");
const util = @import("utility.zig");
const c = util.c;

pub fn testfu() !void {
    // Example of using a cfitsio function
    var file: ?*c.fitsfile = null;
    var status: i32 = 0;
    _ = c.ffopen(&file, "myfile.fits", c.READONLY, &status);
    std.debug.print("Opened FITS file with status: {}\n", .{status});
}
