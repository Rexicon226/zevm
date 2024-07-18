const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const evm = b.addExecutable(.{
        .name = "evm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    evm.root_module.addCMacro("__STDC_CONSTANT_MACROS", "");
    evm.root_module.addCMacro("__STDC_FORMAT_MACROS", "");
    evm.root_module.addCMacro("__STDC_LIMIT_MACROS", "");
    evm.linkSystemLibrary("z");
    evm.linkLibC();
    evm.linkSystemLibrary("LLVM-17");

    b.installArtifact(evm);

    const run_step = b.step("run", "Runs the EVM");
    const run = b.addRunArtifact(evm);
    run_step.dependOn(&run.step);

    if (b.args) |args| run.addArgs(args);
}
