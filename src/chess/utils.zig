const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;

pub const start_position = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub const kb = 1 << 10;
pub const mb = 1 << 20;

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;

pub const max_moves = 1024;

// zig fmt: off
pub const Squares = enum(u6) {
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,

    pub inline fn sq(self: Squares) pos.Square {
        return @intFromEnum(self);
    }

    pub inline fn bb(self: Squares) pos.Bitboard {
        return getSquareBB(@intFromEnum(self));
    }
};
// zig fmt: on

pub inline fn fileOf(sq: pos.Square) u3 {
    return @truncate(sq);
}

pub inline fn rankOf(sq: pos.Square) u3 {
    return @intCast(sq >> 3);
}

pub inline fn relativeRank(c: pos.Color, sq: pos.Square) u3 {
    const r = rankOf(sq);
    return if (c == .White) r else 7 - r;
}

pub fn squareFromString(s: []const u8) ?pos.Square {
    if (s.len != 2) return null;
    if (s[0] < 'a' or s[0] > 'h') return null;
    if (s[1] < '1' or s[1] > '8') return null;
    return pos.squareFromFileRank(@intCast(s[0] - 'a'), @intCast(s[1] - '1'));
}

pub fn squareToString(sq: pos.Square, buf: []u8) []const u8 {
    buf[0] = 'a' + @as(u8, fileOf(sq));
    buf[1] = '1' + @as(u8, rankOf(sq));
    return buf[0..2];
}

pub const empty_bb: pos.Bitboard = 0;
pub const full_bb: pos.Bitboard = 0xFFFFFFFFFFFFFFFF;

pub inline fn getSquareBB(sq: pos.Square) pos.Bitboard {
    return @as(pos.Bitboard, 1) << sq;
}

pub inline fn getBit(bb: pos.Bitboard, sq: pos.Square) bool {
    return (bb & getSquareBB(sq)) != 0;
}

pub inline fn setBit(bb: pos.Bitboard, sq: pos.Square) pos.Bitboard {
    return bb | getSquareBB(sq);
}

pub inline fn clearBit(bb: pos.Bitboard, sq: pos.Square) pos.Bitboard {
    return bb & ~getSquareBB(sq);
}

pub inline fn popBit(bb: *pos.Bitboard, sq: pos.Square) void {
    bb.* &= ~getSquareBB(sq);
}

pub inline fn countBits(bb: pos.Bitboard) u7 {
    return @popCount(bb);
}

pub inline fn lsb(bb: pos.Bitboard) pos.Square {
    return @intCast(@ctz(bb));
}

pub inline fn msb(bb: pos.Bitboard) pos.Square {
    return @intCast(63 - @clz(bb));
}

pub inline fn popLsb(bb: *pos.Bitboard) pos.Square {
    const sq = lsb(bb.*);
    bb.* &= bb.* - 1;
    return sq;
}

pub inline fn moreThanOne(bb: pos.Bitboard) bool {
    return (bb & (bb -% 1)) != 0;
}

pub const file_a: pos.Bitboard = 0x0101010101010101;
pub const file_b: pos.Bitboard = file_a << 1;
pub const file_g: pos.Bitboard = file_a << 6;
pub const file_h: pos.Bitboard = file_a << 7;

pub const rank_1: pos.Bitboard = 0x00000000000000FF;
pub const rank_2: pos.Bitboard = rank_1 << (8 * 1);
pub const rank_3: pos.Bitboard = rank_1 << (8 * 2);
pub const rank_4: pos.Bitboard = rank_1 << (8 * 3);
pub const rank_5: pos.Bitboard = rank_1 << (8 * 4);
pub const rank_6: pos.Bitboard = rank_1 << (8 * 5);
pub const rank_7: pos.Bitboard = rank_1 << (8 * 6);
pub const rank_8: pos.Bitboard = rank_1 << (8 * 7);

pub const not_a_file: pos.Bitboard = ~file_a;
pub const not_h_file: pos.Bitboard = ~file_h;
pub const not_ab_file: pos.Bitboard = ~(file_a | file_b);
pub const not_hg_file: pos.Bitboard = ~(file_h | file_g);
pub const not_first_rank: pos.Bitboard = ~rank_1;
pub const not_eighth_rank: pos.Bitboard = ~rank_8;
pub const dark_squares: pos.Bitboard = 0xaa55aa55aa55aa55;
pub const light_squares: pos.Bitboard = ~dark_squares;

pub inline fn fileBB(f: u3) pos.Bitboard {
    return file_a << f;
}

pub inline fn rankBB(r: u3) pos.Bitboard {
    return rank_1 << (@as(u6, r) * 8);
}

pub inline fn backRankBB(c: pos.Color) pos.Bitboard {
    return if (c == .White) rank_1 else rank_8;
}

pub inline fn promoRankBB(c: pos.Color) pos.Bitboard {
    return if (c == .White) rank_8 else rank_1;
}

pub inline fn doublePushRankBB(c: pos.Color) pos.Bitboard {
    return if (c == .White) rank_3 else rank_6;
}

pub inline fn northOne(bb: pos.Bitboard) pos.Bitboard {
    return bb << 8;
}

pub inline fn southOne(bb: pos.Bitboard) pos.Bitboard {
    return bb >> 8;
}

pub inline fn northEastOne(bb: pos.Bitboard) pos.Bitboard {
    return (bb & not_h_file) << 9;
}

pub inline fn northWestOne(bb: pos.Bitboard) pos.Bitboard {
    return (bb & not_a_file) << 7;
}

pub inline fn southEastOne(bb: pos.Bitboard) pos.Bitboard {
    return (bb & not_h_file) >> 7;
}

pub inline fn southWestOne(bb: pos.Bitboard) pos.Bitboard {
    return (bb & not_a_file) >> 9;
}

pub inline fn forwardOne(comptime c: pos.Color, bb: pos.Bitboard) pos.Bitboard {
    return if (c == .White) northOne(bb) else southOne(bb);
}

pub fn nextSplitMix64(state: *u64) u64 {
    state.* +%= 0x9e3779b97f4a7c15;
    var z = state.*;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

pub fn formatBitboard(bb: pos.Bitboard, buf: []u8) []const u8 {
    var len: usize = 0;
    var rank_idx: usize = 8;
    while (rank_idx > 0) {
        rank_idx -= 1;
        buf[len] = '1' + @as(u8, @intCast(rank_idx));
        buf[len + 1] = ' ';
        len += 2;
        for (0..8) |file| {
            const sq: pos.Square = @intCast(rank_idx * 8 + file);
            buf[len] = if (getBit(bb, sq)) 'X' else '.';
            buf[len + 1] = ' ';
            len += 2;
        }
        buf[len] = '\n';
        len += 1;
    }
    const footer = "  a b c d e f g h\n";
    @memcpy(buf[len .. len + footer.len], footer);
    len += footer.len;
    return buf[0..len];
}

pub fn debugBitboard(bb: pos.Bitboard) void {
    var buf: [256]u8 = undefined;
    std.debug.print("{s}\n", .{formatBitboard(bb, &buf)});
}
