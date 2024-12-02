const std = @import("std");
const this = @This();

var _cfitsio_lib_cache: ?*std.Build.Step.Compile = null;
fn getCfitsio(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    if (_cfitsio_lib_cache) |lib| return lib;

    _cfitsio_lib_cache = createCfitsio(b, target, optimize);
    return _cfitsio_lib_cache.?;
}

var _zlib_lib_cache: ?*std.Build.Step.Compile = null;
fn getZlib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    if (_zlib_lib_cache) |lib| return lib;

    _zlib_lib_cache = createZlib(b, target, optimize);
    return _zlib_lib_cache.?;
}

fn getModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    if (b.modules.contains("zfitsio")) {
        return b.modules.get("zfitsio").?;
    }
    return b.addModule("zfitsio", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_system_libs = b.option(bool, "use-system-libs", "Use system-installed libraries instead of building from source") orelse false;

    const zlib_lib = if (!use_system_libs)
        getZlib(b, target, optimize)
    else
        null;

    const cfitsio_lib = if (!use_system_libs) blk: {
        const lib = getCfitsio(b, target, optimize);
        if (zlib_lib) |zl| lib.linkLibrary(zl);
        break :blk lib;
    } else null;

    const zfitsio_lib = b.addStaticLibrary(.{
        .name = "zfitsio",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (cfitsio_lib) |cfits| {
        zfitsio_lib.linkLibrary(cfits);
        if (zlib_lib) |zl| zfitsio_lib.linkLibrary(zl);
    } else {
        zfitsio_lib.linkSystemLibrary("cfitsio");
        zfitsio_lib.linkSystemLibrary("z");
    }

    b.installArtifact(zfitsio_lib);

    const zfitsio = this.getModule(b, target, optimize);

    const fitsfile_tests = b.addTest(.{
        .root_source_file = b.path("src/fitsfile.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fits_header_tests = b.addTest(.{
        .root_source_file = b.path("src/FITSHeader.zig"),
        .target = target,
        .optimize = optimize,
    });

    const root_test = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    fits_header_tests.linkLibC(); // Add this

    fitsfile_tests.linkLibC(); // Add this
    root_test.linkLibC(); // Add this

    const wrapper = b.addModule("wrapper", .{
        .root_source_file = b.path("src/wrapper.zig"),
    });
    fitsfile_tests.root_module.addImport("wrapper", wrapper);
    fits_header_tests.root_module.addImport("wrapper", wrapper);
    fits_header_tests.root_module.addImport("zfitsio", zfitsio);
    root_test.root_module.addImport("wrapper", wrapper);
    root_test.root_module.addImport("zfitsio", zfitsio);

    if (cfitsio_lib) |lib| {
        fitsfile_tests.linkLibrary(lib);
        fits_header_tests.linkLibrary(lib); // Add this line
        root_test.linkLibrary(lib);
        if (zlib_lib) |zl| {
            fitsfile_tests.linkLibrary(zl);
            fits_header_tests.linkLibrary(zl); // Add this line
            root_test.linkLibrary(zl);
        }
    } else {
        fitsfile_tests.linkSystemLibrary("cfitsio");
        fits_header_tests.linkSystemLibrary("cfitsio"); // Add this line
        root_test.linkSystemLibrary("cfitsio");
        fitsfile_tests.linkSystemLibrary("z");
        fits_header_tests.linkSystemLibrary("z"); // Add this line
        root_test.linkSystemLibrary("z");
    }

    const run_fitsfile_tests = b.addRunArtifact(fitsfile_tests);
    const run_header_tests = b.addRunArtifact(fits_header_tests);
    const run_root_test = b.addRunArtifact(root_test);
    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_fitsfile_tests.step);
    test_step.dependOn(&run_header_tests.step); // Add this line
    test_step.dependOn(&run_root_test.step);

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{ .name = "read_fits", .path = "examples/read_fits.zig" },
        .{ .name = "write_fits", .path = "examples/write_fits.zig" },
        .{ .name = "modify_header", .path = "examples/modify_header.zig" },
        .{ .name = "basic_fits", .path = "examples/basic_fits.zig" },
        .{ .name = "a", .path = "examples/a.zig" },
        .{ .name = "header_manipulation", .path = "examples/header_manipulation.zig" },
    };

    const examples_step = b.step("examples", "Build examples");

    for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_source_file = b.path(ex.path),
            .target = target,
            .optimize = optimize,
        });

        exe.linkLibC();
        if (cfitsio_lib) |lib| {
            exe.linkLibrary(lib);
            if (zlib_lib) |zl| exe.linkLibrary(zl);
        } else {
            exe.linkSystemLibrary("cfitsio");
            exe.linkSystemLibrary("z");
        }

        exe.root_module.addImport("zfitsio", zfitsio);

        examples_step.dependOn(&exe.step);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(ex.name, b.fmt("Run the {s} example", .{ex.name}));
        run_step.dependOn(&run_cmd.step);
    }
}

pub fn createZlib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "zlib",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const zlib_dep = b.lazyDependency("zlib", .{
        .target = target,
        .optimize = optimize,
    }) orelse return null;

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
        lib.addCSourceFile(.{
            .file = zlib_dep.path(src),
            .flags = &.{"-std=c89"},
        });
    }
    lib.installHeader(zlib_dep.path("zlib.h"), "zlib.h");
    lib.installHeader(zlib_dep.path("zconf.h"), "zconf.h");
    return lib;
}

pub fn createCfitsio(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
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

    inline for (srcs) |s| {
        lib.addCSourceFile(.{
            .file = cfitsio_dep.path(s),
            .flags = &.{ "-std=c11", "-D_POSIX_C_SOURCE=200809L" },
        });
    }
    lib.installHeader(cfitsio_dep.path("fitsio.h"), "fitsio.h");
    lib.installHeader(cfitsio_dep.path("longnam.h"), "longnam.h");
    return lib;
}
