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

    // ----------------------------- Library -----------------------------------

    const libthermit = b.addSharedLibrary(.{
        .name = "thermit",
        .root_source_file = b.path("src/external.zig"),
        .optimize = .ReleaseFast,
        .target = target,
    });
    libthermit.addIncludePath(b.path("src"));

    const header = b.addInstallHeaderFile(b.path("src/thermit.h"), "thermit.h");

    const libs = b.step("lib", "Build the library");
    libs.dependOn(&libthermit.step);
    libs.dependOn(&header.step);

    // ----------------------------- Examples ----------------------------------

    const EXAMPLES = .{
        .{
            .name = "screensize",
            .desc = "Example that prints the current screen size",
        },
    };

    inline for (EXAMPLES) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path("src/bin/" ++ example.name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("thermit", thermit);
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
