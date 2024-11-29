//! This example demonstrates how to manipulate FITS file headers using the zfitsio library.
//! It shows operations for writing and reading header keywords of different data types,
//! as well as proper memory management and error handling.

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
    var fits_file = try fits.openFits(allocator, "examples/data/M51_green.fit", fits.Mode.READ_WRITE);
    // Ensure file is closed when function exits, ignoring potential close errors
    defer fits_file.close() catch unreachable;

    // Initialize a header object for header manipulation operations
    var header = fits.FITSHeader.init(fits_file);

    // Demonstrate writing different data types to the FITS header
    std.debug.print("\nWriting keywords...\n", .{});

    // Write a string value with associated comment
    try header.writeKeyword("TESTSTR", "test value", "string comment");
    std.debug.print("Wrote TESTSTR\n", .{});

    // Write a boolean value with associated comment
    try header.writeKeyword("TESTBOOL", true, "boolean comment");
    std.debug.print("Wrote TESTBOOL\n", .{});

    // Write an integer value with associated comment
    try header.writeKeyword("TESTINT", 42, "integer comment");
    std.debug.print("Wrote TESTINT\n", .{});

    // Write a floating-point value with associated comment
    try header.writeKeyword("TESTFLT", 3.14159, "float comment");
    std.debug.print("Wrote TESTFLT\n", .{});

    // Flush changes to disk to ensure they are written
    // This is important when making multiple modifications
    try fits_file.flush();
    std.debug.print("\nFlushed changes to file\n", .{});

    // Print all headers to verify our changes
    // This helps in debugging and confirming the state of the FITS header
    try header.printAllHeaders();

    // Demonstrate reading back the values we just wrote
    std.debug.print("\nReading keywords...\n", .{});

    // Read and verify string value
    // Note: getKeyword returns an allocated string that must be freed
    const str_val = header.getKeyword("TESTSTR") catch |err| {
        std.debug.print("Error reading TESTSTR: {}\n", .{err});
        return err;
    };
    // Free the allocated string when we're done with it
    defer allocator.free(str_val);
    std.debug.print("TESTSTR value: {s}\n", .{str_val});

    // Read and verify boolean value
    const bool_val = header.getKeyword("TESTBOOL") catch |err| {
        std.debug.print("Error reading TESTBOOL: {}\n", .{err});
        return err;
    };
    defer allocator.free(bool_val);
    std.debug.print("TESTBOOL value: {s}\n", .{bool_val});

    // Read and verify integer value
    const int_val = header.getKeyword("TESTINT") catch |err| {
        std.debug.print("Error reading TESTINT: {}\n", .{err});
        return err;
    };
    defer allocator.free(int_val);
    std.debug.print("TESTINT value: {s}\n", .{int_val});

    // Read and verify float value
    const float_val = header.getKeyword("TESTFLT") catch |err| {
        std.debug.print("Error reading TESTFLT: {}\n", .{err});
        return err;
    };
    defer allocator.free(float_val);
    std.debug.print("TESTFLT value: {s}\n", .{float_val});
}
