const std = @import("std");
const root = @import("../root.zig");
const pos = root.pos;
const utils = root.utils;
const fen = root.fen;
const attacks = root.attacks;
const perft = root.perft;

pub const Expectation = struct {
    depth: u32,
    nodes: u64,
};

pub const Case = struct {
    fen: []const u8,
    line_no: usize,
    expectations: []const Expectation,

    pub fn maxDepth(self: Case) u32 {
        var m: u32 = 0;
        for (self.expectations) |e| m = @max(m, e.depth);
        return m;
    }
};

pub const Suite = struct {
    arena: std.heap.ArenaAllocator,
    cases: []const Case,

    pub fn deinit(self: *Suite) void {
        self.arena.deinit();
    }
};

pub const ParseError = error{
    MissingFen,
    MissingDepthMarker,
    InvalidDepth,
    InvalidNodeCount,
    NoExpectations,
};

pub fn parseLine(allocator: std.mem.Allocator, line: []const u8, line_no: usize) !?Case {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '#') return null;
    if (std.mem.startsWith(u8, trimmed, "//")) return null;

    var fields = std.mem.splitScalar(u8, trimmed, ';');

    const fen_field = fields.next() orelse return ParseError.MissingFen;
    const fen_text = std.mem.trim(u8, fen_field, " \t");
    if (fen_text.len == 0) return ParseError.MissingFen;

    var list = std.ArrayList(Expectation).empty;
    errdefer list.deinit(allocator);

    while (fields.next()) |field| {
        const spec = std.mem.trim(u8, field, " \t");
        if (spec.len == 0) continue;

        if (spec[0] != 'D' and spec[0] != 'd') return ParseError.MissingDepthMarker;

        var parts = std.mem.tokenizeAny(u8, spec[1..], " \t");
        const depth_text = parts.next() orelse return ParseError.InvalidDepth;
        const nodes_text = parts.next() orelse return ParseError.InvalidNodeCount;

        const depth = std.fmt.parseInt(u32, depth_text, 10) catch return ParseError.InvalidDepth;
        const nodes = std.fmt.parseInt(u64, nodes_text, 10) catch return ParseError.InvalidNodeCount;
        if (depth == 0) return ParseError.InvalidDepth;

        try list.append(allocator, .{ .depth = depth, .nodes = nodes });
    }

    if (list.items.len == 0) return ParseError.NoExpectations;

    return Case{
        .fen = try allocator.dupe(u8, fen_text),
        .line_no = line_no,
        .expectations = try list.toOwnedSlice(allocator),
    };
}

pub fn parseSuite(child_allocator: std.mem.Allocator, text: []const u8) !Suite {
    var arena = std.heap.ArenaAllocator.init(child_allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    var cases = std.ArrayList(Case).empty;

    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |line| {
        line_no += 1;
        if (try parseLine(a, line, line_no)) |c| {
            try cases.append(a, c);
        }
    }

    return .{
        .arena = arena,
        .cases = try cases.toOwnedSlice(a),
    };
}

pub const max_suite_bytes = 8 * 1024 * 1024;

pub fn loadSuite(allocator: std.mem.Allocator, path: []const u8) !Suite {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const text = try file.readToEndAlloc(allocator, max_suite_bytes);
    defer allocator.free(text);

    return parseSuite(allocator, text);
}

pub const Options = struct {
    max_depth: u32 = 4,
    use_tt: bool = false,
    tt_size_mb: usize = perft.default_tt_size_mb,
    verbose: bool = false,
};

pub const Failure = struct {
    fen: []const u8,
    line_no: usize,
    depth: u32,
    expected: u64,
    got: u64,
};

pub const Summary = struct {
    checked: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    nodes: u64 = 0,
    nanos: u64 = 0,

    pub fn nps(self: Summary) u64 {
        if (self.nanos == 0) return 0;
        return @intFromFloat(@as(f64, @floatFromInt(self.nodes)) /
            (@as(f64, @floatFromInt(self.nanos)) / 1e9));
    }
};

pub fn runSuite(
    allocator: std.mem.Allocator,
    suite: Suite,
    opts: Options,
    failures: ?*std.ArrayList(Failure),
) !Summary {
    try attacks.init();

    var tt: ?perft.TranspositionTable = if (opts.use_tt)
        try perft.TranspositionTable.init(allocator, opts.tt_size_mb)
    else
        null;
    defer if (tt) |*t| t.deinit(allocator);

    var summary = Summary{};
    var timer = try std.time.Timer.start();

    for (suite.cases) |case| {
        for (case.expectations) |exp| {
            if (exp.depth > opts.max_depth) {
                summary.skipped += 1;
                continue;
            }

            var gs = try fen.parseFEN(case.fen);

            if (tt) |*t| t.clear();

            const start = timer.read();
            const got = if (tt) |*t|
                (try perft.perftTT(&gs, exp.depth, t)).total
            else
                try perft.perft(&gs, exp.depth);
            const elapsed = timer.read() - start;

            summary.checked += 1;
            summary.nodes += got;
            summary.nanos += elapsed;

            if (got == exp.nodes) {
                summary.passed += 1;
            } else {
                summary.failed += 1;
                if (failures) |f| {
                    try f.append(allocator, .{
                        .fen = case.fen,
                        .line_no = case.line_no,
                        .depth = exp.depth,
                        .expected = exp.nodes,
                        .got = got,
                    });
                }
            }

            if (opts.verbose) {
                std.debug.print("{s} line {d} D{d}: {d}{s}\n", .{
                    if (got == exp.nodes) "ok  " else "FAIL",
                    case.line_no,
                    exp.depth,
                    got,
                    if (got == exp.nodes) "" else " (mismatch)",
                });
            }
        }
    }

    return summary;
}

pub fn printDivide(fen_text: []const u8, depth: u32) !void {
    try attacks.init();

    var gs = try fen.parseFEN(fen_text);

    var buf: [utils.max_moves]perft.DivideEntry = undefined;
    const entries = try perft.divide(&gs, depth, &buf);

    var uci: [5]u8 = undefined;
    for (entries) |e| {
        std.debug.print("{s}: {d}\n", .{ e.move.toUci(&uci), e.nodes });
    }
    std.debug.print("moves {d}, nodes {d}\n", .{ entries.len, perft.divideTotal(entries) });
}

test "parseLine reads a fen and its depth expectations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const line = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ;D1 20 ;D2 400 ;D3 8902";
    const case = (try parseLine(arena.allocator(), line, 7)).?;

    try testing.expectEqualStrings(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        case.fen,
    );
    try testing.expectEqual(@as(usize, 7), case.line_no);
    try testing.expectEqual(@as(usize, 3), case.expectations.len);
    try testing.expectEqual(@as(u32, 1), case.expectations[0].depth);
    try testing.expectEqual(@as(u64, 20), case.expectations[0].nodes);
    try testing.expectEqual(@as(u64, 8902), case.expectations[2].nodes);
    try testing.expectEqual(@as(u32, 3), case.maxDepth());
}

test "parseLine tolerates spacing, lowercase d and out-of-order depths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const line = "  8/8/8/8/8/8/8/K6k w - - 0 1   ;d3   12 ;D1 3  ";
    const case = (try parseLine(arena.allocator(), line, 1)).?;

    try testing.expectEqualStrings("8/8/8/8/8/8/8/K6k w - - 0 1", case.fen);
    try testing.expectEqual(@as(usize, 2), case.expectations.len);
    try testing.expectEqual(@as(u32, 3), case.expectations[0].depth);
    try testing.expectEqual(@as(u64, 12), case.expectations[0].nodes);
    try testing.expectEqual(@as(u32, 3), case.maxDepth());
}

test "parseLine skips blanks and comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expect((try parseLine(a, "", 1)) == null);
    try testing.expect((try parseLine(a, "   \t ", 1)) == null);
    try testing.expect((try parseLine(a, "# a comment", 1)) == null);
    try testing.expect((try parseLine(a, "// also a comment", 1)) == null);
}

test "parseLine rejects malformed lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // No expectations at all.
    try testing.expectError(ParseError.NoExpectations, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1", 1));
    // Depth field missing its marker.
    try testing.expectError(ParseError.MissingDepthMarker, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1 ;1 20", 1));
    // Node count missing.
    try testing.expectError(ParseError.InvalidNodeCount, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1 ;D1", 1));
    // Non-numeric depth and count.
    try testing.expectError(ParseError.InvalidDepth, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1 ;Dx 20", 1));
    try testing.expectError(ParseError.InvalidNodeCount, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1 ;D1 xx", 1));
    // Depth 0 is meaningless.
    try testing.expectError(ParseError.InvalidDepth, parseLine(a, "8/8/8/8/8/8/8/K6k w - - 0 1 ;D0 1", 1));
    // Empty fen.
    try testing.expectError(ParseError.MissingFen, parseLine(a, ";D1 20", 1));
}

test "parseSuite handles multiple lines, comments and CRLF" {
    const text =
        "# standard positions\r\n" ++
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ;D1 20 ;D2 400\r\n" ++
        "\r\n" ++
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1 ;D1 14\r\n";

    var suite = try parseSuite(testing.allocator, text);
    defer suite.deinit();

    try testing.expectEqual(@as(usize, 2), suite.cases.len);
    try testing.expectEqual(@as(usize, 2), suite.cases[0].line_no);
    try testing.expectEqual(@as(usize, 4), suite.cases[1].line_no);
    try testing.expectEqual(@as(u64, 14), suite.cases[1].expectations[0].nodes);
}

const testing = std.testing;

const startpos = utils.start_position;
const kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
const position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1";
const position4 = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1";

fn board(fen_text: []const u8) !pos.GameState {
    try attacks.init();
    return fen.parseFEN(fen_text);
}

test "perft of depth zero is one" {
    var gs = try board(startpos);
    defer gs.deinit();
    try testing.expectEqual(@as(u64, 1), try perft.perft(&gs, 0));

    const detailed = try perft.perftDetailed(&gs, 0);
    try testing.expectEqual(@as(u64, 1), detailed.total);
}

test "perft node counts at shallow depth" {
    const cases = [_]struct { f: []const u8, d: u32, n: u64 }{
        .{ .f = startpos, .d = 1, .n = 20 },
        .{ .f = startpos, .d = 2, .n = 400 },
        .{ .f = startpos, .d = 3, .n = 8902 },
        .{ .f = kiwipete, .d = 1, .n = 48 },
        .{ .f = kiwipete, .d = 2, .n = 2039 },
        .{ .f = position3, .d = 1, .n = 14 },
        .{ .f = position3, .d = 2, .n = 191 },
        .{ .f = position3, .d = 3, .n = 2812 },
        .{ .f = position4, .d = 1, .n = 6 },
        .{ .f = position4, .d = 2, .n = 264 },
    };

    for (cases) |c| {
        var gs = try board(c.f);
        defer gs.deinit();
        try testing.expectEqual(c.n, try perft.perft(&gs, c.d));
    }
}

test "leaf breakdown matches the published category counts" {
    const cases = [_]struct {
        f: []const u8,
        d: u32,
        want: perft.PerftResult,
    }{
        .{ .f = startpos, .d = 1, .want = .{ .total = 20 } },
        .{ .f = startpos, .d = 3, .want = .{ .total = 8902, .captures = 34 } },
        .{ .f = kiwipete, .d = 1, .want = .{ .total = 48, .captures = 8, .castling = 2 } },
        .{ .f = kiwipete, .d = 2, .want = .{
            .total = 2039,
            .captures = 351,
            .en_passant = 1,
            .castling = 91,
        } },
        .{ .f = position3, .d = 1, .want = .{ .total = 14, .captures = 1 } },
        .{ .f = position4, .d = 2, .want = .{
            .total = 264,
            .captures = 87,
            .castling = 6,
            .promotions = 48,
        } },
    };

    for (cases) |c| {
        var gs = try board(c.f);
        defer gs.deinit();
        const got = try perft.perftDetailed(&gs, c.d);
        testing.expectEqual(c.want, got) catch |err| {
            std.debug.print("\n{s} D{d}\n  want {any}\n  got  {any}\n", .{ c.f, c.d, c.want, got });
            return err;
        };
    }
}

test "en passant captures are also counted as captures" {
    var gs = try board(kiwipete);
    defer gs.deinit();
    const res = try perft.perftDetailed(&gs, 2);
    try testing.expect(res.en_passant <= res.captures);
}

test "perftDetailed total agrees with plain perft" {
    for ([_][]const u8{ startpos, kiwipete, position3, position4 }) |f| {
        for (1..4) |d| {
            var gs = try board(f);
            defer gs.deinit();
            const plain = try perft.perft(&gs, @intCast(d));
            const detailed = try perft.perftDetailed(&gs, @intCast(d));
            try testing.expectEqual(plain, detailed.total);
        }
    }
}

test "divide sums to the perft total" {
    var buf: [utils.max_moves]perft.DivideEntry = undefined;

    for ([_][]const u8{ startpos, kiwipete, position3, position4 }) |f| {
        for (1..4) |d| {
            var gs = try board(f);
            defer gs.deinit();

            const entries = try perft.divide(&gs, @intCast(d), &buf);
            try testing.expectEqual(
                try perft.perft(&gs, @intCast(d)),
                perft.divideTotal(entries),
            );

            // One entry per legal root move.
            try testing.expectEqual(try perft.perft(&gs, 1), @as(u64, entries.len));
        }
    }
}

test "divide output is sorted by move text" {
    var gs = try board(startpos);
    defer gs.deinit();

    var buf: [utils.max_moves]perft.DivideEntry = undefined;
    const entries = try perft.divide(&gs, 2, &buf);

    var prev: [5]u8 = undefined;
    var prev_len: usize = 0;
    for (entries) |e| {
        var cur: [5]u8 = undefined;
        const text = e.move.toUci(&cur);
        if (prev_len != 0) {
            try testing.expect(!std.mem.lessThan(u8, text, prev[0..prev_len]));
        }
        @memcpy(prev[0..text.len], text);
        prev_len = text.len;
    }
}

test "divide leaves the position untouched" {
    var gs = try board(kiwipete);
    defer gs.deinit();

    const before = gs.cur_position.hash;
    var buf: [utils.max_moves]perft.DivideEntry = undefined;
    _ = try perft.divide(&gs, 3, &buf);

    try testing.expectEqual(before, gs.cur_position.hash);
    try testing.expectEqual(pos.Color.White, gs.to_move);
}

test "table stores and retrieves a result" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 1);
    defer tt.deinit(testing.allocator);

    const key: u64 = 0xdeadbeefcafef00d;
    const res = perft.PerftResult{ .total = 1234, .captures = 56 };

    try testing.expect(tt.get(key, 3) == null);
    tt.store(key, 3, res);
    try testing.expect(tt.get(key, 3).?.eql(res));
}

test "table entries are keyed by depth as well as position" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 1);
    defer tt.deinit(testing.allocator);

    const key: u64 = 0x1234567812345678;
    tt.store(key, 3, .{ .total = 8902 });
    tt.store(key, 4, .{ .total = 197281 });

    try testing.expectEqual(@as(u64, 8902), tt.get(key, 3).?.total);
    try testing.expectEqual(@as(u64, 197281), tt.get(key, 4).?.total);
    try testing.expect(tt.get(key, 5) == null);
}

test "table starts empty and clears" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 1);
    defer tt.deinit(testing.allocator);

    for (0..256) |i| {
        try testing.expect(tt.get(@intCast(i *% 0x9e3779b97f4a7c15), 3) == null);
    }
    try testing.expectEqual(@as(usize, 0), tt.hashfull());

    tt.store(0xabc, 2, .{ .total = 7 });
    try testing.expect(tt.get(0xabc, 2) != null);

    tt.clear();
    try testing.expect(tt.get(0xabc, 2) == null);
}

test "probing wraps around the end of the table" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 1);
    defer tt.deinit(testing.allocator);

    const last = @as(u64, tt.count() - 1);
    for (0..perft.default_probe) |i| {
        tt.store(last + (@as(u64, @intCast(i)) * @as(u64, tt.count())), 3, .{ .total = i });
    }
    try testing.expect(tt.get(last, 3) != null);
}

test "table survives more entries than it has slots" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 1);
    defer tt.deinit(testing.allocator);

    var key: u64 = 1;
    for (0..tt.count() * 2) |i| {
        key = key *% 0x9e3779b97f4a7c15 +% 1;
        tt.store(key, @intCast((i % 8) + 1), .{ .total = i });
    }
    try testing.expect(tt.hashfull() > 0);
}

test "table-accelerated perft agrees with the exact version" {
    var tt = try perft.TranspositionTable.init(testing.allocator, 4);
    defer tt.deinit(testing.allocator);

    for ([_][]const u8{ startpos, kiwipete, position3, position4 }) |f| {
        for (1..4) |d| {
            var gs = try board(f);
            defer gs.deinit();

            tt.clear();
            const exact = try perft.perftDetailed(&gs, @intCast(d));
            const cached = try perft.perftTT(&gs, @intCast(d), &tt);
            try testing.expect(exact.eql(cached));

            const warm = try perft.perftTT(&gs, @intCast(d), &tt);
            try testing.expect(exact.eql(warm));
        }
    }

    {
        var gs = try board(startpos);
        defer gs.deinit();
        tt.clear();
        try testing.expectEqual(@as(u64, 197281), (try perft.perftTT(&gs, 4, &tt)).total);
        try testing.expectEqual(@as(u64, 197281), (try perft.perftTT(&gs, 4, &tt)).total);
        try testing.expect(tt.hashfull() > 0);
    }
}

test "table too small to probe is rejected rather than misbehaving" {
    try testing.expectError(
        error.TableTooSmall,
        perft.TranspositionTable.init(testing.allocator, 0),
    );
}

test "perft suite from file" {
    const a = testing.allocator;
 
    const path = try std.process.getEnvVarOwned(a, "PERFT_EPD");
    defer a.free(path);
 
    var suite = loadSuite(a, path) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer suite.deinit();
 
    var max_depth: u32 = 3;
    if (std.process.getEnvVarOwned(a, "PERFT_MAX_DEPTH")) |text| {
        defer a.free(text);
        max_depth = std.fmt.parseInt(u32, std.mem.trim(u8, text, " \t\r\n"), 10) catch max_depth;
    } else |_| {}
 
    var failures = std.ArrayList(Failure).empty;
    defer failures.deinit(a);
 
    const summary = try runSuite(a, suite, .{ .max_depth = max_depth, .verbose = true }, &failures);
 
    if (failures.items.len > 0) {
        std.debug.print("\n{d} perft mismatch(es):\n", .{failures.items.len});
        for (failures.items) |f| {
            std.debug.print(
                "  line {d} D{d}: expected {d}, got {d}\n    {s}\n",
                .{ f.line_no, f.depth, f.expected, f.got, f.fen },
            );
        }
        std.debug.print(
            "  (run `zig build perft-divide -- \"<fen>\" <depth>` to localise a mismatch)\n",
            .{},
        );
    }
 
    std.debug.print(
        "perft suite: {d}/{d} passed, {d} skipped beyond depth {d}, {d} nodes\n",
        .{ summary.passed, summary.checked, summary.skipped, max_depth, summary.nodes },
    );
 
    try testing.expectEqual(@as(usize, 0), summary.failed);
}

