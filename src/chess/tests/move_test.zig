const std = @import("std");
const h = @import("harness.zig");
const pos = h.pos;
const utils = h.utils;
const Move = pos.Move;
const MoveList = h.MoveList;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Move fits in 16 bits" {
    try expectEqual(@as(usize, 16), @bitSizeOf(Move));
    try expectEqual(@as(usize, 2), @sizeOf(Move));
}

test "from and to survive a round trip through every square pair" {
    var from_i: usize = 0;
    while (from_i < 64) : (from_i += 1) {
        var to_i: usize = 0;
        while (to_i < 64) : (to_i += 1) {
            const m = Move.quiet(@intCast(from_i), @intCast(to_i));
            try expectEqual(@as(pos.Square, @intCast(from_i)), m.from);
            try expectEqual(@as(pos.Square, @intCast(to_i)), m.to);

            const raw: u16 = @bitCast(m);
            const back: Move = @bitCast(raw);
            try expect(m.eql(back));
        }
    }
}

test "quiet move classification" {
    const m = Move.quiet(h.sq("e2"), h.sq("e3"));
    try expect(m.isQuiet());
    try expect(!m.isCapture());
    try expect(!m.isPromo());
    try expect(!m.isCastle());
    try expect(!m.isEP());
    try expect(!m.isDoublePP());
}

test "double pawn push classification" {
    const m = Move.doublePush(h.sq("e2"), h.sq("e4"));
    try expect(m.isDoublePP());
    try expect(m.isQuiet());
    try expect(!m.isCapture());
    try expect(!m.isPromo());
    try expect(!m.isCastle());
    try expect(!m.isEP());
}

test "castling classification distinguishes the two sides" {
    const ks = Move.castle(h.sq("e1"), h.sq("g1"), true);
    const qs = Move.castle(h.sq("e1"), h.sq("c1"), false);

    try expect(ks.isCastle());
    try expect(qs.isCastle());
    try expect(ks.isKingsideCastle());
    try expect(!qs.isKingsideCastle());

    for ([_]Move{ ks, qs }) |m| {
        try expect(!m.isCapture());
        try expect(!m.isPromo());
        try expect(!m.isEP());
        try expect(!m.isDoublePP());
    }
}

test "capture classification" {
    const m = Move.capture(h.sq("e4"), h.sq("d5"));
    try expect(m.isCapture());
    try expect(!m.isEP());
    try expect(!m.isPromo());
    try expect(!m.isCastle());
    try expect(!m.isQuiet());
    try expect(!m.isDoublePP());
}

test "en passant classification" {
    const m = Move.enPassant(h.sq("e5"), h.sq("d6"));
    try expect(m.isEP());
    try expect(m.isCapture());
    try expect(!m.isPromo());
    try expect(!m.isCastle());
    try expect(!m.isDoublePP());
}

test "promotion classification and piece mapping" {
    const flags = [_]Move.PFlags{ .Knight, .Bishop, .Rook, .Queen };
    const pieces = [_]pos.Pieces{ .Knight, .Bishop, .Rook, .Queen };

    for (flags, pieces) |f, want| {
        const quiet_promo = Move.promotion(h.sq("a7"), h.sq("a8"), f);
        try expect(quiet_promo.isPromo());
        try expect(!quiet_promo.isCapture());
        try expect(!quiet_promo.isCastle());
        try expect(!quiet_promo.isEP());
        try expect(!quiet_promo.isDoublePP());
        try expectEqual(want, quiet_promo.promoPiece());

        const cap_promo = Move.promoCapture(h.sq("a7"), h.sq("b8"), f);
        try expect(cap_promo.isPromo());
        try expect(cap_promo.isCapture());
        try expect(!cap_promo.isCastle());
        try expect(!cap_promo.isEP());
        try expectEqual(want, cap_promo.promoPiece());
    }
}

test "promoPiece agrees with the flags-plus-one encoding makeMove relies on" {
    for ([_]Move.PFlags{ .Knight, .Bishop, .Rook, .Queen }) |f| {
        const m = Move.promotion(h.sq("a7"), h.sq("a8"), f);
        const from_raw: pos.Pieces = @enumFromInt(@as(u3, m.flags) + 1);
        try expectEqual(from_raw, m.promoPiece());
    }
}

test "no constructor is misclassified as another kind" {
    const all = [_]Move{
        Move.quiet(h.sq("e2"), h.sq("e3")),
        Move.doublePush(h.sq("e2"), h.sq("e4")),
        Move.castle(h.sq("e1"), h.sq("g1"), true),
        Move.castle(h.sq("e1"), h.sq("c1"), false),
        Move.capture(h.sq("e4"), h.sq("d5")),
        Move.enPassant(h.sq("e5"), h.sq("d6")),
        Move.promotion(h.sq("a7"), h.sq("a8"), .Queen),
        Move.promoCapture(h.sq("a7"), h.sq("b8"), .Knight),
    };

    for (all) |m| {
        var kinds: usize = 0;
        if (m.isCastle()) kinds += 1;
        if (m.isEP()) kinds += 1;
        if (m.isDoublePP()) kinds += 1;
        if (m.isPromo()) kinds += 1;
        try expect(kinds <= 1);

        try expectEqual(m.isQuiet(), !m.isCapture() and !m.isPromo());
    }
}

test "toUci formats plain and promotion moves" {
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("e2e4", Move.doublePush(h.sq("e2"), h.sq("e4")).toUci(&buf));
    try std.testing.expectEqualStrings("e1g1", Move.castle(h.sq("e1"), h.sq("g1"), true).toUci(&buf));
    try std.testing.expectEqualStrings("e5d6", Move.enPassant(h.sq("e5"), h.sq("d6")).toUci(&buf));
    try std.testing.expectEqualStrings("a7a8q", Move.promotion(h.sq("a7"), h.sq("a8"), .Queen).toUci(&buf));
    try std.testing.expectEqualStrings("a7a8n", Move.promotion(h.sq("a7"), h.sq("a8"), .Knight).toUci(&buf));
    try std.testing.expectEqualStrings("a7b8r", Move.promoCapture(h.sq("a7"), h.sq("b8"), .Rook).toUci(&buf));
    try std.testing.expectEqualStrings("a7b8b", Move.promoCapture(h.sq("a7"), h.sq("b8"), .Bishop).toUci(&buf));
}

test "eql compares the whole encoding" {
    const a = Move.quiet(h.sq("e2"), h.sq("e3"));
    try expect(a.eql(Move.quiet(h.sq("e2"), h.sq("e3"))));
    try expect(!a.eql(Move.quiet(h.sq("e2"), h.sq("e4"))));
    try expect(!a.eql(Move.capture(h.sq("e2"), h.sq("e3"))));
}

test "MoveList starts empty and accumulates" {
    var list = MoveList.empty;
    try expectEqual(@as(usize, 0), list.len);
    try expectEqual(@as(usize, 0), list.slice().len);

    list.add(Move.quiet(h.sq("e2"), h.sq("e3")));
    list.add(Move.doublePush(h.sq("d2"), h.sq("d4")));
    try expectEqual(@as(usize, 2), list.len);
    try expectEqual(@as(usize, 2), list.slice().len);

    list.clear();
    try expectEqual(@as(usize, 0), list.len);
}

test "MoveList holds the documented maximum" {
    var list = MoveList.empty;
    for (0..utils.max_moves) |i| {
        list.add(Move.quiet(@intCast(i % 64), @intCast((i + 1) % 64)));
    }
    try expectEqual(utils.max_moves, list.len);
    try expect(utils.max_moves >= 218); // the worst case reachable in chess
}

test "MoveList contains and findUci" {
    var list = MoveList.empty;
    const m = Move.doublePush(h.sq("e2"), h.sq("e4"));
    list.add(m);
    list.add(Move.promotion(h.sq("a7"), h.sq("a8"), .Queen));

    try expect(list.contains(m));
    try expect(!list.contains(Move.quiet(h.sq("e2"), h.sq("e4"))));

    try expect(list.findUci("e2e4") != null);
    try expect(list.findUci("a7a8q") != null);
    try expect(list.findUci("a7a8n") == null);
    try expect(list.findUci("h1h2") == null);
    try expect(list.findUci("e2e4").?.eql(m));
}

test "MoveList countTo" {
    var list = MoveList.empty;
    inline for (.{ Move.PFlags.Queen, .Rook, .Bishop, .Knight }) |f| {
        list.add(Move.promotion(h.sq("a7"), h.sq("a8"), f));
    }
    list.add(Move.quiet(h.sq("e2"), h.sq("e3")));

    try expectEqual(@as(usize, 4), list.countTo(h.sq("a8")));
    try expectEqual(@as(usize, 1), list.countTo(h.sq("e3")));
    try expectEqual(@as(usize, 0), list.countTo(h.sq("h8")));
}
