const std = @import("std");
const h = @import("harness.zig");
const magic = h.magic;
const utils = h.utils;
const pos = h.pos;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "rook mask excludes the board edge and the origin square" {
    const mask = magic.maskRookAttacks(h.sq("d4"));
    try expect(!utils.getBit(mask, h.sq("d4")));
    try expect(!utils.getBit(mask, h.sq("d1")));
    try expect(!utils.getBit(mask, h.sq("d8")));
    try expect(!utils.getBit(mask, h.sq("a4")));
    try expect(!utils.getBit(mask, h.sq("h4")));

    try expect(utils.getBit(mask, h.sq("d2")));
    try expect(utils.getBit(mask, h.sq("d7")));
    try expect(utils.getBit(mask, h.sq("b4")));
    try expect(utils.getBit(mask, h.sq("g4")));

    try expectEqual(@as(u7, 10), utils.countBits(mask));
}

test "bishop mask excludes the board edge" {
    const mask = magic.maskBishopAttacks(h.sq("d4"));
    try expect(!utils.getBit(mask, h.sq("a1")));
    try expect(!utils.getBit(mask, h.sq("a7")));
    try expect(!utils.getBit(mask, h.sq("g1")));
    try expect(!utils.getBit(mask, h.sq("h8")));

    try expect(utils.getBit(mask, h.sq("c3")));
    try expect(utils.getBit(mask, h.sq("e5")));
    try expect(utils.getBit(mask, h.sq("g7")));

    try expectEqual(@as(u7, 9), utils.countBits(mask));
}

test "relevant bit counts match the published magic bitboard values" {
    try expectEqual(@as(u7, 12), magic.rook_relevant_bits[h.sq("a1")]);
    try expectEqual(@as(u7, 12), magic.rook_relevant_bits[h.sq("h8")]);
    try expectEqual(@as(u7, 10), magic.rook_relevant_bits[h.sq("d4")]);

    try expectEqual(@as(u7, 6), magic.bishop_relevant_bits[h.sq("a1")]);
    try expectEqual(@as(u7, 9), magic.bishop_relevant_bits[h.sq("d4")]);
    try expectEqual(@as(u7, 5), magic.bishop_relevant_bits[h.sq("a2")]);

    for (0..64) |i| {
        try expectEqual(magic.rook_relevant_bits[i], utils.countBits(magic.rook_masks[i]));
        try expectEqual(magic.bishop_relevant_bits[i], utils.countBits(magic.bishop_masks[i]));
    }
}

test "table sizes are the standard fancy-magic totals" {
    try expectEqual(@as(usize, 102400), magic.rook_table_size);
    try expectEqual(@as(usize, 5248), magic.bishop_table_size);
}

test "setOccupancy enumerates every subset of the mask exactly once" {
    const mask = magic.maskBishopAttacks(h.sq("a1")); // 6 relevant bits
    const bits = utils.countBits(mask);
    const count = @as(usize, 1) << @intCast(bits);

    var seen = std.AutoHashMap(pos.Bitboard, void).init(std.testing.allocator);
    defer seen.deinit();

    for (0..count) |i| {
        const occ = magic.setOccupancy(i, bits, mask);
        try expectEqual(occ, occ & mask); // always a subset
        try expect(!seen.contains(occ)); // never repeated
        try seen.put(occ, {});
    }
    try expectEqual(count, seen.count());
}

test "setOccupancy index 0 is empty and all-ones is the whole mask" {
    const mask = magic.maskRookAttacks(h.sq("d4"));
    const bits = utils.countBits(mask);
    try expectEqual(@as(pos.Bitboard, 0), magic.setOccupancy(0, bits, mask));

    const all = (@as(usize, 1) << @intCast(bits)) - 1;
    try expectEqual(mask, magic.setOccupancy(all, bits, mask));
}

test "rook reference attacks stop on the first blocker but include it" {
    const blockers = h.bb(&.{ "d6", "b4" });
    const a = magic.rookAttacks(h.sq("d4"), blockers);

    try expect(utils.getBit(a, h.sq("d5")));
    try expect(utils.getBit(a, h.sq("d6"))); // the blocker itself is attackable
    try expect(!utils.getBit(a, h.sq("d7"))); // but nothing behind it

    try expect(utils.getBit(a, h.sq("c4")));
    try expect(utils.getBit(a, h.sq("b4")));
    try expect(!utils.getBit(a, h.sq("a4")));

    // Unobstructed rays run all the way to the edge.
    try expect(utils.getBit(a, h.sq("d1")));
    try expect(utils.getBit(a, h.sq("h4")));
}

test "bishop reference attacks stop on the first blocker but include it" {
    const blockers = h.bb(&.{"f6"});
    const a = magic.bishopAttacks(h.sq("d4"), blockers);

    try expect(utils.getBit(a, h.sq("e5")));
    try expect(utils.getBit(a, h.sq("f6")));
    try expect(!utils.getBit(a, h.sq("g7")));
    try expect(!utils.getBit(a, h.sq("h8")));

    try expect(utils.getBit(a, h.sq("a1")));
    try expect(utils.getBit(a, h.sq("a7")));
    try expect(utils.getBit(a, h.sq("g1")));
}

test "corner rook on an empty board attacks 14 squares" {
    try expectEqual(@as(u7, 14), utils.countBits(magic.rookAttacks(h.sq("a1"), 0)));
    try expectEqual(@as(u7, 14), utils.countBits(magic.rookAttacks(h.sq("d4"), 0)));
}

test "bishop on an empty board attacks the expected counts" {
    try expectEqual(@as(u7, 7), utils.countBits(magic.bishopAttacks(h.sq("a1"), 0)));
    try expectEqual(@as(u7, 13), utils.countBits(magic.bishopAttacks(h.sq("d4"), 0)));
}

test "magic tables build without a destructive collision" {
    try magic.init();
}

test "rook lookups match the reference for all relevant occupancies" {
    try h.attacks.init();

    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const mask = magic.rook_masks[i];
        const bits = magic.rook_relevant_bits[i];
        const count = @as(usize, 1) << @intCast(bits);

        for (0..count) |j| {
            const occ = magic.setOccupancy(j, bits, mask);
            try expectEqual(magic.rookAttacks(s, occ), magic.getRookAttacks(s, occ));
        }
    }
}

test "bishop lookups match the reference for all relevant occupancies" {
    try h.attacks.init();

    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const mask = magic.bishop_masks[i];
        const bits = magic.bishop_relevant_bits[i];
        const count = @as(usize, 1) << @intCast(bits);

        for (0..count) |j| {
            const occ = magic.setOccupancy(j, bits, mask);
            try expectEqual(magic.bishopAttacks(s, occ), magic.getBishopAttacks(s, occ));
        }
    }
}

test "magic lookups ignore occupancy outside the relevant mask" {
    try h.attacks.init();

    var state: u64 = 0xfeedfacecafebeef;
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        for (0..64) |_| {
            const noise = utils.nextSplitMix64(&state);
            const relevant = noise & magic.rook_masks[i];
            // Adding blockers on the edge must not change the answer.
            try expectEqual(
                magic.getRookAttacks(s, relevant),
                magic.getRookAttacks(s, noise),
            );
        }
    }
}

test "queen attacks are the union of rook and bishop attacks" {
    try h.attacks.init();

    var state: u64 = 0x0badc0de0badc0de;
    for (0..64) |i| {
        const s: pos.Square = @intCast(i);
        const occ = utils.nextSplitMix64(&state);
        try expectEqual(
            magic.getRookAttacks(s, occ) | magic.getBishopAttacks(s, occ),
            magic.getQueenAttacks(s, occ),
        );
    }
}

test "sliding attacks are symmetric" {
    try h.attacks.init();

    // If a rook on x attacks y through some occupancy, a rook on y attacks x
    // through the same occupancy.
    var state: u64 = 0x5eed5eed5eed5eed;
    for (0..200) |_| {
        const occ = utils.nextSplitMix64(&state) & utils.nextSplitMix64(&state);
        const a: pos.Square = @intCast(utils.nextSplitMix64(&state) % 64);
        const b: pos.Square = @intCast(utils.nextSplitMix64(&state) % 64);
        if (a == b) continue;

        const a_hits_b = utils.getBit(magic.getRookAttacks(a, occ), b);
        const b_hits_a = utils.getBit(magic.getRookAttacks(b, occ), a);
        try expectEqual(a_hits_b, b_hits_a);
    }
}
