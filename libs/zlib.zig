const std = @import("std");

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "zlib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Resolve the dependency for `zlib`
    const zlib_dep = b.lazyDependency("zlib", .{
        .target = target,
        .optimize = optimize,
    }) orelse return null;

    // List of `zlib` source files
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

    // Add each source file to the build step
    inline for (srcs) |src| {
        lib.addCSourceFile(.{
            .file = zlib_dep.path(src),
            .flags = &.{"-std=c89"},
        });
    }

    // Install `zlib` headers for library use
    lib.installHeader(zlib_dep.path("zlib.h"), "zlib.h");
    lib.installHeader(zlib_dep.path("zconf.h"), "zconf.h");

    return lib;
}
