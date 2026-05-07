const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const thermit = b.addModule("thermit", .{
        .root_source_file = b.path("src/thermit.zig"),
    });

    _ = b.addModule("spinner", .{
        .root_source_file = b.path("src/spinner.zig"),
        .imports = &.{.{ .name = "thermit", .module = thermit }},
    });

    const scured = b.addModule("scured", .{
        .root_source_file = b.path("src/scured.zig"),
        .imports = &.{.{ .name = "thermit", .module = thermit }},
    });

    // ----------------------------- Library -----------------------------------

    const ext_mod = b.createModule(.{
        .root_source_file = b.path("src/external.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "thermit", .module = thermit }},
    });
    ext_mod.addIncludePath(b.path("src"));

    const thermitLib = b.addLibrary(.{
        .name = "thermit",
        .root_module = ext_mod,
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });

    const libthermit = b.addInstallArtifact(thermitLib, .{});

    const header = b.addInstallHeaderFile(b.path("src/external.h"), "thermit.h");

    const libs = b.step("lib", "Build the library");
    libs.dependOn(&libthermit.step);
    libs.dependOn(&header.step);

    const check = b.step("check", "zls check step");

    // ----------------------------- Examples ----------------------------------

    const EXAMPLES = .{
        .{
            .name = "screensize",
            .desc = "Example that prints the current screen size",
            .need = .thermit,
            .check = false,
        },
        .{
            .name = "tuianimation",
            .desc = "Example that shows a basic animation",
            .need = .scinee,
            .check = false,
        },
        .{
            .name = "readme",
            .desc = "Example that shows a basic animation",
            .need = .scinee,
            .check = true,
        },
    };

    inline for (EXAMPLES) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/bin/" ++ example.name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        switch (example.need) {
            .thermit => exe_mod.addImport("thermit", thermit),
            .scinee => exe_mod.addImport("scured", scured),
            else => {},
        }
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = exe_mod,
        });
        const exampleStep = b.step("example-" ++ example.name, example.desc);
        const exampleRun = b.addRunArtifact(exe);
        exampleStep.dependOn(&exampleRun.step);

        if (example.check) check.dependOn(&exe.step);
    }

    // ------------------------------ Tests ------------------------------------

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/thermit.zig"),
        .target = target,
        .optimize = optimize,
    });
    const t = b.addTest(.{
        .root_module = test_mod,
    });

    const tests = b.step("test", "Run unit tests");
    tests.dependOn(&b.addRunArtifact(t).step);
}
