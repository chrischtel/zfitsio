const std = @import("std");

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "cfitsio",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib.addIncludePath(b.path("libs/zlib/"));

    const cfitsio_dep = b.lazyDependency("cfitsio", .{
        .target = target,
        .optimize = optimize,
    }) orelse return null;

    inline for (srcs) |s| {
        lib.addCSourceFile(.{
            .file = cfitsio_dep.path(s),
            .flags = &.{"-std=c99"},
        });
    }
    lib.installHeader(cfitsio_dep.path("fitsio.h"), "fitsio.h");
    return lib;
}

const srcs = &.{
    "fitscore.c",
    "getcol.c",
    "getkey.c",
    "putcol.c",
    "putkey.c",
    "checksum.c",
    "ricecomp.c",
    "zcompress.c",
    "zuncompress.c",
    "drvrfile.c",
    "drvrmem.c",
    "drvrsmem.c",
    "scalnull.c",
    "swapproc.c",
    "region.c",
    "histo.c",
    "group.c",
};
