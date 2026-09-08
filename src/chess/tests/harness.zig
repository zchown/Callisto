const std = @import("std");
const root = @import("../root.zig");

pub const pos = root.pos;
pub const utils = root.utils;
pub const magic = root.magic;
pub const attacks = root.attacks;
pub const movegen = root.movegen;
pub const fen = root.fen;
pub const zobrist = root.zobrist;

pub const Move = pos.Move;
pub const MoveList = movegen.MoveList;
pub const Square = pos.Square;
pub const Bitboard = pos.Bitboard;

pub fn sq(name: []const u8) Square {
    return utils.squareFromString(name).?;
}

pub fn bb(names: []const []const u8) Bitboard {
    var out: Bitboard = 0;
    for (names) |n| out |= utils.getSquareBB(sq(n));
    return out;
}

pub const Board = struct {
    gs: pos.GameState,

    pub fn init(fen_str: []const u8) !Board {
        try attacks.init();
        return .{ .gs = try fen.parseFEN(fen_str) };
    }

    pub fn deinit(self: *Board) void {
        self.gs.deinit();
    }

    pub fn pseudoLegal(self: *Board) MoveList {
        var list = MoveList.empty;
        movegen.generateAll(&self.gs, &list);
        return list;
    }

    pub fn legal(self: *Board) !MoveList {
        var list = MoveList.empty;
        try movegen.generateLegal(&self.gs, &list);
        return list;
    }
};

pub fn hasUci(list: *const MoveList, uci: []const u8) bool {
    return list.findUci(uci) != null;
}

pub fn countFrom(list: *const MoveList, from: Square) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.from == from) n += 1;
    }
    return n;
}

pub fn countCaptures(list: *const MoveList) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.isCapture()) n += 1;
    }
    return n;
}

pub fn countPromotions(list: *const MoveList) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.isPromo()) n += 1;
    }
    return n;
}

pub fn countCastles(list: *const MoveList) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.isCastle()) n += 1;
    }
    return n;
}

pub fn countEnPassant(list: *const MoveList) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.isEP()) n += 1;
    }
    return n;
}

pub fn expectMoveCount(list: *const MoveList, expected: usize) !void {
    if (list.len != expected) {
        var buf: [5]u8 = undefined;
        std.debug.print("\nexpected {d} moves, got {d}:\n  ", .{ expected, list.len });
        for (list.slice()) |m| std.debug.print("{s} ", .{m.toUci(&buf)});
        std.debug.print("\n", .{});
    }
    try std.testing.expectEqual(expected, list.len);
}

pub fn expectHasUci(list: *const MoveList, uci: []const u8) !void {
    if (!hasUci(list, uci)) {
        var buf: [5]u8 = undefined;
        std.debug.print("\nexpected move {s} to be generated; got:\n  ", .{uci});
        for (list.slice()) |m| std.debug.print("{s} ", .{m.toUci(&buf)});
        std.debug.print("\n", .{});
        return error.MissingMove;
    }
}

pub fn expectNoUci(list: *const MoveList, uci: []const u8) !void {
    if (hasUci(list, uci)) {
        std.debug.print("\nmove {s} should not have been generated\n", .{uci});
        return error.UnexpectedMove;
    }
}
