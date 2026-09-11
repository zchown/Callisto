const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;

const Move = pos.Move;

pub const max_pv_moves = 32;

pub const Score = union(enum) {
    cp: i32,
    mate: i32,

    pub fn toCp(self: Score) i32 {
        return switch (self) {
            .cp => |v| v,
            .mate => |m| if (m >= 0) 100_000 - m * 100 else -100_000 - m * 100,
        };
    }

    pub fn negate(self: Score) Score {
        return switch (self) {
            .cp => |v| .{ .cp = -v },
            .mate => |m| .{ .mate = -m },
        };
    }

    pub fn format(self: Score, buf: []u8) []const u8 {
        return switch (self) {
            .cp => |v| blk: {
                const f = @as(f32, @floatFromInt(v)) / 100.0;
                break :blk std.fmt.bufPrint(buf, "{s}{d:.2}", .{
                    if (v > 0) "+" else if (v < 0) "-" else " ",
                    @abs(f),
                }) catch "?";
            },
            .mate => |m| std.fmt.bufPrint(buf, "#{d}", .{m}) catch "?",
        };
    }
};

pub const Info = struct {
    depth: ?u32 = null,
    seldepth: ?u32 = null,
    multipv: u32 = 1,
    score: ?Score = null,
    lowerbound: bool = false,
    upperbound: bool = false,
    nodes: ?u64 = null,
    nps: ?u64 = null,
    time_ms: ?u64 = null,
    hashfull: ?u32 = null,
    tbhits: ?u64 = null,
    currmove: ?[]const u8 = null,
    currmovenumber: ?u32 = null,
    pv: ?[]const u8 = null,
    string: ?[]const u8 = null,
};

pub const OptionKind = enum { check, spin, combo, button, string, unknown };

pub const OptionDecl = struct {
    name: []const u8,
    kind: OptionKind = .unknown,
    default: []const u8 = "",
    min: ?i64 = null,
    max: ?i64 = null,
};

pub const BestMove = struct {
    move: []const u8,
    ponder: ?[]const u8 = null,
};

pub const Message = union(enum) {
    none,
    unknown: []const u8,
    id_name: []const u8,
    id_author: []const u8,
    uciok,
    readyok,
    bestmove: BestMove,
    info: Info,
    option: OptionDecl,
    copyprotection: []const u8,
    registration: []const u8,
    text: []const u8, // anything else
};

pub fn parse(raw_line: []const u8) Message {
    const line = std.mem.trim(u8, raw_line, " \t\r\n");
    if (line.len == 0) return .none;

    var it = std.mem.tokenizeAny(u8, line, " \t");
    const head = it.next() orelse return .none;

    if (eq(head, "uciok")) return .uciok;
    if (eq(head, "readyok")) return .readyok;
    if (eq(head, "id")) return parseId(&it);
    if (eq(head, "bestmove")) return parseBestMove(&it);
    if (eq(head, "info")) return .{ .info = parseInfo(it.rest()) };
    if (eq(head, "option")) return parseOption(line);
    if (eq(head, "copyprotection")) return .{ .copyprotection = it.rest() };
    if (eq(head, "registration")) return .{ .registration = it.rest() };

    return .{ .text = line };
}

fn parseId(it: *std.mem.TokenIterator(u8, .any)) Message {
    const what = it.next() orelse return .{ .unknown = "id" };
    const rest = std.mem.trim(u8, it.rest(), " \t");
    if (eq(what, "name")) return .{ .id_name = rest };
    if (eq(what, "author")) return .{ .id_author = rest };
    return .{ .unknown = rest };
}

fn parseBestMove(it: *std.mem.TokenIterator(u8, .any)) Message {
    const best = it.next() orelse return .{ .unknown = "bestmove" };
    var bm = BestMove{ .move = best };
    if (it.next()) |kw| {
        if (eq(kw, "ponder")) bm.ponder = it.next();
    }
    return .{ .bestmove = bm };
}

pub fn parseInfo(body: []const u8) Info {
    var info = Info{};
    var it = std.mem.tokenizeAny(u8, body, " \t");

    while (it.next()) |tok| {
        if (eq(tok, "depth")) {
            info.depth = nextInt(u32, &it);
        } else if (eq(tok, "seldepth")) {
            info.seldepth = nextInt(u32, &it);
        } else if (eq(tok, "multipv")) {
            info.multipv = nextInt(u32, &it) orelse 1;
        } else if (eq(tok, "nodes")) {
            info.nodes = nextInt(u64, &it);
        } else if (eq(tok, "nps")) {
            info.nps = nextInt(u64, &it);
        } else if (eq(tok, "time")) {
            info.time_ms = nextInt(u64, &it);
        } else if (eq(tok, "hashfull")) {
            info.hashfull = nextInt(u32, &it);
        } else if (eq(tok, "tbhits")) {
            info.tbhits = nextInt(u64, &it);
        } else if (eq(tok, "currmove")) {
            info.currmove = it.next();
        } else if (eq(tok, "currmovenumber")) {
            info.currmovenumber = nextInt(u32, &it);
        } else if (eq(tok, "score")) {
            const kind = it.next() orelse continue;
            if (eq(kind, "cp")) {
                if (nextInt(i32, &it)) |v| info.score = .{ .cp = v };
            } else if (eq(kind, "mate")) {
                if (nextInt(i32, &it)) |v| info.score = .{ .mate = v };
            }
        } else if (eq(tok, "lowerbound")) {
            info.lowerbound = true;
        } else if (eq(tok, "upperbound")) {
            info.upperbound = true;
        } else if (eq(tok, "pv")) {
            info.pv = std.mem.trim(u8, it.rest(), " \t");
            break;
        } else if (eq(tok, "string")) {
            info.string = std.mem.trim(u8, it.rest(), " \t");
            break;
        }
    }
    return info;
}

fn parseOption(line: []const u8) Message {
    const name_kw = " name ";
    const type_kw = " type ";

    const name_at = std.mem.indexOf(u8, line, name_kw) orelse return .{ .unknown = line };
    const name_start = name_at + name_kw.len;

    var decl = OptionDecl{ .name = "" };

    const type_at = std.mem.indexOfPos(u8, line, name_start, type_kw);
    if (type_at == null) {
        decl.name = std.mem.trim(u8, line[name_start..], " \t");
        return .{ .option = decl };
    }

    decl.name = std.mem.trim(u8, line[name_start..type_at.?], " \t");
    const tail = line[type_at.? + type_kw.len ..];

    var it = std.mem.tokenizeAny(u8, tail, " \t");
    const kind_tok = it.next() orelse return .{ .option = decl };
    decl.kind = if (eq(kind_tok, "check"))
        .check
    else if (eq(kind_tok, "spin"))
        .spin
    else if (eq(kind_tok, "combo"))
        .combo
    else if (eq(kind_tok, "button"))
        .button
    else if (eq(kind_tok, "string"))
        .string
    else
        .unknown;

    while (it.next()) |tok| {
        if (eq(tok, "default")) {
            const rest = it.rest();
            const cut = cutAtKeyword(rest);
            decl.default = std.mem.trim(u8, cut, " \t");
            var re = std.mem.tokenizeAny(u8, rest[cut.len..], " \t");
            while (re.next()) |k| {
                if (eq(k, "min")) {
                    decl.min = nextInt(i64, &re);
                } else if (eq(k, "max")) {
                    decl.max = nextInt(i64, &re);
                }
            }
            break;
        } else if (eq(tok, "min")) {
            decl.min = nextInt(i64, &it);
        } else if (eq(tok, "max")) {
            decl.max = nextInt(i64, &it);
        }
    }

    return .{ .option = decl };
}

fn cutAtKeyword(s: []const u8) []const u8 {
    const keys = [_][]const u8{ " min ", " max ", " var " };
    var end = s.len;
    for (keys) |k| {
        if (std.mem.indexOf(u8, s, k)) |at| end = @min(end, at);
    }
    return s[0..end];
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn nextInt(comptime T: type, it: *std.mem.TokenIterator(u8, .any)) ?T {
    const tok = it.next() orelse return null;
    return std.fmt.parseInt(T, tok, 10) catch null;
}

pub const Limits = struct {
    infinite: bool = false,
    depth: ?u32 = null,
    nodes: ?u64 = null,
    movetime_ms: ?u64 = null,
    wtime_ms: ?i64 = null,
    btime_ms: ?i64 = null,
    winc_ms: ?i64 = null,
    binc_ms: ?i64 = null,
    movestogo: ?u32 = null,

    pub fn isEmpty(self: Limits) bool {
        return !self.infinite and self.depth == null and self.nodes == null and
            self.movetime_ms == null and self.wtime_ms == null and self.btime_ms == null;
    }
};

const Sink = struct {
    buf: []u8,
    len: usize = 0,

    fn str(self: *Sink, s: []const u8) !void {
        if (self.len + s.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.len..][0..s.len], s);
        self.len += s.len;
    }

    fn print(self: *Sink, comptime fmt: []const u8, args: anytype) !void {
        const w = try std.fmt.bufPrint(self.buf[self.len..], fmt, args);
        self.len += w.len;
    }

    fn done(self: *Sink) []const u8 {
        return self.buf[0..self.len];
    }
};

pub fn positionCmd(buf: []u8, start_fen: ?[]const u8, moves: []const Move) ![]const u8 {
    var s = Sink{ .buf = buf };
    try s.str("position ");

    const startpos = root.utils.start_position;
    if (start_fen) |f| {
        if (std.mem.eql(u8, std.mem.trim(u8, f, " "), startpos)) {
            try s.str("startpos");
        } else {
            try s.print("fen {s}", .{f});
        }
    } else {
        try s.str("startpos");
    }

    if (moves.len > 0) {
        try s.str(" moves");
        var mb: [8]u8 = undefined;
        for (moves) |m| {
            try s.print(" {s}", .{m.toUci(&mb)});
        }
    }
    return s.done();
}

pub fn goCmd(buf: []u8, limits: Limits) ![]const u8 {
    var s = Sink{ .buf = buf };
    try s.str("go");

    if (limits.infinite) {
        try s.str(" infinite");
    } else {
        if (limits.wtime_ms) |v| try s.print(" wtime {d}", .{@max(v, 1)});
        if (limits.btime_ms) |v| try s.print(" btime {d}", .{@max(v, 1)});
        if (limits.winc_ms) |v| try s.print(" winc {d}", .{@max(v, 0)});
        if (limits.binc_ms) |v| try s.print(" binc {d}", .{@max(v, 0)});
        if (limits.movestogo) |v| try s.print(" movestogo {d}", .{v});
        if (limits.movetime_ms) |v| try s.print(" movetime {d}", .{v});
        if (limits.depth) |v| try s.print(" depth {d}", .{v});
        if (limits.nodes) |v| try s.print(" nodes {d}", .{v});
    }

    if (s.len == 2) try s.str(" infinite");
    return s.done();
}

pub fn setOptionCmd(buf: []u8, name: []const u8, value: ?[]const u8) ![]const u8 {
    var s = Sink{ .buf = buf };
    if (value) |v| {
        try s.print("setoption name {s} value {s}", .{ name, v });
    } else {
        try s.print("setoption name {s}", .{name});
    }
    return s.done();
}

test "parse info line" {
    const msg = parse("info depth 18 seldepth 24 multipv 1 score cp -37 nodes 1234567 nps 987654 time 1250 pv e2e4 e7e5 g1f3");
    try std.testing.expect(msg == .info);
    const i = msg.info;
    try std.testing.expectEqual(@as(?u32, 18), i.depth);
    try std.testing.expectEqual(@as(u32, 1), i.multipv);
    try std.testing.expectEqual(@as(i32, -37), i.score.?.cp);
    try std.testing.expectEqual(@as(?u64, 1234567), i.nodes);
    try std.testing.expectEqualStrings("e2e4 e7e5 g1f3", i.pv.?);
}

test "parse mate score and bestmove" {
    const m1 = parse("info depth 30 score mate -3 pv a1a2");
    try std.testing.expectEqual(@as(i32, -3), m1.info.score.?.mate);

    const m2 = parse("bestmove e7e8q ponder h1h8");
    try std.testing.expectEqualStrings("e7e8q", m2.bestmove.move);
    try std.testing.expectEqualStrings("h1h8", m2.bestmove.ponder.?);
}

test "parse options" {
    const a = parse("option name Hash type spin default 16 min 1 max 33554432");
    try std.testing.expectEqualStrings("Hash", a.option.name);
    try std.testing.expectEqual(OptionKind.spin, a.option.kind);
    try std.testing.expectEqualStrings("16", a.option.default);
    try std.testing.expectEqual(@as(?i64, 1), a.option.min);

    const b = parse("option name Use NNUE type check default true");
    try std.testing.expectEqualStrings("Use NNUE", b.option.name);
    try std.testing.expectEqual(OptionKind.check, b.option.kind);
    try std.testing.expectEqualStrings("true", b.option.default);

    const c = parse("option name Clear Hash type button");
    try std.testing.expectEqual(OptionKind.button, c.option.kind);
}

test "build commands" {
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "go wtime 300000 btime 299000 winc 2000 binc 2000",
        try goCmd(&buf, .{ .wtime_ms = 300000, .btime_ms = 299000, .winc_ms = 2000, .binc_ms = 2000 }),
    );
    try std.testing.expectEqualStrings("go infinite", try goCmd(&buf, .{}));
    try std.testing.expectEqualStrings(
        "setoption name MultiPV value 3",
        try setOptionCmd(&buf, "MultiPV", "3"),
    );

    const moves = [_]Move{ Move.quiet(12, 28), Move.quiet(52, 36) };
    try std.testing.expectEqualStrings(
        "position startpos moves e2e4 e7e5",
        try positionCmd(&buf, null, &moves),
    );
}
