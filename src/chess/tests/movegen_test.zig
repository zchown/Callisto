const std = @import("std");
const h = @import("harness.zig");
const pos = h.pos;
const utils = h.utils;
const fen = h.fen;
const movegen = h.movegen;
const attacks = h.attacks;
const Move = pos.Move;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "starting position generates 20 moves" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 20);
    try expectEqual(@as(usize, 0), h.countCaptures(&list));
    try expectEqual(@as(usize, 0), h.countPromotions(&list));
    try expectEqual(@as(usize, 0), h.countCastles(&list));
    try expectEqual(@as(usize, 0), h.countEnPassant(&list));
}

test "starting position splits into 16 pawn and 4 knight moves" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    var list = b.pseudoLegal();

    var single: usize = 0;
    var double: usize = 0;
    var knight: usize = 0;
    for (list.slice()) |m| {
        switch (b.gs.cur_position.getPieceFromSquare(m.from)) {
            .Pawn => if (m.isDoublePP()) {
                double += 1;
            } else {
                single += 1;
            },
            .Knight => knight += 1,
            else => return error.UnexpectedPieceMoved,
        }
    }
    try expectEqual(@as(usize, 8), single);
    try expectEqual(@as(usize, 8), double);
    try expectEqual(@as(usize, 4), knight);

    try h.expectHasUci(&list, "e2e4");
    try h.expectHasUci(&list, "b1c3");
    try h.expectHasUci(&list, "g1f3");
}

test "black generates the mirror of white's opening moves" {
    var b = try h.Board.init("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 20);
    try h.expectHasUci(&list, "e7e5");
    try h.expectHasUci(&list, "d7d6");
    try h.expectHasUci(&list, "b8c6");
    try h.expectNoUci(&list, "e2e4");
}

test "generateAll clears the list, appendAll does not" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();

    var list = movegen.MoveList.empty;
    movegen.generateAll(&b.gs, &list);
    try expectEqual(@as(usize, 20), list.len);

    movegen.generateAll(&b.gs, &list);
    try expectEqual(@as(usize, 20), list.len);

    movegen.appendAll(&b.gs, &list);
    try expectEqual(@as(usize, 40), list.len);
}

test "a pawn blocked head-on has no moves at all" {
    var b = try h.Board.init("4k3/8/8/8/8/4p3/4P3/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 0), h.countFrom(&list, h.sq("e2")));
    try h.expectMoveCount(&list, 4); // king only
}

test "double push is blocked by a piece on the far square" {
    var b = try h.Board.init("4k3/8/8/8/4n3/8/4P3/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "e2e3");
    try h.expectNoUci(&list, "e2e4");
    try expectEqual(@as(usize, 1), h.countFrom(&list, h.sq("e2")));
}

test "double push is only available from the home rank" {
    var b = try h.Board.init("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();
    try h.expectHasUci(&list, "e2e3");
    try h.expectHasUci(&list, "e2e4");

    var b2 = try h.Board.init("4k3/8/8/8/8/4P3/8/4K3 w - - 0 1");
    defer b2.deinit();
    var list2 = b2.pseudoLegal();
    try h.expectHasUci(&list2, "e3e4");
    try h.expectNoUci(&list2, "e3e5");
}

test "pawn captures go diagonally and only onto enemy pieces" {
    var b = try h.Board.init("4k3/8/8/8/3p1p2/4P3/8/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "e3d4");
    try h.expectHasUci(&list, "e3f4");
    try h.expectHasUci(&list, "e3e4"); // push is still available
    try expectEqual(@as(usize, 3), h.countFrom(&list, h.sq("e3")));
    try expectEqual(@as(usize, 2), h.countCaptures(&list));
}

test "pawn captures do not wrap around the board edge" {
    var b = try h.Board.init("4k3/8/8/7p/P7/8/8/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 0), h.countCaptures(&list));
    try h.expectHasUci(&list, "a4a5");
    try expectEqual(@as(usize, 1), h.countFrom(&list, h.sq("a4")));
}

test "black pawns move down the board" {
    var b = try h.Board.init("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "e7e6");
    try h.expectHasUci(&list, "e7e5");
    try h.expectNoUci(&list, "e7e8");
}

test "black pawn captures point downward and do not wrap" {
    var b = try h.Board.init("4k3/p7/1P6/8/8/8/8/4K3 b - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "a7b6");
    try h.expectHasUci(&list, "a7a6");
    try h.expectHasUci(&list, "a7a5");
    try expectEqual(@as(usize, 3), h.countFrom(&list, h.sq("a7")));
}

test "a pawn reaching the last rank generates four promotions" {
    var b = try h.Board.init("8/P7/8/8/8/8/8/K6k w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 7); 
    try expectEqual(@as(usize, 4), h.countPromotions(&list));

    for ([_][]const u8{ "a7a8q", "a7a8r", "a7a8b", "a7a8n" }) |uci| {
        try h.expectHasUci(&list, uci);
    }
}

test "promotion captures generate four moves as well" {
    var b = try h.Board.init("1n6/P7/8/8/8/8/8/K6k w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 11); // 4 pushes + 4 capture promotions + 3 king
    try expectEqual(@as(usize, 8), h.countPromotions(&list));

    for ([_][]const u8{ "a7b8q", "a7b8r", "a7b8b", "a7b8n" }) |uci| {
        try h.expectHasUci(&list, uci);
        try expect(list.findUci(uci).?.isCapture());
    }
    try expect(!list.findUci("a7a8q").?.isCapture());
}

test "a blocked pawn on the seventh rank cannot promote" {
    var b = try h.Board.init("n7/P7/8/8/8/8/8/K6k w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 0), h.countPromotions(&list));
    try expectEqual(@as(usize, 0), h.countFrom(&list, h.sq("a7")));
}

test "black promotes on the first rank" {
    var b = try h.Board.init("k6K/8/8/8/8/8/7p/8 b - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 4), h.countPromotions(&list));
    try h.expectHasUci(&list, "h2h1q");
    try expectEqual(pos.Pieces.Queen, list.findUci("h2h1q").?.promoPiece());
}

test "en passant capture is generated when the ep square is set" {
    var b = try h.Board.init("8/8/8/3pP3/8/8/8/K6k w - d6 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 5);
    try expectEqual(@as(usize, 1), h.countEnPassant(&list));

    const m = list.findUci("e5d6").?;
    try expect(m.isEP());
    try expect(m.isCapture());
    try expectEqual(h.sq("e5"), m.from);
}

test "no en passant when the ep square is absent" {
    var b = try h.Board.init("8/8/8/3pP3/8/8/8/K6k w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 0), h.countEnPassant(&list));
    try h.expectNoUci(&list, "e5d6");
}

test "two pawns can both capture en passant" {
    var b = try h.Board.init("8/8/8/3pPP2/8/8/8/K6k w - d6 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 1), h.countEnPassant(&list));

    var b2 = try h.Board.init("8/8/8/2PpP3/8/8/8/K6k w - d6 0 1");
    defer b2.deinit();
    var list2 = b2.pseudoLegal();
    try expectEqual(@as(usize, 2), h.countEnPassant(&list2));
    try h.expectHasUci(&list2, "c5d6");
    try h.expectHasUci(&list2, "e5d6");
}

test "black captures en passant downward" {
    var b = try h.Board.init("K6k/8/8/8/3Pp3/8/8/8 b - d3 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 1), h.countEnPassant(&list));
    try h.expectHasUci(&list, "e4d3");
}

test "a lone knight in the corner has two moves" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/N3K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 2), h.countFrom(&list, h.sq("a1")));
    try h.expectHasUci(&list, "a1b3");
    try h.expectHasUci(&list, "a1c2");
}

test "a knight jumps over blockers" {
    var b = try h.Board.init("4k3/8/8/8/8/PPP5/PNP5/1N2K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "b1d2");
}

test "a rook stops at the first blocker and can capture it" {
    var b = try h.Board.init("4k3/8/8/8/8/8/R2p4/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "a2b2");
    try h.expectHasUci(&list, "a2c2");
    try h.expectHasUci(&list, "a2d2"); // capture
    try h.expectNoUci(&list, "a2e2"); // blocked beyond
    try expect(list.findUci("a2d2").?.isCapture());
}

test "a rook cannot capture its own pieces" {
    var b = try h.Board.init("4k3/8/8/8/8/8/R2P4/4K3 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "a2c2");
    try h.expectNoUci(&list, "a2d2");
    try expectEqual(@as(usize, 0), h.countCaptures(&list));
}

test "a queen on an open board reaches 27 squares" {
    var b = try h.Board.init("7k/8/8/3Q4/8/8/8/K7 w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();
    try expectEqual(@as(usize, 27), h.countFrom(&list, h.sq("d5")));
}

test "bishops stay on their own colour" {
    var b = try h.Board.init("7k/8/8/8/8/8/8/B6K w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 7), h.countFrom(&list, h.sq("a1")));
    for (list.slice()) |m| {
        if (m.from != h.sq("a1")) continue;
        try expect(utils.getBit(utils.dark_squares, m.to) ==
            utils.getBit(utils.dark_squares, h.sq("a1")));
    }
}

test "both castles are available on an empty back rank" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectMoveCount(&list, 26);
    try expectEqual(@as(usize, 2), h.countCastles(&list));
    try h.expectHasUci(&list, "e1g1");
    try h.expectHasUci(&list, "e1c1");
    try expect(list.findUci("e1g1").?.isKingsideCastle());
    try expect(!list.findUci("e1c1").?.isKingsideCastle());
}

test "black castles too" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 2), h.countCastles(&list));
    try h.expectHasUci(&list, "e8g8");
    try h.expectHasUci(&list, "e8c8");
}

test "castling is blocked by a piece in the way" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectNoUci(&list, "e1g1");
    try h.expectHasUci(&list, "e1c1");
}

test "queenside castling is blocked by a piece on b1" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectNoUci(&list, "e1c1");
    try h.expectHasUci(&list, "e1g1");
}

test "castling is forbidden while in check" {
    var b = try h.Board.init("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expect(attacks.isInCheck(&b.gs.cur_position, .White));
    try expectEqual(@as(usize, 0), h.countCastles(&list));
}

test "castling is forbidden through an attacked square" {
    var b = try h.Board.init("4k3/5r2/8/8/8/8/8/R3K2R w KQ - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expect(!attacks.isInCheck(&b.gs.cur_position, .White));
    try h.expectNoUci(&list, "e1g1");
    try h.expectHasUci(&list, "e1c1");
}

test "castling is forbidden onto an attacked square" {
    var b = try h.Board.init("4k3/6r1/8/8/8/8/8/R3K2R w KQ - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectNoUci(&list, "e1g1");
    try h.expectHasUci(&list, "e1c1");
}

test "queenside castling is allowed when only b1 is attacked" {
    var b = try h.Board.init("4k3/1r6/8/8/8/8/8/R3K2R w KQ - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try h.expectHasUci(&list, "e1c1");
}

test "castling requires the right in the FEN" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();
    try expectEqual(@as(usize, 0), h.countCastles(&list));

    var b2 = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w K - 0 1");
    defer b2.deinit();
    var list2 = b2.pseudoLegal();
    try expectEqual(@as(usize, 1), h.countCastles(&list2));
    try h.expectHasUci(&list2, "e1g1");
}

test "chess960 castling from a Shredder FEN" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/RK5R w AH - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    try expectEqual(@as(usize, 2), h.countCastles(&list));
    try h.expectHasUci(&list, "b1g1"); // kingside
    try h.expectHasUci(&list, "b1c1"); // queenside

    try b.gs.makeMove(list.findUci("b1g1").?);
    const p = &b.gs.cur_position;
    try expectEqual(pos.Pieces.King, p.getPieceFromSquare(h.sq("g1")));
    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("f1")));
    try expect(p.isConsistent());
}


test "pinned pieces are still generated pseudo-legally" {
    var b = try h.Board.init("4rk2/8/8/8/8/8/4N3/4K3 w - - 0 1");
    defer b.deinit();

    var pseudo = b.pseudoLegal();
    try expectEqual(@as(usize, 6), h.countFrom(&pseudo, h.sq("e2")));
    try h.expectMoveCount(&pseudo, 10);

    var legal = try b.legal();
    try expectEqual(@as(usize, 0), h.countFrom(&legal, h.sq("e2")));
    try h.expectMoveCount(&legal, 4);
}

test "king moves onto attacked squares are pseudo-legal but not legal" {
    var b = try h.Board.init("7k/8/8/8/8/8/r7/4K3 w - - 0 1");
    defer b.deinit();

    var pseudo = b.pseudoLegal();
    try h.expectMoveCount(&pseudo, 5);
    try h.expectHasUci(&pseudo, "e1e2");

    var legal = try b.legal();
    try h.expectMoveCount(&legal, 2);
    try h.expectHasUci(&legal, "e1d1");
    try h.expectHasUci(&legal, "e1f1");
    try h.expectNoUci(&legal, "e1e2");
}

test "moves that ignore an existing check are pseudo-legal but not legal" {
    var b = try h.Board.init("4rk2/8/8/8/8/8/4P3/4K3 w - - 0 1");
    defer b.deinit();

    var pseudo = b.pseudoLegal();
    try h.expectHasUci(&pseudo, "e2e3");

    var legal = try b.legal();
    try h.expectHasUci(&legal, "e2e3");
    try h.expectHasUci(&legal, "e2e4");
}

test "legal move counts for the standard perft positions" {
    const cases = [_]struct { f: []const u8, n: usize }{
        .{ .f = utils.start_position, .n = 20 },
        .{ .f = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", .n = 48 },
        .{ .f = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", .n = 14 },
        .{ .f = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", .n = 6 },
        .{ .f = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", .n = 44 },
        .{ .f = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", .n = 46 },
    };

    for (cases) |c| {
        var b = try h.Board.init(c.f);
        defer b.deinit();
        var list = try b.legal();
        try h.expectMoveCount(&list, c.n);
    }
}

test "checkmate and stalemate produce no legal moves" {
    var mate = try h.Board.init("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3");
    defer mate.deinit();
    var mate_list = try mate.legal();
    try h.expectMoveCount(&mate_list, 0);
    try expect(attacks.isInCheck(&mate.gs.cur_position, .White));

    var stale = try h.Board.init("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
    defer stale.deinit();
    var stale_list = try stale.legal();
    try h.expectMoveCount(&stale_list, 0);
    try expect(!attacks.isInCheck(&stale.gs.cur_position, .Black));
}

test "every generated move leaves the board consistent" {
    const positions = [_][]const u8{
        utils.start_position,
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    };

    for (positions) |f| {
        var b = try h.Board.init(f);
        defer b.deinit();
        var list = b.pseudoLegal();

        for (list.slice()) |m| {
            try b.gs.makeMove(m);
            try expect(b.gs.cur_position.isConsistent());
            b.gs.unmakeMove(m);
        }
    }
}

test "no duplicate moves are generated" {
    const positions = [_][]const u8{
        utils.start_position,
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        "1n6/P7/8/8/8/8/8/K6k w - - 0 1",
    };

    for (positions) |f| {
        var b = try h.Board.init(f);
        defer b.deinit();
        var list = b.pseudoLegal();

        for (list.slice(), 0..) |m, i| {
            for (list.slice()[i + 1 ..]) |other| {
                try expect(!m.eql(other));
            }
        }
    }
}

test "every generated move starts on a friendly piece" {
    var b = try h.Board.init("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    for (list.slice()) |m| {
        const piece = b.gs.cur_position.getFromSquare(m.from);
        try expect(!piece.isNone());
        try expectEqual(pos.Color.White, piece.color);

        const target = b.gs.cur_position.getFromSquare(m.to);
        if (!target.isNone() and !m.isCastle()) {
            try expectEqual(pos.Color.Black, target.color);
        }
    }
}

test "capture flags match the board" {
    var b = try h.Board.init("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    defer b.deinit();
    var list = b.pseudoLegal();

    for (list.slice()) |m| {
        if (m.isEP()) continue; // the captured pawn is not on the target square
        const occupied = !b.gs.cur_position.getFromSquare(m.to).isNone();
        try expectEqual(occupied, m.isCapture());
    }
}
