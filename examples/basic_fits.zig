const std = @import("std");
const fits = @import("zfitsio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fits_file = try fits.openFits(allocator, "examples/data/test.fit", fits.Mode.READ_ONLY);
    defer fits_file.close() catch |err| {
        std.debug.print("Error closing file: {}\n", .{err});
    };

    const count = try fits_file.getHDUCount();

    std.debug.print("HDU count: {d}\n", .{count});

    const dimensions = try fits_file.getImageDimensions();
    std.debug.print("Image dimensions: {d}x{d}\n", .{ dimensions[0], dimensions[1] });
}
