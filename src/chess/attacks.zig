const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;
const utils = root.utils;
const magic = root.magic;

const Bitboard = pos.Bitboard;
const Square = pos.Square;
const Color = pos.Color;
const Pieces = pos.Pieces;
const Position = pos.Position;

pub const pawn_attacks: [utils.num_colors][utils.num_squares]Bitboard = blk: {
    var t: [utils.num_colors][utils.num_squares]Bitboard = undefined;
    for (0..utils.num_squares) |i| {
        const b = utils.getSquareBB(@intCast(i));
        t[0][i] = utils.northEastOne(b) | utils.northWestOne(b);
        t[1][i] = utils.southEastOne(b) | utils.southWestOne(b);
    }
    break :blk t;
};

pub const knight_attacks: [utils.num_squares]Bitboard = blk: {
    var t: [utils.num_squares]Bitboard = undefined;
    for (0..utils.num_squares) |i| {
        const b = utils.getSquareBB(@intCast(i));
        t[i] = ((b & utils.not_h_file) << 17) |
            ((b & utils.not_a_file) << 15) |
            ((b & utils.not_hg_file) << 10) |
            ((b & utils.not_ab_file) << 6) |
            ((b & utils.not_a_file) >> 17) |
            ((b & utils.not_h_file) >> 15) |
            ((b & utils.not_ab_file) >> 10) |
            ((b & utils.not_hg_file) >> 6);
    }
    break :blk t;
};

pub const king_attacks: [utils.num_squares]Bitboard = blk: {
    var t: [utils.num_squares]Bitboard = undefined;
    for (0..utils.num_squares) |i| {
        const b = utils.getSquareBB(@intCast(i));
        t[i] = utils.northOne(b) | utils.southOne(b) |
            ((b & utils.not_h_file) << 1) | ((b & utils.not_a_file) >> 1) |
            utils.northEastOne(b) | utils.northWestOne(b) |
            utils.southEastOne(b) | utils.southWestOne(b);
    }
    break :blk t;
};

pub inline fn pawnAttacks(c: Color, sq: Square) Bitboard {
    return pawn_attacks[c.idx()][sq];
}

pub inline fn knightAttacks(sq: Square) Bitboard {
    return knight_attacks[sq];
}

pub inline fn kingAttacks(sq: Square) Bitboard {
    return king_attacks[sq];
}

pub inline fn pawnAttacksBB(comptime c: Color, pawns: Bitboard) Bitboard {
    return if (c == .White)
        utils.northEastOne(pawns) | utils.northWestOne(pawns)
    else
        utils.southEastOne(pawns) | utils.southWestOne(pawns);
}

var ready: bool = false;

pub fn init() !void {
    try magic.init();
    ready = true;
}

pub inline fn isInitialized() bool {
    return ready;
}

pub inline fn attacksFrom(p: Pieces, c: Color, sq: Square, occupancy: Bitboard) Bitboard {
    return switch (p) {
        .Pawn => pawnAttacks(c, sq),
        .Knight => knightAttacks(sq),
        .Bishop => magic.getBishopAttacks(sq, occupancy),
        .Rook => magic.getRookAttacks(sq, occupancy),
        .Queen => magic.getQueenAttacks(sq, occupancy),
        .King => kingAttacks(sq),
        .None => 0,
    };
}

pub fn attackersTo(p: *const Position, sq: Square, occupancy: Bitboard) Bitboard {
    return (pawnAttacks(.Black, sq) & p.getPieceColorBoard(.Pawn, .White)) |
        (pawnAttacks(.White, sq) & p.getPieceColorBoard(.Pawn, .Black)) |
        (knightAttacks(sq) & p.getPieceBoard(.Knight)) |
        (kingAttacks(sq) & p.getPieceBoard(.King)) |
        (magic.getBishopAttacks(sq, occupancy) &
            (p.getPieceBoard(.Bishop) | p.getPieceBoard(.Queen))) |
        (magic.getRookAttacks(sq, occupancy) &
            (p.getPieceBoard(.Rook) | p.getPieceBoard(.Queen)));
}

pub fn attackersToBy(p: *const Position, sq: Square, by: Color, occupancy: Bitboard) Bitboard {
    return attackersTo(p, sq, occupancy) & p.getColorBoard(by);
}

pub fn isSquareAttackedBy(p: *const Position, sq: Square, by: Color, occupancy: Bitboard) bool {
    if ((pawnAttacks(by.oposite(), sq) & p.getPieceColorBoard(.Pawn, by)) != 0) return true;
    if ((knightAttacks(sq) & p.getPieceColorBoard(.Knight, by)) != 0) return true;
    if ((kingAttacks(sq) & p.getPieceColorBoard(.King, by)) != 0) return true;
    if ((magic.getBishopAttacks(sq, occupancy) & p.diagonalSliders(by)) != 0) return true;
    if ((magic.getRookAttacks(sq, occupancy) & p.straightSliders(by)) != 0) return true;
    return false;
}

pub fn isSquareAttacked(p: *const Position, sq: Square, by: Color) bool {
    return isSquareAttackedBy(p, sq, by, p.getOccupancy());
}

pub fn isInCheck(p: *const Position, c: Color) bool {
    const king_bb = p.getPieceColorBoard(.King, c);
    if (king_bb == 0) return false;
    return isSquareAttackedBy(p, utils.lsb(king_bb), c.oposite(), p.getOccupancy());
}
