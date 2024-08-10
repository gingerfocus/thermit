const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("thermit", .{ .root_source_file = b.path("src/root.zig") });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(unit_tests);

    const tests = b.step("test", "Run unit tests");
    tests.dependOn(&run_tests.step);

    // const translate_c = b.addTranslateC(.{
    //     .root_source_file = b.path("include/termbox2.h"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const termbox2 = translate_c.addModule("termbox2");
    // exe.root_module.addImport("termbox2", termbox2);
}
