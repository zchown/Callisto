const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const chess = b.addModule("chess", .{
        .root_source_file = b.path("src/chess/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const chess_module_tests = b.addTest(.{
        .name = "chess_module_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/chess/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_chess_module_tests = b.addRunArtifact(chess_module_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_chess_module_tests.step);

    if (fileExists(b, "src/chess/tests.zig")) {
        const chess_unit_tests = b.addTest(.{
            .name = "chess_unit_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/chess/tests.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_chess_unit_tests = b.addRunArtifact(chess_unit_tests);
        const run_chess_unit_tests_step = b.step("chess_unit_tests", "Run chess unit tests");
        run_chess_unit_tests_step.dependOn(&run_chess_unit_tests.step);
    }

    if (fileExists(b, "src/chess/main.zig")) {
        const chess_exe = b.addExecutable(.{
            .name = "chess",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/chess/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(chess_exe);

        const run_chess_cmd = b.addRunArtifact(chess_exe);
        run_chess_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_chess_cmd.addArgs(args);

        const run_chess_step = b.step("run-chess", "Run the standalone chess executable");
        run_chess_step.dependOn(&run_chess_cmd.step);
    }

    const exe = b.addExecutable(.{
        .name = "Callisto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("chess", chess);

    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run Callisto");
    run_step.dependOn(&run_cmd.step);
}

fn fileExists(b: *std.Build, sub_path: []const u8) bool {
    const full = b.pathFromRoot(sub_path);
    std.fs.cwd().access(full, .{}) catch return false;
    return true;
}
