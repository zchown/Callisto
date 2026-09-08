const std = @import("std");
const h = @import("harness.zig");
const utils = h.utils;
const pos = h.pos;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "squareFromFileRank matches the Squares enum" {
    try expectEqual(@as(pos.Square, 0), pos.squareFromFileRank(0, 0));
    try expectEqual(utils.Squares.a1.sq(), pos.squareFromFileRank(0, 0));
    try expectEqual(utils.Squares.h1.sq(), pos.squareFromFileRank(7, 0));
    try expectEqual(utils.Squares.a8.sq(), pos.squareFromFileRank(0, 7));
    try expectEqual(utils.Squares.h8.sq(), pos.squareFromFileRank(7, 7));
    try expectEqual(utils.Squares.e4.sq(), pos.squareFromFileRank(4, 3));
}

test "squareFromFileRank covers every square exactly once" {
    var seen = [_]bool{false} ** 64;
    for (0..8) |f| {
        for (0..8) |r| {
            const s = pos.squareFromFileRank(@intCast(f), @intCast(r));
            try expect(!seen[s]);
            seen[s] = true;
        }
    }
    for (seen) |x| try expect(x);
}

test "fileOf and rankOf invert squareFromFileRank" {
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        try expectEqual(s, pos.squareFromFileRank(utils.fileOf(s), utils.rankOf(s)));
    }
}

test "relativeRank flips for black" {
    try expectEqual(@as(u3, 0), utils.relativeRank(.White, h.sq("a1")));
    try expectEqual(@as(u3, 7), utils.relativeRank(.White, h.sq("a8")));
    try expectEqual(@as(u3, 0), utils.relativeRank(.Black, h.sq("a8")));
    try expectEqual(@as(u3, 7), utils.relativeRank(.Black, h.sq("a1")));
    try expectEqual(@as(u3, 1), utils.relativeRank(.Black, h.sq("h7")));
}

test "square string round trip" {
    var buf: [2]u8 = undefined;
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const text = utils.squareToString(s, &buf);
        try expectEqual(s, utils.squareFromString(text).?);
    }
    try expectEqual(h.sq("e4"), utils.squareFromString("e4").?);
    try expect(utils.squareFromString("e9") == null);
    try expect(utils.squareFromString("i1") == null);
    try expect(utils.squareFromString("e") == null);
    try expect(utils.squareFromString("e44") == null);
}

test "getSquareBB sets exactly one bit" {
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const b = utils.getSquareBB(s);
        try expectEqual(@as(u7, 1), utils.countBits(b));
        try expectEqual(s, utils.lsb(b));
        try expectEqual(s, utils.msb(b));
    }
}

test "getBit, setBit, clearBit and popBit agree" {
    var b: pos.Bitboard = 0;
    const s = h.sq("d5");

    try expect(!utils.getBit(b, s));
    b = utils.setBit(b, s);
    try expect(utils.getBit(b, s));
    try expectEqual(@as(u7, 1), utils.countBits(b));

    b = utils.setBit(b, s);
    try expectEqual(@as(u7, 1), utils.countBits(b));

    try expectEqual(@as(pos.Bitboard, 0), utils.clearBit(b, s));

    utils.popBit(&b, s);
    try expect(!utils.getBit(b, s));

    utils.popBit(&b, s);
    try expectEqual(@as(pos.Bitboard, 0), b);
}

test "countBits" {
    try expectEqual(@as(u7, 0), utils.countBits(0));
    try expectEqual(@as(u7, 64), utils.countBits(utils.full_bb));
    try expectEqual(@as(u7, 8), utils.countBits(utils.rank_1));
    try expectEqual(@as(u7, 8), utils.countBits(utils.file_a));
    try expectEqual(@as(u7, 32), utils.countBits(utils.dark_squares));
}

test "lsb and msb pick the right ends" {
    const b = h.bb(&.{ "c3", "a1", "h8" });
    try expectEqual(h.sq("a1"), utils.lsb(b));
    try expectEqual(h.sq("h8"), utils.msb(b));
}

test "popLsb drains a bitboard in ascending order" {
    var b = h.bb(&.{ "h8", "a1", "e4", "b2" });
    const want = [_]pos.Square{ h.sq("a1"), h.sq("b2"), h.sq("e4"), h.sq("h8") };

    for (want) |w| {
        try expectEqual(@as(usize, 1), @as(usize, 1));
        try expectEqual(w, utils.popLsb(&b));
    }
    try expectEqual(@as(pos.Bitboard, 0), b);
}

test "moreThanOne" {
    try expect(!utils.moreThanOne(0));
    try expect(!utils.moreThanOne(utils.getSquareBB(h.sq("d4"))));
    try expect(utils.moreThanOne(h.bb(&.{ "d4", "e5" })));
    try expect(utils.moreThanOne(utils.full_bb));
}

test "file and rank masks" {
    try expectEqual(utils.file_a, utils.fileBB(0));
    try expectEqual(utils.file_h, utils.fileBB(7));
    try expectEqual(utils.rank_1, utils.rankBB(0));
    try expectEqual(utils.rank_8, utils.rankBB(7));

    try expect(utils.getBit(utils.file_a, h.sq("a5")));
    try expect(!utils.getBit(utils.file_a, h.sq("b5")));
    try expect(utils.getBit(utils.rank_4, h.sq("e4")));
    try expect(!utils.getBit(utils.rank_4, h.sq("e5")));
}

test "files and ranks partition the board" {
    var files: pos.Bitboard = 0;
    var ranks: pos.Bitboard = 0;
    for (0..8) |i| {
        files |= utils.fileBB(@intCast(i));
        ranks |= utils.rankBB(@intCast(i));
    }
    try expectEqual(utils.full_bb, files);
    try expectEqual(utils.full_bb, ranks);
    try expectEqual(utils.full_bb, utils.dark_squares | utils.light_squares);
    try expectEqual(@as(pos.Bitboard, 0), utils.dark_squares & utils.light_squares);
}

test "negated file masks" {
    try expectEqual(~utils.file_a, utils.not_a_file);
    try expectEqual(~utils.file_h, utils.not_h_file);
    try expect(!utils.getBit(utils.not_ab_file, h.sq("b4")));
    try expect(utils.getBit(utils.not_ab_file, h.sq("c4")));
    try expect(!utils.getBit(utils.not_hg_file, h.sq("g4")));
    try expect(utils.getBit(utils.not_hg_file, h.sq("f4")));
}

test "colour-relative rank masks" {
    try expectEqual(utils.rank_1, utils.backRankBB(.White));
    try expectEqual(utils.rank_8, utils.backRankBB(.Black));
    try expectEqual(utils.rank_8, utils.promoRankBB(.White));
    try expectEqual(utils.rank_1, utils.promoRankBB(.Black));
    try expectEqual(utils.rank_3, utils.doublePushRankBB(.White));
    try expectEqual(utils.rank_6, utils.doublePushRankBB(.Black));
}

test "north and south shifts fall off the board" {
    try expectEqual(h.bb(&.{"e5"}), utils.northOne(h.bb(&.{"e4"})));
    try expectEqual(h.bb(&.{"e3"}), utils.southOne(h.bb(&.{"e4"})));
    try expectEqual(@as(pos.Bitboard, 0), utils.northOne(utils.rank_8));
    try expectEqual(@as(pos.Bitboard, 0), utils.southOne(utils.rank_1));
}

test "diagonal shifts do not wrap around the edges" {
    try expectEqual(h.bb(&.{"f5"}), utils.northEastOne(h.bb(&.{"e4"})));
    try expectEqual(h.bb(&.{"d5"}), utils.northWestOne(h.bb(&.{"e4"})));
    try expectEqual(h.bb(&.{"f3"}), utils.southEastOne(h.bb(&.{"e4"})));
    try expectEqual(h.bb(&.{"d3"}), utils.southWestOne(h.bb(&.{"e4"})));

    try expectEqual(@as(pos.Bitboard, 0), utils.northEastOne(h.bb(&.{"h4"})));
    try expectEqual(@as(pos.Bitboard, 0), utils.southEastOne(h.bb(&.{"h4"})));
    try expectEqual(@as(pos.Bitboard, 0), utils.northWestOne(h.bb(&.{"a4"})));
    try expectEqual(@as(pos.Bitboard, 0), utils.southWestOne(h.bb(&.{"a4"})));

    try expectEqual(@as(u7, 7), utils.countBits(utils.northEastOne(utils.file_a)));
    try expectEqual(@as(u7, 0), utils.countBits(utils.northEastOne(utils.file_h)));
}

test "forwardOne follows the side to move" {
    try expectEqual(h.bb(&.{"e5"}), utils.forwardOne(.White, h.bb(&.{"e4"})));
    try expectEqual(h.bb(&.{"e3"}), utils.forwardOne(.Black, h.bb(&.{"e4"})));
}

test "splitmix64 does not immediately repeat" {
    var state: u64 = 0x1234567890abcdef;
    var seen: [64]u64 = undefined;
    for (&seen) |*s| s.* = utils.nextSplitMix64(&state);

    for (seen, 0..) |a, i| {
        for (seen[i + 1 ..]) |b| try expect(a != b);
    }
}

test "formatBitboard puts a1 at the bottom left" {
    var buf: [256]u8 = undefined;
    const text = utils.formatBitboard(h.bb(&.{"a1"}), &buf);
    var it = std.mem.splitScalar(u8, text, '\n');
    var last_row: []const u8 = "";
    while (it.next()) |line| {
        if (line.len > 0 and line[0] == '1') last_row = line;
    }
    try std.testing.expectEqualStrings("1 X . . . . . . . ", last_row);
}
