const std = @import("std");
const root = @import("root.zig");
const utils = root.utils;
const pos = root.pos;
const magic = root.magic;
const attacks = root.attacks;

const Move = pos.Move;
const Bitboard = pos.Bitboard;
const Square = pos.Square;
const Color = pos.Color;
const Pieces = pos.Pieces;
const Position = pos.Position;
const GameState = pos.GameState;

pub const MoveList = struct {
    moves: [utils.max_moves]Move = undefined,
    len: usize = 0,

    pub const empty: MoveList = .{};

    pub inline fn add(self: *MoveList, m: Move) void {
        std.debug.assert(self.len < utils.max_moves);
        self.moves[self.len] = m;
        self.len += 1;
    }

    pub inline fn clear(self: *MoveList) void {
        self.len = 0;
    }

    pub inline fn slice(self: *const MoveList) []const Move {
        return self.moves[0..self.len];
    }

    pub fn contains(self: *const MoveList, m: Move) bool {
        for (self.slice()) |x| {
            if (x.eql(m)) return true;
        }
        return false;
    }

    pub fn findUci(self: *const MoveList, uci: []const u8) ?Move {
        var buf: [5]u8 = undefined;
        for (self.slice()) |m| {
            if (std.mem.eql(u8, m.toUci(&buf), uci)) return m;
        }
        return null;
    }

    pub fn countTo(self: *const MoveList, sq: Square) usize {
        var n: usize = 0;
        for (self.slice()) |m| {
            if (m.to == sq) n += 1;
        }
        return n;
    }
};

pub fn generateAll(gs: *const GameState, list: *MoveList) void {
    list.clear();
    appendAll(gs, list);
}

pub fn appendAll(gs: *const GameState, list: *MoveList) void {
    std.debug.assert(attacks.isInitialized());
    switch (gs.to_move) {
        .White => generateFor(.White, gs, list),
        .Black => generateFor(.Black, gs, list),
    }
}

pub fn generateLegal(gs: *GameState, list: *MoveList) !void {
    var pseudo = MoveList.empty;
    generateAll(gs, &pseudo);

    list.clear();
    const us = gs.to_move;
    for (pseudo.slice()) |m| {
        try gs.makeMove(m);
        if (!attacks.isInCheck(&gs.cur_position, us)) list.add(m);
        gs.unmakeMove(m);
    }
}

fn generateFor(comptime us: Color, gs: *const GameState, list: *MoveList) void {
    const p = &gs.cur_position;
    const them = comptime us.oposite();

    const occ = p.getOccupancy();
    const enemy = p.getColorBoard(them);
    const targets = ~p.getColorBoard(us);

    generatePawnMoves(us, gs, list);

    var knights = p.getPieceColorBoard(.Knight, us);
    while (knights != 0) {
        const from = utils.popLsb(&knights);
        emit(list, from, attacks.knightAttacks(from) & targets, enemy);
    }

    generateSliders(.Bishop, us, p, list, targets, enemy, occ);
    generateSliders(.Rook, us, p, list, targets, enemy, occ);
    generateSliders(.Queen, us, p, list, targets, enemy, occ);

    var kings = p.getPieceColorBoard(.King, us);
    while (kings != 0) {
        const from = utils.popLsb(&kings);
        emit(list, from, attacks.kingAttacks(from) & targets, enemy);
    }

    generateCastles(us, gs, list);
}

inline fn emit(list: *MoveList, from: Square, dests: Bitboard, enemy: Bitboard) void {
    var caps = dests & enemy;
    while (caps != 0) {
        list.add(Move.capture(from, utils.popLsb(&caps)));
    }
    var quiets = dests & ~enemy;
    while (quiets != 0) {
        list.add(Move.quiet(from, utils.popLsb(&quiets)));
    }
}

inline fn generateSliders(
    comptime pt: Pieces,
    comptime us: Color,
    p: *const Position,
    list: *MoveList,
    targets: Bitboard,
    enemy: Bitboard,
    occ: Bitboard,
) void {
    var bb = p.getPieceColorBoard(pt, us);
    while (bb != 0) {
        const from = utils.popLsb(&bb);
        const a = switch (pt) {
            .Bishop => magic.getBishopAttacks(from, occ),
            .Rook => magic.getRookAttacks(from, occ),
            .Queen => magic.getQueenAttacks(from, occ),
            else => @compileError("generateSliders expects a sliding piece"),
        };
        emit(list, from, a & targets, enemy);
    }
}

inline fn shiftBack(to: Square, comptime delta: i16) Square {
    return @intCast(@as(i16, to) - delta);
}

inline fn emitPromotions(
    list: *MoveList,
    from: Square,
    to: Square,
    comptime is_capture: bool,
) void {
    inline for ([_]Move.PFlags{ .Queen, .Rook, .Bishop, .Knight }) |pf| {
        list.add(if (is_capture)
            Move.promoCapture(from, to, pf)
        else
            Move.promotion(from, to, pf));
    }
}

inline fn emitPawnCaptures(
    comptime delta: i16,
    comptime promo_rank: Bitboard,
    dests: Bitboard,
    list: *MoveList,
) void {
    var promos = dests & promo_rank;
    while (promos != 0) {
        const to = utils.popLsb(&promos);
        emitPromotions(list, shiftBack(to, delta), to, true);
    }
    var normal = dests & ~promo_rank;
    while (normal != 0) {
        const to = utils.popLsb(&normal);
        list.add(Move.capture(shiftBack(to, delta), to));
    }
}

fn generatePawnMoves(comptime us: Color, gs: *const GameState, list: *MoveList) void {
    const p = &gs.cur_position;
    const them = comptime us.oposite();

    const pawns = p.getPieceColorBoard(.Pawn, us);
    if (pawns == 0) return;

    const empty = ~p.getOccupancy();
    const enemy = p.getColorBoard(them);

    const promo_rank = comptime utils.promoRankBB(us);
    const dpp_rank = comptime utils.doublePushRankBB(us);

    const push_delta: i16 = comptime if (us == .White) 8 else -8;
    const cap_h_delta: i16 = comptime if (us == .White) 9 else -7; // toward the h-file
    const cap_a_delta: i16 = comptime if (us == .White) 7 else -9; // toward the a-file

    const toward_h = if (us == .White) utils.northEastOne(pawns) else utils.southEastOne(pawns);
    const toward_a = if (us == .White) utils.northWestOne(pawns) else utils.southWestOne(pawns);

    emitPawnCaptures(cap_h_delta, promo_rank, toward_h & enemy, list);
    emitPawnCaptures(cap_a_delta, promo_rank, toward_a & enemy, list);

    if (p.ep_sq) |ep| {
        var from_bb = attacks.pawnAttacks(them, ep) & pawns;
        while (from_bb != 0) {
            list.add(Move.enPassant(utils.popLsb(&from_bb), ep));
        }
    }

    const single = utils.forwardOne(us, pawns) & empty;

    var promos = single & promo_rank;
    while (promos != 0) {
        const to = utils.popLsb(&promos);
        emitPromotions(list, shiftBack(to, push_delta), to, false);
    }

    var doubles = utils.forwardOne(us, single & dpp_rank) & empty;
    while (doubles != 0) {
        const to = utils.popLsb(&doubles);
        list.add(Move.doublePush(shiftBack(to, push_delta * 2), to));
    }

    var quiets = single & ~promo_rank;
    while (quiets != 0) {
        const to = utils.popLsb(&quiets);
        list.add(Move.quiet(shiftBack(to, push_delta), to));
    }
}

inline fn spanInclusive(a: Square, b: Square) Bitboard {
    std.debug.assert(utils.rankOf(a) == utils.rankOf(b));
    const lo = @min(a, b);
    const hi = @max(a, b);
    const n: u6 = @intCast(@as(u7, hi - lo) + 1);
    return ((@as(Bitboard, 1) << n) - 1) << lo;
}

fn generateCastles(comptime us: Color, gs: *const GameState, list: *MoveList) void {
    const p = &gs.cur_position;
    const them = comptime us.oposite();

    const ks: pos.CastleValues = comptime if (us == .White) .WhiteKingside else .BlackKingside;
    const qs: pos.CastleValues = comptime if (us == .White) .WhiteQueenside else .BlackQueenside;

    const can_ks = pos.hasCastleRight(p.castle, ks);
    const can_qs = pos.hasCastleRight(p.castle, qs);
    if (!can_ks and !can_qs) return;

    const king_bb = p.getPieceColorBoard(.King, us);
    if (king_bb == 0) return;
    const king_sq = utils.lsb(king_bb);

    if (attacks.isSquareAttackedBy(p, king_sq, them, p.getOccupancy())) return;

    if (can_ks) tryCastle(us, gs, list, king_sq, true);
    if (can_qs) tryCastle(us, gs, list, king_sq, false);
}

fn tryCastle(
    comptime us: Color,
    gs: *const GameState,
    list: *MoveList,
    king_sq: Square,
    kingside: bool,
) void {
    const p = &gs.cur_position;
    const them = comptime us.oposite();

    const rook_from = gs.rookSquare(us, kingside);
    const rook_pc = p.getFromSquare(rook_from);
    if (rook_pc.piece != .Rook or rook_pc.color != us) return;

    const king_to = GameState.kingCastleDest(us, kingside);
    const rook_to = GameState.rookCastleDest(us, kingside);

    const vacated = utils.getSquareBB(king_sq) | utils.getSquareBB(rook_from);
    const occ = p.getOccupancy() & ~vacated;

    const king_path = spanInclusive(king_sq, king_to);
    const rook_path = spanInclusive(rook_from, rook_to);
    if ((occ & (king_path | rook_path)) != 0) return;

    var walk = king_path;
    while (walk != 0) {
        const s = utils.popLsb(&walk);
        if (attacks.isSquareAttackedBy(p, s, them, occ)) return;
    }

    list.add(Move.castle(king_sq, king_to, kingside));
}
