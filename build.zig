const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize  = b.standardOptimizeOption(.{});

    const exec = b.addExecutable(.{
        .name = "shader alchemist",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize
    });

    exec.linkSystemLibrary("glfw");
    exec.linkSystemLibrary("GL");
    exec.addIncludePath(b.path("gl"));
    exec.linkLibC();
    exec.addCSourceFile(.{
        .file = b.path("gl/glad/glad.c")
    });

    b.installArtifact(exec);
    const run_exec = b.addRunArtifact(exec);
    const run_step = b.step("run", "run the app");
    run_exec.addArgs(b.args.?);
    run_step.dependOn(&run_exec.step);
}
