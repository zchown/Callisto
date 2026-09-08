const std = @import("std");
const h = @import("harness.zig");
const attacks = h.attacks;
const utils = h.utils;
const pos = h.pos;
const fen = h.fen;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "knight attacks in the centre and in the corners" {
    try expectEqual(h.bb(&.{ "c3", "c5", "d2", "d6", "f2", "f6", "g3", "g5" }), attacks.knightAttacks(h.sq("e4")));

    try expectEqual(h.bb(&.{ "b3", "c2" }), attacks.knightAttacks(h.sq("a1")));
    try expectEqual(h.bb(&.{ "g3", "f2" }), attacks.knightAttacks(h.sq("h1")));
    try expectEqual(h.bb(&.{ "b6", "c7" }), attacks.knightAttacks(h.sq("a8")));
    try expectEqual(h.bb(&.{ "g6", "f7" }), attacks.knightAttacks(h.sq("h8")));
}

test "knight attack counts over the whole board" {
    var total: usize = 0;
    for (0..64) |i| total += utils.countBits(attacks.knightAttacks(@intCast(i)));
    try expectEqual(@as(usize, 336), total);

    try expectEqual(@as(u7, 8), utils.countBits(attacks.knightAttacks(h.sq("d5"))));
    try expectEqual(@as(u7, 3), utils.countBits(attacks.knightAttacks(h.sq("b1"))));
    try expectEqual(@as(u7, 3), utils.countBits(attacks.knightAttacks(h.sq("a2"))));
}

test "knight attacks never wrap across a file boundary" {
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const f = utils.fileOf(s);
        var a = attacks.knightAttacks(s);
        while (a != 0) {
            const t = utils.popLsb(&a);
            const df = @as(i8, utils.fileOf(t)) - @as(i8, f);
            try expect(df >= -2 and df <= 2);
        }
    }
}

test "king attacks in the centre, on an edge and in a corner" {
    try expectEqual(h.bb(&.{ "d3", "d4", "d5", "e3", "e5", "f3", "f4", "f5" }), attacks.kingAttacks(h.sq("e4")));
    try expectEqual(h.bb(&.{ "a1", "b1", "b2" }), attacks.kingAttacks(h.sq("a2")) & ~h.bb(&.{ "a3", "b3" }));
    try expectEqual(h.bb(&.{ "a2", "b1", "b2" }), attacks.kingAttacks(h.sq("a1")));
    try expectEqual(h.bb(&.{ "g7", "g8", "h7" }), attacks.kingAttacks(h.sq("h8")));
}

test "king attack counts" {
    try expectEqual(@as(u7, 8), utils.countBits(attacks.kingAttacks(h.sq("d4"))));
    try expectEqual(@as(u7, 5), utils.countBits(attacks.kingAttacks(h.sq("a4"))));
    try expectEqual(@as(u7, 3), utils.countBits(attacks.kingAttacks(h.sq("a1"))));
}

test "king attacks are symmetric" {
    for (0..64) |i| {
        const a: pos.Square = @intCast(i);
        var bbs = attacks.kingAttacks(a);
        while (bbs != 0) {
            const b = utils.popLsb(&bbs);
            try expect(utils.getBit(attacks.kingAttacks(b), a));
        }
    }
}

test "pawn attacks point the right way for each colour" {
    try expectEqual(h.bb(&.{ "d5", "f5" }), attacks.pawnAttacks(.White, h.sq("e4")));
    try expectEqual(h.bb(&.{ "d3", "f3" }), attacks.pawnAttacks(.Black, h.sq("e4")));
}

test "pawn attacks on the a and h files do not wrap" {
    try expectEqual(h.bb(&.{"b5"}), attacks.pawnAttacks(.White, h.sq("a4")));
    try expectEqual(h.bb(&.{"g5"}), attacks.pawnAttacks(.White, h.sq("h4")));
    try expectEqual(h.bb(&.{"b3"}), attacks.pawnAttacks(.Black, h.sq("a4")));
    try expectEqual(h.bb(&.{"g3"}), attacks.pawnAttacks(.Black, h.sq("h4")));
}

test "pawn attacks off the end of the board are empty" {
    try expectEqual(@as(pos.Bitboard, 0), attacks.pawnAttacks(.White, h.sq("e8")));
    try expectEqual(@as(pos.Bitboard, 0), attacks.pawnAttacks(.Black, h.sq("e1")));
}

test "pawn attack reversal identity" {
    for (0..64) |i| {
        const from: pos.Square = @intCast(i);
        var a = attacks.pawnAttacks(.White, from);
        while (a != 0) {
            const to = utils.popLsb(&a);
            try expect(utils.getBit(attacks.pawnAttacks(.Black, to), from));
        }
    }
}

test "pawnAttacksBB matches the per-square table" {
    const pawns = h.bb(&.{ "a2", "e4", "h7" });
    var expected: pos.Bitboard = 0;
    var p = pawns;
    while (p != 0) expected |= attacks.pawnAttacks(.White, utils.popLsb(&p));
    try expectEqual(expected, attacks.pawnAttacksBB(.White, pawns));
}

test "attacksFrom dispatches on piece type" {
    try h.attacks.init();
    const occ: pos.Bitboard = 0;
    const s = h.sq("d4");

    try expectEqual(attacks.knightAttacks(s), attacks.attacksFrom(.Knight, .White, s, occ));
    try expectEqual(attacks.kingAttacks(s), attacks.attacksFrom(.King, .White, s, occ));
    try expectEqual(attacks.pawnAttacks(.Black, s), attacks.attacksFrom(.Pawn, .Black, s, occ));
    try expectEqual(h.magic.getRookAttacks(s, occ), attacks.attacksFrom(.Rook, .White, s, occ));
    try expectEqual(h.magic.getBishopAttacks(s, occ), attacks.attacksFrom(.Bishop, .White, s, occ));
    try expectEqual(h.magic.getQueenAttacks(s, occ), attacks.attacksFrom(.Queen, .White, s, occ));
    try expectEqual(@as(pos.Bitboard, 0), attacks.attacksFrom(.None, .White, s, occ));
}

test "isSquareAttacked in the starting position" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    const p = &b.gs.cur_position;

    for (0..8) |f| {
        const s = pos.squareFromFileRank(@intCast(f), 2);
        try expect(attacks.isSquareAttacked(p, s, .White));
    }
    for (0..8) |f| {
        const s = pos.squareFromFileRank(@intCast(f), 3);
        try expect(!attacks.isSquareAttacked(p, s, .White));
        try expect(!attacks.isSquareAttacked(p, s, .Black));
    }
    try expect(attacks.isSquareAttacked(p, h.sq("e7"), .Black));
    try expect(!attacks.isSquareAttacked(p, h.sq("e7"), .White));
}

test "attackersTo counts both colours" {
    var b = try h.Board.init(utils.start_position);
    defer b.deinit();
    const p = &b.gs.cur_position;
    const occ = p.getOccupancy();

    try expectEqual(h.bb(&.{ "d2", "f2" }), attacks.attackersTo(p, h.sq("e3"), occ));

    try expectEqual(h.bb(&.{ "b2", "b1" }), attacks.attackersTo(p, h.sq("a3"), occ));

    try expectEqual(h.bb(&.{ "e1", "d1", "c1", "b1" }), attacks.attackersTo(p, h.sq("d2"), occ));
}

test "attackersToBy filters by colour" {
    var b = try h.Board.init("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1");
    defer b.deinit();
    const p = &b.gs.cur_position;
    const occ = p.getOccupancy();

    try expectEqual(h.bb(&.{"e4"}), attacks.attackersToBy(p, h.sq("d5"), .White, occ));
    try expectEqual(h.bb(&.{"d5"}), attacks.attackersToBy(p, h.sq("e4"), .Black, occ));
}

test "sliding attacks are blocked by intervening pieces" {
    var b = try h.Board.init("k7/8/8/8/8/P7/8/R3K3 w - - 0 1");
    defer b.deinit();
    const p = &b.gs.cur_position;

    try expect(!attacks.isSquareAttacked(p, h.sq("a8"), .White));
    try expect(attacks.isSquareAttacked(p, h.sq("a3"), .White));

    var p2 = p.*;
    p2.removePiece(h.sq("a3"));
    try expect(attacks.isSquareAttacked(&p2, h.sq("a8"), .White));
}

test "isInCheck detects checks from each piece type" {
    const cases = [_]struct { f: []const u8, white_in_check: bool }{
        .{ .f = "4k3/8/8/8/8/8/8/4K3 w - - 0 1", .white_in_check = false },
        .{ .f = "4k3/8/8/8/8/8/8/r3K3 w - - 0 1", .white_in_check = true }, // rook
        .{ .f = "4k3/8/8/8/8/8/8/b3K3 w - - 0 1", .white_in_check = false }, // wrong colour square
        .{ .f = "4k3/8/8/8/8/8/5p2/4K3 w - - 0 1", .white_in_check = true }, // pawn
        .{ .f = "4k3/8/8/8/8/8/3p4/4K3 w - - 0 1", .white_in_check = true }, // pawn, other side
        .{ .f = "4k3/8/8/8/8/8/4p3/4K3 w - - 0 1", .white_in_check = false }, // pawns don't check forward
        .{ .f = "4k3/8/8/8/8/3n4/8/4K3 w - - 0 1", .white_in_check = true }, // knight
        .{ .f = "4k3/8/8/8/8/8/8/q3K3 w - - 0 1", .white_in_check = true }, // queen on the rank
        .{ .f = "4k3/8/8/8/1b6/8/8/4K3 w - - 0 1", .white_in_check = true }, // bishop on the diagonal
    };

    for (cases) |c| {
        var b = try h.Board.init(c.f);
        defer b.deinit();
        try expectEqual(c.white_in_check, attacks.isInCheck(&b.gs.cur_position, .White));
    }
}

test "isInCheck is false when the king is absent" {
    var b = try h.Board.init("8/8/8/8/8/8/8/R6r w - - 0 1");
    defer b.deinit();
    try expect(!attacks.isInCheck(&b.gs.cur_position, .White));
}

test "isSquareAttackedBy honours a custom occupancy" {
    var b = try h.Board.init("k7/8/8/8/8/P7/8/R3K3 w - - 0 1");
    defer b.deinit();
    const p = &b.gs.cur_position;

    const occ = p.getOccupancy();
    try expect(!attacks.isSquareAttackedBy(p, h.sq("a8"), .White, occ));

    const without_pawn = occ & ~utils.getSquareBB(h.sq("a3"));
    try expect(attacks.isSquareAttackedBy(p, h.sq("a8"), .White, without_pawn));
}
