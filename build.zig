const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const thermit = b.addModule("thermit", .{
        .root_source_file = b.path("src/thermit.zig"),
    });

    // an reference implementation of thermit
    const spinner = b.addModule("spinner", .{
        .root_source_file = b.path("src/spinner.zig"),
    });
    spinner.addImport("thermit", thermit);

    // an reference implementation of thermit
    const scured = b.addModule("scured", .{
        .root_source_file = b.path("src/scured.zig"),
    });
    scured.addImport("thermit", thermit);

    // ----------------------------- Library -----------------------------------

    const thermitLib = b.addSharedLibrary(.{
        .name = "thermit",
        .root_source_file = b.path("src/external.zig"),
        .optimize = .ReleaseFast,
        .target = target,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    thermitLib.root_module.addImport("thermit", thermit);
    thermitLib.addIncludePath(b.path("src"));
    thermitLib.linkLibC();

    const libthermit = b.addInstallArtifact(thermitLib, .{});

    // // HACK zig complier doesnt emit the header in the right place so just
    // // tell it to make it and instead of using its location use the real one
    // _ = thermitLib.getEmittedH();
    // const header = b.addInstallHeaderFile(b.path(".zig-cache/thermit.h"), "thermit.h");
    const header = b.addInstallHeaderFile(b.path("src/external.h"), "thermit.h");

    const libs = b.step("lib", "Build the library");
    libs.dependOn(&libthermit.step);
    libs.dependOn(&header.step);

    // ----------------------------- Examples ----------------------------------

    const EXAMPLES = .{
        .{
            .name = "screensize",
            .desc = "Example that prints the current screen size",
            .need = .thermit,
        },
        .{
            .name = "tuianimation",
            .desc = "Example that shows a basic animation",
            .need = .scinee,
        },
        .{
            .name = "readme",
            .desc = "Example that shows a basic animation",
            .need = .scinee,
        },
    };

    inline for (EXAMPLES) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path("src/bin/" ++ example.name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        switch (example.need) {
            .thermit => {
                exe.root_module.addImport("thermit", thermit);
            },
            .scinee => {
                exe.root_module.addImport("scured", scured);
            },
            else => {},
        }
        const exampleStep = b.step("example-" ++ example.name, example.desc);
        const exampleRun = b.addRunArtifact(exe);
        exampleStep.dependOn(&exampleRun.step);
    }

    // ------------------------------ Tests -----------------------------------
    const t = b.addTest(.{
        .root_source_file = b.path("src/thermit.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.step("test", "Run unit tests");
    tests.dependOn(&b.addRunArtifact(t).step);
}
