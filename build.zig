const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "zig8",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zig8.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const exe = b.addExecutable(.{
        .name = "zig8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibrary(lib);

    b.installArtifact(lib);

    if (b.option(bool, "install", "install zig8") orelse false) {
        b.installArtifact(exe);
    }

    // var main_tests = b.addTest("src/main.zig");
    // main_tests.setBuildMode(mode);

    // const test_step = b.step("test", "Run library tests");
    // test_step.dependOn(&main_tests.step);
}
