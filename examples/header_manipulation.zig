const std = @import("std");
const fits = @import("zfitsio");

pub fn main() !void {
    // Print start message for the test
    std.debug.print("\nRunning FITSHeader test...\n", .{});

    // Initialize the page allocator for memory management
    // Using page allocator for simplicity in example; in production code,
    // consider using a more appropriate allocator for your use case
    const allocator = std.heap.page_allocator;

    // Open a FITS file in READ_WRITE mode
    // The file path is relative to the project root
    var fits_file = try fits.openFits(allocator, "examples/data/M51_lum.fit", fits.Mode.READ_WRITE);
    // Ensure file is closed when function exits, ignoring potential close errors
    defer fits_file.close() catch {};

    // Initialize a header object for header manipulation operations
    var header = fits.FITSHeader.init(fits_file);

    try header.insertCardImage(.{
        .keyword = "OBSERVER",
        .value = "'John Doe'",
        .comment = "Observer name",
    });

    // Update a card image
    try header.updateCardImage("OBSERVER", .{
        .keyword = "OBSERVER",
        .value = "'Jane Smith'",
        .comment = "Updated observer",
    });

    // Write different data types
    try header.writeString("OBJECT", "M31", "Target object");
    try header.writeLogical("FILTER", true, "Filter in beam");

    try header.deleteCardImage("FILTER");
}
