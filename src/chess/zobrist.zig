const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;
const utils = root.utils;
const rng = utils.nextSplitMix64;

pub const ZobristKey = u64;

const num_piece_kinds = utils.num_pieces + 1;

const PieceRandoms = [utils.num_colors][num_piece_kinds][utils.num_squares]ZobristKey;
const CastleRandoms = [16]ZobristKey;
const ColorRandoms = [utils.num_colors]ZobristKey;
const EnPassantRandoms = [utils.num_squares]ZobristKey;

pub const zobrist = Zobs.init();

const Zobs = @This();

piece: PieceRandoms,
castle: CastleRandoms,
color: ColorRandoms,
en_passant: EnPassantRandoms,

fn init() Zobs {
    @setEvalBranchQuota(1_000_000);

    var keys: Zobs = Zobs{
        .piece = undefined,
        .castle = undefined,
        .color = undefined,
        .en_passant = undefined,
    };

    var rng_state: u64 = 0xdeadbeefdeadbeef;

    keys.color[0] = rng(&rng_state);
    keys.color[1] = rng(&rng_state);

    for (0..num_piece_kinds) |piece| {
        for (0..utils.num_squares) |sq| {
            keys.piece[0][piece][sq] = rng(&rng_state);
            keys.piece[1][piece][sq] = rng(&rng_state);
        }
    }

    for (0..16) |castle| {
        keys.castle[castle] = rng(&rng_state);
    }

    for (0..utils.num_squares) |sq| {
        keys.en_passant[sq] = rng(&rng_state);
    }

    return keys;
}

pub inline fn sideKeys(self: Zobs, side: pos.Color) ZobristKey {
    return self.color[@intFromEnum(side)];
}

pub inline fn enPassantKeys(self: Zobs, ep: ?pos.Square) ZobristKey {
    if (ep) |sq| {
        return self.en_passant[sq];
    } else return 0;
}

pub inline fn pieceKeys(self: Zobs, color: pos.Color, piece: pos.Pieces, sq: pos.Square) ZobristKey {
    return self.piece[@intFromEnum(color)][@intFromEnum(piece)][sq];
}

pub inline fn castleKeys(self: Zobs, castle: pos.CastleRights) ZobristKey {
    return self.castle[@as(usize, castle)];
}
