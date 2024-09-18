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

    // const libthermit = b.addStaticLibrary(.{
    //     .name = "thermit",
    //     .root_source_file = b.path("src/external.zig"),
    //     .optimize = optimize,
    //     .target = target,
    // });
    // b.installArtifact(libthermit);
    //
    // const header = b.addInstallFile(libthermit.getEmittedH(), "include/thermit.h");
    // header.step.dependOn(&libthermit.step);
    // b.getInstallStep().dependOn(&header.step);

    // ------------------------------ Tests -----------------------------------
    const t = b.addTest(.{
        .root_source_file = b.path("src/thermit.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.step("test", "Run unit tests");
    tests.dependOn(&b.addRunArtifact(t).step);
}
