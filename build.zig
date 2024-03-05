const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const chameleon = b.dependency("chameleon", .{});

    // const libModule = b.addModule("ltn", .{
    //     .root_source_file = .{ .path = "src/lib.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // libModule.addImport("chameleon", chameleon.module("chameleon"));

    const lib = b.addStaticLibrary(.{
        .name = "ltn",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });
    // lib.root_module.addImport("lib", libModule);

    b.installArtifact(lib);

    const slib = b.addSharedLibrary(.{
        .name = "ltn.dll",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });
    // slib.root_module.addImport("lib", libModule);

    b.installArtifact(slib);

    const exe = b.addExecutable(.{
        .name = "Demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // exe.root_module.addImport("lib", libModule);
    exe.root_module.addImport("chameleon", chameleon.module("chameleon"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
