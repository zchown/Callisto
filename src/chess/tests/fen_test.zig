const std = @import("std");
const h = @import("harness.zig");
const pos = h.pos;
const utils = h.utils;
const fen = h.fen;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "starting position parses correctly" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    const p = &b.gs.cur_position;

    try expectEqual(pos.Color.White, b.gs.to_move);
    try expectEqual(@as(u8, 0), b.gs.halfmoveClock());
    try expect(p.ep_sq == null);
    try expectEqual(@as(pos.CastleRights, @intFromEnum(pos.CastleValues.AllCastling)), p.castle);

    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("a1")));
    try expectEqual(pos.Color.White, p.getColorFromSquare(h.sq("a1")));
    try expectEqual(pos.Pieces.King, p.getPieceFromSquare(h.sq("e1")));
    try expectEqual(pos.Pieces.Queen, p.getPieceFromSquare(h.sq("d1")));
    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("a8")));
    try expectEqual(pos.Color.Black, p.getColorFromSquare(h.sq("a8")));
    try expect(p.getFromSquare(h.sq("e4")).isNone());

    try expect(p.isConsistent());
}

test "rank ordering puts rank 8 first" {
    var b = try h.Board.init("r7/8/8/8/8/8/8/4K3 w - - 0 1");
    defer b.deinit();
    const p = &b.gs.cur_position;

    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("a8")));
    try expect(p.getFromSquare(h.sq("a1")).isNone());
}

test "side to move" {
    var w = try h.Board.init("4k3/8/8/8/8/8/8/4K3 w - - 0 1");
    defer w.deinit();
    try expectEqual(pos.Color.White, w.gs.to_move);

    var b = try h.Board.init("4k3/8/8/8/8/8/8/4K3 b - - 0 1");
    defer b.deinit();
    try expectEqual(pos.Color.Black, b.gs.to_move);
}

test "castling rights parse into the right bits" {
    var all = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer all.deinit();
    try expect(pos.hasCastleRight(all.gs.cur_position.castle, .WhiteKingside));
    try expect(pos.hasCastleRight(all.gs.cur_position.castle, .WhiteQueenside));
    try expect(pos.hasCastleRight(all.gs.cur_position.castle, .BlackKingside));
    try expect(pos.hasCastleRight(all.gs.cur_position.castle, .BlackQueenside));

    var some = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w Kq - 0 1");
    defer some.deinit();
    try expect(pos.hasCastleRight(some.gs.cur_position.castle, .WhiteKingside));
    try expect(!pos.hasCastleRight(some.gs.cur_position.castle, .WhiteQueenside));
    try expect(!pos.hasCastleRight(some.gs.cur_position.castle, .BlackKingside));
    try expect(pos.hasCastleRight(some.gs.cur_position.castle, .BlackQueenside));

    var none = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1");
    defer none.deinit();
    try expectEqual(@as(pos.CastleRights, 0), none.gs.cur_position.castle);
}

test "castling rights record the rook files" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();

    try expectEqual(@as(u3, 7), b.gs.white_ks_rook_file);
    try expectEqual(@as(u3, 0), b.gs.white_qs_rook_file);
    try expectEqual(@as(u3, 7), b.gs.black_ks_rook_file);
    try expectEqual(@as(u3, 0), b.gs.black_qs_rook_file);

    try expectEqual(h.sq("h1"), b.gs.rookSquare(.White, true));
    try expectEqual(h.sq("a1"), b.gs.rookSquare(.White, false));
    try expectEqual(h.sq("h8"), b.gs.rookSquare(.Black, true));
    try expectEqual(h.sq("a8"), b.gs.rookSquare(.Black, false));
}

test "Shredder FEN names the rook files directly" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/RK5R w AH - 0 1");
    defer b.deinit();

    try expectEqual(@as(u3, 0), b.gs.white_qs_rook_file);
    try expectEqual(@as(u3, 7), b.gs.white_ks_rook_file);
    try expect(pos.hasCastleRight(b.gs.cur_position.castle, .WhiteQueenside));
    try expect(pos.hasCastleRight(b.gs.cur_position.castle, .WhiteKingside));
}

test "castling destinations are fixed regardless of starting files" {
    try expectEqual(h.sq("g1"), pos.GameState.kingCastleDest(.White, true));
    try expectEqual(h.sq("c1"), pos.GameState.kingCastleDest(.White, false));
    try expectEqual(h.sq("f1"), pos.GameState.rookCastleDest(.White, true));
    try expectEqual(h.sq("d1"), pos.GameState.rookCastleDest(.White, false));

    try expectEqual(h.sq("g8"), pos.GameState.kingCastleDest(.Black, true));
    try expectEqual(h.sq("c8"), pos.GameState.kingCastleDest(.Black, false));
    try expectEqual(h.sq("f8"), pos.GameState.rookCastleDest(.Black, true));
    try expectEqual(h.sq("d8"), pos.GameState.rookCastleDest(.Black, false));
}

test "en passant square parses" {
    var b = try h.Board.init("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
    defer b.deinit();
    try expectEqual(h.sq("d6"), b.gs.cur_position.ep_sq.?);

    var none = try h.Board.init("4k3/8/8/8/8/8/8/4K3 w - - 0 1");
    defer none.deinit();
    try expect(none.gs.cur_position.ep_sq == null);
}

test "move counters parse" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/4K3 w - - 25 40");
    defer b.deinit();
    try expectEqual(@as(u8, 25), b.gs.halfmoveClock());
    try expectEqual(@as(usize, 79), b.gs.ply);

    var bl = try h.Board.init("4k3/8/8/8/8/8/8/4K3 b - - 3 40");
    defer bl.deinit();
    try expectEqual(@as(usize, 80), bl.gs.ply);
}

test "toFen round trips the standard positions" {
    const cases = [_][]const u8{
        utils.start_position,
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "8/8/8/8/8/8/8/4K2k b - - 12 99",
    };

    for (cases) |f| {
        var b = try h.Board.init(f);
        defer b.deinit();
        const out = try fen.toFen(std.testing.allocator, b.gs);
        defer std.testing.allocator.free(out);
        try expectEqualStrings(f, out);
    }
}

test "malformed FENs are rejected rather than silently accepted" {
    const bad = [_][]const u8{
        "", // nothing at all
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", // no side to move
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1", // bad side
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1", // short rank
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNRR w KQkq - 0 1", // long rank
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1", // missing a rank
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNZ w KQkq - 0 1", // bad piece
        "4k3/8/8/8/8/8/8/4K3 w - e9 0 1", // impossible ep square
        "4k3/8/8/8/8/8/8/4K3 w - e4 0 1", // ep square on the wrong rank
        "4k3/8/8/8/8/8/8/4K3 w KQ - 0 1", // castling rights with no rooks
    };

    for (bad) |f| {
        const result = fen.parseFEN(f);
        if (result) |gs| {
            var g = gs;
            g.deinit();
            std.debug.print("\nFEN should have been rejected: \"{s}\"\n", .{f});
            return error.ShouldHaveFailed;
        } else |_| {}
    }
}

test "a FEN without move counters still parses" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/4K3 w - -");
    defer b.deinit();
    try expectEqual(@as(u8, 0), b.gs.halfmoveClock());
}
