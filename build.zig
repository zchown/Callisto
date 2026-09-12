const std = @import("std");

const lua_scripts = [_]struct { name: []const u8, path: []const u8 }{
    .{ .name = "lua_init", .path = "lua/init.lua" },
    .{ .name = "lua_panels_evaluation", .path = "lua/panels/evaluation.lua" },
    .{ .name = "lua_panels_engine", .path = "lua/panels/engine.lua" },
    .{ .name = "lua_panels_engine_cards", .path = "lua/panels/engine_cards.lua" },
    .{ .name = "lua_panels_moves", .path = "lua/panels/moves.lua" },
    .{ .name = "lua_panels_settings", .path = "lua/panels/settings.lua" },
};

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

    const lua_dep = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zlua", lua_dep.module("zlua"));

    for (lua_scripts) |script| {
        exe.root_module.addAnonymousImport(script.name, .{
            .root_source_file = b.path(script.path),
        });
    }

    exe.addIncludePath(b.path("vendor/nanosvg"));
    exe.addCSourceFile(.{
        .file = b.path("src/c/nanosvg_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });

    exe.linkLibC();
    b.installArtifact(exe);

    b.installDirectory(.{
        .source_dir = b.path("lua"),
        .install_dir = .bin,
        .install_subdir = "lua",
    });

    if (fileExists(b, "pieces")) {
        b.installDirectory(.{
            .source_dir = b.path("pieces"),
            .install_dir = .bin,
            .install_subdir = "pieces",
        });
    }

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
