const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;
const utils = root.utils;
const movegen = root.movegen;
const attacks = root.attacks;

const Move = pos.Move;
const GameState = pos.GameState;
const MoveList = movegen.MoveList;

pub const max_len = 12;

const Sink = struct {
    buf: []u8,
    len: usize = 0,

    fn byte(self: *Sink, c: u8) void {
        if (self.len < self.buf.len) {
            self.buf[self.len] = c;
            self.len += 1;
        }
    }

    fn str(self: *Sink, s: []const u8) void {
        for (s) |c| self.byte(c);
    }

    fn square(self: *Sink, sq: pos.Square) void {
        self.byte('a' + @as(u8, utils.fileOf(sq)));
        self.byte('1' + @as(u8, utils.rankOf(sq)));
    }

    fn print(self: *Sink, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(self.buf[self.len..], fmt, args) catch return;
        self.len += w.len;
    }

    fn done(self: *Sink) []const u8 {
        return self.buf[0..self.len];
    }
};

pub fn pieceLetter(p: pos.Pieces) u8 {
    return switch (p) {
        .Pawn => 'P',
        .Knight => 'N',
        .Bishop => 'B',
        .Rook => 'R',
        .Queen => 'Q',
        .King => 'K',
        .None => '?',
    };
}

pub fn toSan(gs: *GameState, m: Move, buf: []u8) ![]const u8 {
    var s = Sink{ .buf = buf };
    const moved = gs.cur_position.getPieceFromSquare(m.from);

    if (m.isCastle()) {
        s.str(if (m.isKingsideCastle()) "O-O" else "O-O-O");
    } else if (moved == .Pawn) {
        if (m.isCapture()) {
            s.byte('a' + @as(u8, utils.fileOf(m.from)));
            s.byte('x');
        }
        s.square(m.to);
        if (m.isPromo()) {
            s.byte('=');
            s.byte(pieceLetter(m.promoPiece()));
        }
    } else {
        s.byte(pieceLetter(moved));
        try disambiguate(gs, m, moved, &s);
        if (m.isCapture()) s.byte('x');
        s.square(m.to);
    }

    try gs.makeMove(m);
    defer gs.unmakeMove(m);

    const them = gs.to_move;
    if (attacks.isInCheck(&gs.cur_position, them)) {
        var replies = MoveList.empty;
        try movegen.generateLegal(gs, &replies);
        s.byte(if (replies.len == 0) '#' else '+');
    }

    return s.done();
}

fn disambiguate(gs: *GameState, m: Move, moved: pos.Pieces, s: *Sink) !void {
    var list = MoveList.empty;
    try movegen.generateLegal(gs, &list);

    var ambiguous = false;
    var same_file = false;
    var same_rank = false;

    for (list.slice()) |o| {
        if (o.to != m.to or o.from == m.from) continue;
        if (gs.cur_position.getPieceFromSquare(o.from) != moved) continue;
        if (gs.cur_position.getColorFromSquare(o.from) != gs.to_move) continue;
        ambiguous = true;
        if (utils.fileOf(o.from) == utils.fileOf(m.from)) same_file = true;
        if (utils.rankOf(o.from) == utils.rankOf(m.from)) same_rank = true;
    }

    if (!ambiguous) return;

    if (!same_file) {
        s.byte('a' + @as(u8, utils.fileOf(m.from)));
    } else if (!same_rank) {
        s.byte('1' + @as(u8, utils.rankOf(m.from)));
    } else {
        s.byte('a' + @as(u8, utils.fileOf(m.from)));
        s.byte('1' + @as(u8, utils.rankOf(m.from)));
    }
}

pub fn fromSan(gs: *GameState, text: []const u8) !?Move {
    const want = strip(text);
    if (want.len == 0) return null;

    var list = MoveList.empty;
    try movegen.generateLegal(gs, &list);

    var buf: [max_len]u8 = undefined;
    for (list.slice()) |m| {
        const san = try toSan(gs, m, &buf);
        if (std.mem.eql(u8, strip(san), want)) return m;
    }

    var ubuf: [8]u8 = undefined;
    for (list.slice()) |m| {
        if (std.mem.eql(u8, m.toUci(&ubuf), want)) return m;
    }

    return null;
}

pub fn fromUci(gs: *GameState, text: []const u8) !?Move {
    var list = MoveList.empty;
    try movegen.generateLegal(gs, &list);
    var buf: [8]u8 = undefined;
    for (list.slice()) |m| {
        if (std.mem.eql(u8, m.toUci(&buf), text)) return m;
    }
    return null;
}

fn strip(s: []const u8) []const u8 {
    var out = std.mem.trim(u8, s, " \t\r\n");
    while (out.len > 0) {
        const c = out[out.len - 1];
        if (c == '+' or c == '#' or c == '!' or c == '?') {
            out = out[0 .. out.len - 1];
        } else break;
    }
    if (out.len >= 3 and out[0] == '0') return out;
    return out;
}

pub fn pvToSanCopy(src: *const GameState, pv: []const u8, buf: []u8) []const u8 {
    var scratch = src.*;
    return pvToSanNoRestore(&scratch, pv, buf);
}

fn pvToSanNoRestore(gs: *GameState, pv: []const u8, buf: []u8) []const u8 {
    var out = Sink{ .buf = buf };
    var it = std.mem.tokenizeAny(u8, pv, " \t");
    var first = true;
    var count: usize = 0;

    while (it.next()) |tok| : (count += 1) {
        if (count >= 32) break;
        if (gs.ply + 1 >= gs.history.len) break;

        const m = (fromUci(gs, tok) catch null) orelse break;
        var sbuf: [max_len]u8 = undefined;
        const san = toSan(gs, m, &sbuf) catch break;

        if (!first) out.byte(' ');
        const full = (gs.ply + @intFromBool(gs.to_move == .White)) / 2;
        if (gs.to_move == .White) {
            out.print("{d}.", .{full});
        } else if (first) {
            out.print("{d}...", .{full});
        }
        out.str(san);
        first = false;

        gs.makeMove(m) catch break;
    }
    return out.done();
}

test "san basics" {
    try attacks.init();
    var gs = try root.fen.parseFEN(utils.start_position);

    var buf: [max_len]u8 = undefined;
    const e4 = (try fromSan(&gs, "e4")).?;
    try std.testing.expectEqualStrings("e4", try toSan(&gs, e4, &buf));

    try gs.makeMove(e4);
    const c5 = (try fromSan(&gs, "c5")).?;
    try gs.makeMove(c5);
    const nf3 = (try fromSan(&gs, "Nf3")).?;
    try std.testing.expectEqualStrings("Nf3", try toSan(&gs, nf3, &buf));
}

test "san disambiguation and mate" {
    try attacks.init();
    var gs = try root.fen.parseFEN("4k3/8/8/8/8/8/8/N1N1K3 w - - 0 1");
    var list = MoveList.empty;
    try movegen.generateLegal(&gs, &list);

    var buf: [max_len]u8 = undefined;
    var seen_a = false;
    var seen_c = false;
    for (list.slice()) |m| {
        const s = try toSan(&gs, m, &buf);
        if (std.mem.eql(u8, s, "Nab3")) seen_a = true;
        if (std.mem.eql(u8, s, "Ncb3")) seen_c = true;
    }
    try std.testing.expect(seen_a and seen_c);
}
