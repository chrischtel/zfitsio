const std = @import("std");
const Build = std.Build;
const Step = Build.Step;
const This = @This();

const LibraryConfig = struct {
    cache: ?*Step.Compile = null,
    creator: *const fn (b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*Step.Compile,
    name: []const u8,
};

var lib_cache = struct {
    cfitsio: ?*Step.Compile = null,
    zlib: ?*Step.Compile = null,
}{};

fn getLibrary(comptime creator: *const fn (b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*Step.Compile, cache: *?*Step.Compile, b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*Step.Compile {
    if (cache.*) |lib| return lib;
    const result = creator(b, target, optimize);
    if (result) |lib| {
        cache.* = lib;
    }
    return result;
}

fn getModule(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *Build.Module {
    return b.modules.get("zfitsio") orelse b.addModule("zfitsio", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

const Example = struct {
    name: []const u8,
    path: []const u8,
};

const examples = [_]Example{
    .{ .name = "read_fits", .path = "examples/read_fits.zig" },
    .{ .name = "write_fits", .path = "examples/write_fits.zig" },
    .{ .name = "modify_header", .path = "examples/modify_header.zig" },
    .{ .name = "basic_fits", .path = "examples/basic_fits.zig" },
    .{ .name = "a", .path = "examples/a.zig" },
    .{ .name = "header_manipulation", .path = "examples/header_manipulation.zig" },
};

fn setupTest(b: *Build, name: []const u8, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *Step.Compile {
    const test_step = b.addTest(.{
        .root_source_file = b.path(b.fmt("src/{s}.zig", .{name})),
        .target = target,
        .optimize = optimize,
    });
    test_step.linkLibC();
    return test_step;
}

fn linkLibraries(artifact: *Step.Compile, libs: struct { cfitsio: ?*Step.Compile, zlib: ?*Step.Compile }) void {
    if (libs.cfitsio) |cfits| {
        artifact.linkLibrary(cfits);
        if (libs.zlib) |zl| artifact.linkLibrary(zl);
    } else {
        artifact.linkSystemLibrary("cfitsio");
        artifact.linkSystemLibrary("z");
    }
}

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_system_libs = b.option(bool, "use-system-libs", "Use system-installed libraries instead of building from source") orelse false;

    const zlib = if (!use_system_libs)
        getLibrary(createZlib, &lib_cache.zlib, b, target, optimize)
    else
        null;

    const cfitsio = if (!use_system_libs) blk: {
        const lib = getLibrary(createCfitsio, &lib_cache.cfitsio, b, target, optimize);
        if (lib != null and zlib != null) lib.?.linkLibrary(zlib.?);
        break :blk lib;
    } else null;

    const libs = .{
        .zlib = zlib,
        .cfitsio = cfitsio,
    };

    // Setup main library
    const zfitsio_lib = b.addStaticLibrary(.{
        .name = "zfitsio",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkLibraries(zfitsio_lib, libs);

    const docs = b.addInstallDirectory(.{
        .source_dir = zfitsio_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    b.installArtifact(zfitsio_lib);

    // Setup module
    const zfitsio = getModule(b, target, optimize);
    const wrapper = b.addModule("wrapper", .{
        .root_source_file = b.path("src/wrapper.zig"),
    });

    // Setup tests
    const test_names = [_][]const u8{ "fitsfile", "FITSHeader", "root", "Image" };
    var test_steps = std.ArrayList(*Step.Run).init(b.allocator);
    defer test_steps.deinit();

    for (test_names) |name| {
        const test_exe = setupTest(b, name, target, optimize);
        test_exe.root_module.addImport("wrapper", wrapper);
        test_exe.root_module.addImport("zfitsio", zfitsio);
        linkLibraries(test_exe, libs);

        const run_test = b.addRunArtifact(test_exe);
        try test_steps.append(run_test);
    }

    const test_step = b.step("test", "Run unit tests");
    for (test_steps.items) |run_test| {
        test_step.dependOn(&run_test.step);
    }

    // Setup examples
    const examples_step = b.step("examples", "Build examples");
    for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_source_file = b.path(ex.path),
            .target = target,
            .optimize = optimize,
        });

        exe.linkLibC();
        linkLibraries(exe, libs);
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
