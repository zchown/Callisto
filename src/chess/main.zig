const std = @import("std");
const root = @import("root.zig");
const attacks = root.attacks;
const fen = root.fen;
const perft = root.perft;
const suite = @import("tests/perft_test.zig");


const usage =
    \\usage:
    \\  perft suite [path] [max_depth]   run an EPD perft suite (default: perft_suite.epd, depth 5)
    \\  perft divide <fen> <depth>       per-root-move node counts
    \\  perft bench <fen> <depth>        time a single position
    \\
;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);

    const cmd = if (args.len > 1) args[1] else "suite";

    if (std.mem.eql(u8, cmd, "suite")) {
        const path = if (args.len > 2) args[2] else "~/ComputerScience/Personal/Callisto/src/chess/perft_suite/standard.epd";
        const max_depth: u32 = if (args.len > 3)
            try std.fmt.parseInt(u32, args[3], 10)
        else
            5;
        try runSuite(a, path, max_depth);
    } else if (std.mem.eql(u8, cmd, "divide")) {
        if (args.len < 4) return fail("divide needs a fen and a depth");
        try suite.printDivide(args[2], try std.fmt.parseInt(u32, args[3], 10));
    } else if (std.mem.eql(u8, cmd, "bench")) {
        if (args.len < 4) return fail("bench needs a fen and a depth");
        try bench(args[2], try std.fmt.parseInt(u32, args[3], 10));
    } else {
        return fail(usage);
    }
}

fn fail(msg: []const u8) !void {
    std.debug.print("{s}\n", .{msg});
    return error.BadUsage;
}

fn runSuite(a: std.mem.Allocator, path: []const u8, max_depth: u32) !void {
    var s = suite.loadSuite(a, path) catch |err| {
        std.debug.print("could not read suite \"{s}\": {s}\n", .{ path, @errorName(err) });
        return err;
    };
    defer s.deinit();

    std.debug.print("{s}: {d} positions, depths up to {d}\n\n", .{ path, s.cases.len, max_depth });

    var failures = std.ArrayList(suite.Failure).empty;
    defer failures.deinit(a);

    const summary = try suite.runSuite(a, s, .{ .max_depth = max_depth, .use_tt = true, .verbose = true }, &failures);

    for (failures.items) |f| {
        std.debug.print("FAIL line {d} D{d}: expected {d}, got {d}\n  {s}\n", .{
            f.line_no, f.depth, f.expected, f.got, f.fen,
        });
    }

    std.debug.print(
        "\n{d}/{d} passed, {d} failed, {d} skipped\n{d} nodes in {d:.2}s ({d} nps)\n",
        .{
            summary.passed, summary.checked,
            summary.failed, summary.skipped,
            summary.nodes,  @as(f64, @floatFromInt(summary.nanos)) / 1e9,
            summary.nps(),
        },
    );

    if (summary.failed > 0) return error.PerftMismatch;
}

fn bench(fen_text: []const u8, depth: u32) !void {
    try attacks.init();

    var gs = try fen.parseFEN(fen_text);

    var timer = try std.time.Timer.start();
    const res = try perft.perftDetailed(&gs, depth);
    const ns = timer.read();

    std.debug.print(
        \\depth       {d}
        \\nodes       {d}
        \\captures    {d}
        \\en passant  {d}
        \\castles     {d}
        \\promotions  {d}
        \\time        {d:.3}s
        \\nps         {d}
        \\
    , .{
        depth,                             res.total,
        res.captures,                      res.en_passant,
        res.castling,                      res.promotions,
        @as(f64, @floatFromInt(ns)) / 1e9, if (ns > 0) res.total * 1_000_000_000 / ns else 0,
    });
}
