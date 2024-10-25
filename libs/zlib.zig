const std = @import("std");

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "zlib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.addIncludePath(b.path("libs/zlib/"));

    // Add source files for zlib
    const srcs = &.{
        "adler32.c",
        "compress.c",
        "crc32.c",
        "deflate.c",
        "gzclose.c",
        "gzlib.c",
        "gzread.c",
        "gzwrite.c",
        "inflate.c",
        "infback.c",
        "inftrees.c",
        "inffast.c",
        "trees.c",
        "uncompr.c",
        "zutil.c",
    };

    inline for (srcs) |src| {
        lib.addCSourceFile(.{ .file = b.path("libs/zlib/" ++ src), .flags = &.{"-std=c89"} });
    }
    lib.installHeader(b.path("libs/zlib/zlib.h"), "zlib.h");

    return lib;
}
