const std = @import("std");

const srcs = &.{
    "buffers.c",
    "cfileio.c",
    "checksum.c",
    "drvrfile.c",
    "drvrmem.c",
    "drvrnet.c",
    "drvrsmem.c",
    "editcol.c",
    "edithdu.c",
    "fitscore.c",
    "fits_hcompress.c",
    "fits_hdecompress.c",
    "getcol.c",
    "getcolb.c",
    "getcold.c",
    "getcole.c",
    "getcoli.c",
    "getcolj.c",
    "getcolk.c",
    "getcoll.c",
    "getcolsb.c",
    "getcols.c",
    "getcolui.c",
    "getcoluj.c",
    "getcoluk.c",
    "getkey.c",
    "group.c",
    "grparser.c",
    "histo.c",
    "imcompress.c",
    "iraffits.c",
    "modkey.c",
    "pliocomp.c",
    "putcol.c",
    "putcolb.c",
    "putcold.c",
    "putcole.c",
    "putcoli.c",
    "putcolj.c",
    "putcolk.c",
    "putcoll.c",
    "putcolsb.c",
    "putcols.c",
    "putcolu.c",
    "putcolui.c",
    "putcoluj.c",
    "putcoluk.c",
    "putkey.c",
    "quantize.c",
    "region.c",
    "ricecomp.c",
    "scalnull.c",
    "simplerng.c",
    "swapproc.c",
    "wcssub.c",
    "wcsutil.c",
    "zcompress.c",
    "zuncompress.c",
    "eval_f.c",
    "eval_y.c",
    "eval_l.c",
};

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "cfitsio",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const cfitsio_dep = b.lazyDependency("cfitsio", .{
        .target = target,
        .optimize = optimize,
    }) orelse return null;

    inline for (srcs) |s| {
        lib.addCSourceFile(.{
            .file = cfitsio_dep.path(s),
            .flags = &.{ "-std=c11", "-D_POSIX_C_SOURCE=200809L" },
        });
    }

    // Install headers for `cfitsio`
    lib.installHeader(cfitsio_dep.path("fitsio.h"), "fitsio.h");
    lib.installHeader(cfitsio_dep.path("longnam.h"), "longnam.h");

    return lib;
}
