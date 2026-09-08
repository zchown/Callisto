const std = @import("std");
const h = @import("harness.zig");
const pos = h.pos;
const utils = h.utils;
const fen = h.fen;
const Move = pos.Move;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "addPiece updates the mailbox and both bitboards together" {
    var p = pos.Position.init();
    const s = h.sq("d4");

    p.addPiece(.White, .Knight, s);

    try expectEqual(pos.Pieces.Knight, p.getPieceFromSquare(s));
    try expectEqual(pos.Color.White, p.getColorFromSquare(s));
    try expect(utils.getBit(p.getPieceBoard(.Knight), s));
    try expect(utils.getBit(p.getColorBoard(.White), s));
    try expect(utils.getBit(p.getOccupancy(), s));
    try expect(!utils.getBit(p.getColorBoard(.Black), s));
    try expect(p.isConsistent());
}

test "addPiece onto an occupied square replaces the occupant" {
    var p = pos.Position.init();
    const s = h.sq("d4");

    p.addPiece(.Black, .Rook, s);
    p.addPiece(.White, .Pawn, s);

    try expectEqual(pos.Pieces.Pawn, p.getPieceFromSquare(s));
    try expectEqual(pos.Color.White, p.getColorFromSquare(s));
    try expectEqual(@as(pos.Bitboard, 0), p.getPieceBoard(.Rook));
    try expectEqual(@as(pos.Bitboard, 0), p.getColorBoard(.Black));
    try expect(p.isConsistent());
}

test "removePiece clears every representation" {
    var p = pos.Position.init();
    const s = h.sq("d4");

    p.addPiece(.White, .Queen, s);
    p.removePiece(s);

    try expect(p.getFromSquare(s).isNone());
    try expectEqual(@as(pos.Bitboard, 0), p.getPieceBoard(.Queen));
    try expectEqual(@as(pos.Bitboard, 0), p.getOccupancy());
    try expect(p.isConsistent());
}

test "removePiece on an empty square is harmless" {
    var p = pos.Position.init();
    p.removePiece(h.sq("d4"));
    try expectEqual(@as(pos.Bitboard, 0), p.getOccupancy());
    try expect(p.isConsistent());
}

test "getOccupancy is the union, not the intersection, of the colour boards" {
    var p = pos.Position.init();
    p.addPiece(.White, .Pawn, h.sq("a1"));
    p.addPiece(.Black, .Pawn, h.sq("h8"));

    try expectEqual(@as(u7, 2), utils.countBits(p.getOccupancy()));
    try expect(utils.getBit(p.getOccupancy(), h.sq("a1")));
    try expect(utils.getBit(p.getOccupancy(), h.sq("h8")));
}

test "slider groupings" {
    var b = try h.Board.init("4k3/8/8/8/8/8/8/R1BQK3 w - - 0 1");
    defer b.deinit();
    const p = &b.gs.cur_position;

    try expectEqual(h.bb(&.{ "a1", "d1" }), p.straightSliders(.White)); // rook + queen
    try expectEqual(h.bb(&.{ "c1", "d1" }), p.diagonalSliders(.White)); // bishop + queen
    try expectEqual(@as(pos.Bitboard, 0), p.straightSliders(.Black));
}

test "kingSquare finds the king" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    try expectEqual(h.sq("e1"), b.gs.cur_position.kingSquare(.White));
    try expectEqual(h.sq("e8"), b.gs.cur_position.kingSquare(.Black));
}

test "starting position is internally consistent" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    const p = &b.gs.cur_position;

    try expect(p.isConsistent());
    try expectEqual(@as(u7, 32), utils.countBits(p.getOccupancy()));
    try expectEqual(@as(u7, 16), utils.countBits(p.getPieceBoard(.Pawn)));
    try expectEqual(@as(u7, 8), utils.countBits(p.getPieceColorBoard(.Pawn, .White)));
    try expectEqual(@as(u7, 2), utils.countBits(p.getPieceBoard(.King)));
}

test "castle rights add and remove" {
    const all: pos.CastleRights = @intFromEnum(pos.CastleValues.AllCastling);

    try expect(pos.hasCastleRight(all, .WhiteKingside));
    try expect(pos.hasCastleRight(all, .BlackQueenside));

    const no_white = pos.removeCastleRights(all, .AllWhite);
    try expect(!pos.hasCastleRight(no_white, .WhiteKingside));
    try expect(!pos.hasCastleRight(no_white, .WhiteQueenside));
    try expect(pos.hasCastleRight(no_white, .BlackKingside));
    try expect(pos.hasCastleRight(no_white, .BlackQueenside));

    try expectEqual(pos.CastleValues.AllWhite, pos.colorCastleRights(.White));
    try expectEqual(pos.CastleValues.AllBlack, pos.colorCastleRights(.Black));
}

test "adding then removing a piece restores the hash" {
    var p = pos.Position.init();
    const base = p.hash;

    p.addPiece(.White, .Knight, h.sq("d4"));
    try expect(p.hash != base);
    p.removePiece(h.sq("d4"));
    try expectEqual(base, p.hash);
}

test "ep and castle hash updates are reversible" {
    var p = pos.Position.init();
    const base = p.hash;

    p.setEpSquare(h.sq("e3"));
    try expect(p.hash != base);
    p.setEpSquare(null);
    try expectEqual(base, p.hash);

    p.setCastleRights(@intFromEnum(pos.CastleValues.AllCastling));
    try expect(p.hash != base);
    p.setCastleRights(0);
    try expectEqual(base, p.hash);
}

test "incremental hash matches a full recompute" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();

    const moves = [_][]const u8{ "e2e4", "e7e5", "g1f3", "b8c6", "f1b5" };
    for (moves) |uci| {
        var list = b.pseudoLegal();
        const m = list.findUci(uci).?;
        try b.gs.makeMove(m);
    }

    const incremental = b.gs.cur_position.hash;
    var copy = b.gs.cur_position;
    copy.reinintZobrist(b.gs.to_move);
    try expectEqual(copy.hash, incremental);
}

test "a position reached by moves hashes like the same position parsed from FEN" {
    var played = try h.Board.init(utils.start_position);
    defer played.deinit();

    var list = played.pseudoLegal();
    try played.gs.makeMove(list.findUci("e2e4").?);

    var parsed = try h.Board.init("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1");
    defer parsed.deinit();

    try expectEqual(parsed.gs.cur_position.hash, played.gs.cur_position.hash);
}

test "side to move changes the hash" {
    var w = try h.Board.init("4k3/8/8/8/8/8/8/4K3 w - - 0 1");
    defer w.deinit();
    var b = try h.Board.init("4k3/8/8/8/8/8/8/4K3 b - - 0 1");
    defer b.deinit();
    try expect(w.gs.cur_position.hash != b.gs.cur_position.hash);
}

fn expectRoundTrip(fen_str: []const u8) !void {
    var b = try h.Board.init(fen_str);
    defer b.deinit();

    const before = b.gs.cur_position;
    const before_side = b.gs.to_move;
    const before_ply = b.gs.ply;

    var list = b.pseudoLegal();
    for (list.slice()) |m| {
        try b.gs.makeMove(m);
        b.gs.unmakeMove(m);

        try expectEqual(before.hash, b.gs.cur_position.hash);
        try expectEqual(before.castle, b.gs.cur_position.castle);
        try expectEqual(before.ep_sq, b.gs.cur_position.ep_sq);
        try expectEqual(before.halfmove, b.gs.cur_position.halfmove);
        try expectEqual(before.getOccupancy(), b.gs.cur_position.getOccupancy());
        try expectEqual(before_side, b.gs.to_move);
        try expectEqual(before_ply, b.gs.ply);
        try expect(b.gs.cur_position.isConsistent());

        for (0..64) |i| {
            const s: pos.Square = @intCast(i);
            try expectEqual(before.getPieceFromSquare(s), b.gs.cur_position.getPieceFromSquare(s));
        }
    }
}

test "make then unmake restores the position exactly" {
    try expectRoundTrip(utils.start_position);
    try expectRoundTrip("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    try expectRoundTrip("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
    try expectRoundTrip("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 0 1");
}

test "castling moves the rook as well as the king" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    try b.gs.makeMove(list.findUci("e1g1").?);

    const p = &b.gs.cur_position;
    try expectEqual(pos.Pieces.King, p.getPieceFromSquare(h.sq("g1")));
    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("f1")));
    try expect(p.getFromSquare(h.sq("e1")).isNone());
    try expect(p.getFromSquare(h.sq("h1")).isNone());
    try expect(p.isConsistent());

    try expect(!pos.hasCastleRight(p.castle, .WhiteKingside));
    try expect(!pos.hasCastleRight(p.castle, .WhiteQueenside));
    try expect(pos.hasCastleRight(p.castle, .BlackKingside));
}

test "queenside castling lands on c1 and d1" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    try b.gs.makeMove(list.findUci("e1c1").?);

    const p = &b.gs.cur_position;
    try expectEqual(pos.Pieces.King, p.getPieceFromSquare(h.sq("c1")));
    try expectEqual(pos.Pieces.Rook, p.getPieceFromSquare(h.sq("d1")));
    try expect(p.getFromSquare(h.sq("a1")).isNone());
    try expect(p.isConsistent());
}

test "en passant removes the captured pawn from its own square" {
    var b = try h.Board.init("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    const m = list.findUci("e5d6").?;
    try expect(m.isEP());
    try b.gs.makeMove(m);

    const p = &b.gs.cur_position;
    try expectEqual(pos.Pieces.Pawn, p.getPieceFromSquare(h.sq("d6")));
    try expect(p.getFromSquare(h.sq("d5")).isNone()); // the captured pawn
    try expect(p.getFromSquare(h.sq("e5")).isNone());
    try expectEqual(@as(pos.Bitboard, 0), p.getPieceColorBoard(.Pawn, .Black));
    try expect(p.isConsistent());
}

test "promotion places the chosen piece" {
    inline for (.{
        .{ "a7a8q", pos.Pieces.Queen },
        .{ "a7a8r", pos.Pieces.Rook },
        .{ "a7a8b", pos.Pieces.Bishop },
        .{ "a7a8n", pos.Pieces.Knight },
    }) |c| {
        var b = try h.Board.init("4k3/P7/8/8/8/8/8/4K3 w - - 0 1");
        defer b.deinit();

        var list = b.pseudoLegal();
        try b.gs.makeMove(list.findUci(c[0]).?);

        const p = &b.gs.cur_position;
        try expectEqual(c[1], p.getPieceFromSquare(h.sq("a8")));
        try expectEqual(pos.Color.White, p.getColorFromSquare(h.sq("a8")));
        try expect(p.getFromSquare(h.sq("a7")).isNone());
        try expect(p.isConsistent());
    }
}

test "capturing a rook on its home square removes the owner's castle right" {
    var b = try h.Board.init("r3k2r/7R/8/8/8/8/8/4K3 w kq - 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    try b.gs.makeMove(list.findUci("h7h8").?);

    const p = &b.gs.cur_position;
    try expect(!pos.hasCastleRight(p.castle, .BlackKingside));
    try expect(pos.hasCastleRight(p.castle, .BlackQueenside));
}

test "moving a rook removes only that side's right" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    try b.gs.makeMove(list.findUci("a1b1").?);

    const p = &b.gs.cur_position;
    try expect(!pos.hasCastleRight(p.castle, .WhiteQueenside));
    try expect(pos.hasCastleRight(p.castle, .WhiteKingside));
}

test "moving the king removes both of its rights" {
    var b = try h.Board.init("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    defer b.deinit();

    var list = b.pseudoLegal();
    try b.gs.makeMove(list.findUci("e1e2").?);

    const p = &b.gs.cur_position;
    try expect(!pos.hasCastleRight(p.castle, .WhiteKingside));
    try expect(!pos.hasCastleRight(p.castle, .WhiteQueenside));
    try expect(pos.hasCastleRight(p.castle, .BlackKingside));
}

test "halfmove clock resets on pawn moves and captures, and is restored on unmake" {
    var b = try h.Board.init("4k3/8/8/3p4/4P3/8/8/R3K3 w - - 17 30");
    defer b.deinit();
    try expectEqual(@as(u8, 17), b.gs.halfmoveClock());

    var list = b.pseudoLegal();


    var m = list.findUci("a1b1").?;
    try b.gs.makeMove(m);
    try expectEqual(@as(u8, 18), b.gs.halfmoveClock());
    b.gs.unmakeMove(m);
    try expectEqual(@as(u8, 17), b.gs.halfmoveClock());

    m = list.findUci(list, "e4e5").?;
    try b.gs.makeMove(m);
    try expectEqual(@as(u8, 0), b.gs.halfmoveClock());
    b.gs.unmakeMove(m);
    try expectEqual(@as(u8, 17), b.gs.halfmoveClock());
}

test "double pawn push only sets the ep square when a capture is available" {
    {
        var b = try h.Board.init("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
        defer b.deinit();
        var list = b.pseudoLegal();
        try b.gs.makeMove(list.findUci("e2e4").?);
        try expect(b.gs.cur_position.ep_sq == null);
    }
    {
        var b = try h.Board.init("4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1");
        defer b.deinit();
        var list = b.pseudoLegal();
        try b.gs.makeMove(list.findUci("e2e4").?);
        try expectEqual(h.sq("e3"), b.gs.cur_position.ep_sq.?);
    }
}

test "Piece char round trip" {
    for ("PNBRQKpnbrqk") |c| {
        const piece = pos.Piece.fromChar(c).?;
        try expectEqual(c, piece.toChar());
    }
    try expect(pos.Piece.fromChar('x') == null);
    try expect(pos.Piece.fromChar('1') == null);
    try expectEqual(@as(u8, '.'), pos.Piece.none.toChar());
}

test "Color.oposite flips and is an involution" {
    try expectEqual(pos.Color.Black, pos.Color.White.oposite());
    try expectEqual(pos.Color.White, pos.Color.Black.oposite());
    try expectEqual(pos.Color.White, pos.Color.White.oposite().oposite());
}
