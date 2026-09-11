const std = @import("std");
const root = @import("root.zig");
const pos = root.pos;
const utils = root.utils;
const san_mod = root.san;
const movegen = root.movegen;

const Move = pos.Move;
const GameState = pos.GameState;

pub const max_moves = 600;
pub const max_tag_len = 96;

pub const Result = enum {
    white_win,
    black_win,
    draw,
    unknown,

    pub fn text(self: Result) []const u8 {
        return switch (self) {
            .white_win => "1-0",
            .black_win => "0-1",
            .draw => "1/2-1/2",
            .unknown => "*",
        };
    }

    pub fn parse(s: []const u8) Result {
        if (std.mem.eql(u8, s, "1-0")) return .white_win;
        if (std.mem.eql(u8, s, "0-1")) return .black_win;
        if (std.mem.eql(u8, s, "1/2-1/2")) return .draw;
        return .unknown;
    }

    pub fn fromGameResult(r: pos.GameResult) Result {
        return switch (r) {
            .WhiteWin => .white_win,
            .BlackWin => .black_win,
            .Draw => .draw,
            .Ongoing => .unknown,
        };
    }
};

pub const Tags = struct {
    event: []const u8 = "Callisto game",
    site: []const u8 = "local",
    date: []const u8 = "????.??.??",
    round: []const u8 = "-",
    white: []const u8 = "White",
    black: []const u8 = "Black",
    result: Result = .unknown,
    fen: ?[]const u8 = null,
    time_control: ?[]const u8 = null,
    termination: ?[]const u8 = null,
};

const Sink = struct {
    buf: []u8,
    len: usize = 0,
    overflow: bool = false,

    fn str(self: *Sink, s: []const u8) void {
        if (self.len + s.len > self.buf.len) {
            self.overflow = true;
            return;
        }
        @memcpy(self.buf[self.len..][0..s.len], s);
        self.len += s.len;
    }

    fn print(self: *Sink, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(self.buf[self.len..], fmt, args) catch {
            self.overflow = true;
            return;
        };
        self.len += w.len;
    }

    fn done(self: *Sink) []const u8 {
        return self.buf[0..self.len];
    }
};

pub fn write(buf: []u8, tags: Tags, start: GameState, moves: []const Move) ![]const u8 {
    var s = Sink{ .buf = buf };

    s.print("[Event \"{s}\"]\n", .{tags.event});
    s.print("[Site \"{s}\"]\n", .{tags.site});
    s.print("[Date \"{s}\"]\n", .{tags.date});
    s.print("[Round \"{s}\"]\n", .{tags.round});
    s.print("[White \"{s}\"]\n", .{tags.white});
    s.print("[Black \"{s}\"]\n", .{tags.black});
    s.print("[Result \"{s}\"]\n", .{tags.result.text()});
    if (tags.fen) |f| {
        s.print("[SetUp \"1\"]\n[FEN \"{s}\"]\n", .{f});
    }
    if (tags.time_control) |tc| s.print("[TimeControl \"{s}\"]\n", .{tc});
    if (tags.termination) |t| s.print("[Termination \"{s}\"]\n", .{t});
    s.str("\n");

    var gs = start;
    var col: usize = 0;
    var sbuf: [san_mod.max_len]u8 = undefined;
    var word: [24]u8 = undefined;

    for (moves) |m| {
        if (gs.ply + 1 >= gs.history.len) break;
        const text = san_mod.toSan(&gs, m, &sbuf) catch break;

        var piece: []const u8 = undefined;
        if (gs.to_move == .White) {
            const full = (gs.ply + 1) / 2;
            piece = std.fmt.bufPrint(&word, "{d}. {s}", .{ full, text }) catch text;
        } else {
            piece = std.fmt.bufPrint(&word, "{s}", .{text}) catch text;
        }

        if (col + piece.len + 1 > 79) {
            s.str("\n");
            col = 0;
        } else if (col > 0) {
            s.str(" ");
            col += 1;
        }
        s.str(piece);
        col += piece.len;

        gs.makeMove(m) catch break;
    }

    if (col + tags.result.text().len + 1 > 79) {
        s.str("\n");
    } else if (col > 0) {
        s.str(" ");
    }
    s.str(tags.result.text());
    s.str("\n\n");

    if (s.overflow) return error.NoSpaceLeft;
    return s.done();
}

pub fn appendToFile(path: []const u8, text: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false, .read = true });
    defer file.close();
    const end = try file.getEndPos();
    try file.seekTo(end);
    try file.writeAll(text);
}

pub const Game = struct {
    start_fen: [128]u8 = undefined,
    start_fen_len: usize = 0,
    white: [max_tag_len]u8 = undefined,
    white_len: usize = 0,
    black: [max_tag_len]u8 = undefined,
    black_len: usize = 0,
    event: [max_tag_len]u8 = undefined,
    event_len: usize = 0,
    result: Result = .unknown,
    moves: [max_moves]Move = undefined,
    count: usize = 0,

    pub fn whiteName(self: *const Game) []const u8 {
        return self.white[0..self.white_len];
    }
    pub fn blackName(self: *const Game) []const u8 {
        return self.black[0..self.black_len];
    }
    pub fn fen(self: *const Game) ?[]const u8 {
        if (self.start_fen_len == 0) return null;
        return self.start_fen[0..self.start_fen_len];
    }
};

fn copyInto(dst: []u8, len: *usize, src: []const u8) void {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    len.* = n;
}

pub fn read(text: []const u8, out: *Game) !void {
    out.* = .{};

    var lines = std.mem.splitScalar(u8, text, '\n');
    var movetext_start: usize = 0;
    var offset: usize = 0;

    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        offset += raw.len + 1;
        if (line.len == 0) {
            if (movetext_start != 0) break;
            continue;
        }
        if (line[0] != '[') {
            movetext_start = offset - raw.len - 1;
            break;
        }
        movetext_start = offset;

        const key_end = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const key = line[1..key_end];
        const q1 = std.mem.indexOfScalar(u8, line, '"') orelse continue;
        const q2 = std.mem.lastIndexOfScalar(u8, line, '"') orelse continue;
        if (q2 <= q1) continue;
        const value = line[q1 + 1 .. q2];

        if (std.mem.eql(u8, key, "White")) {
            copyInto(&out.white, &out.white_len, value);
        } else if (std.mem.eql(u8, key, "Black")) {
            copyInto(&out.black, &out.black_len, value);
        } else if (std.mem.eql(u8, key, "Event")) {
            copyInto(&out.event, &out.event_len, value);
        } else if (std.mem.eql(u8, key, "Result")) {
            out.result = Result.parse(value);
        } else if (std.mem.eql(u8, key, "FEN")) {
            copyInto(&out.start_fen, &out.start_fen_len, value);
        }
    }

    const body = if (movetext_start < text.len) text[movetext_start..] else "";

    var gs = if (out.start_fen_len > 0)
        try root.fen.parseFEN(out.start_fen[0..out.start_fen_len])
    else
        try root.fen.parseFEN(utils.start_position);

    var i: usize = 0;
    var depth: usize = 0;
    while (i < body.len) {
        const c = body[i];
        switch (c) {
            ' ', '\t', '\r', '\n' => i += 1,
            '{' => {
                while (i < body.len and body[i] != '}') i += 1;
                if (i < body.len) i += 1;
            },
            ';' => {
                while (i < body.len and body[i] != '\n') i += 1;
            },
            '(' => {
                depth += 1;
                i += 1;
            },
            ')' => {
                if (depth > 0) depth -= 1;
                i += 1;
            },
            '$' => {
                i += 1;
                while (i < body.len and std.ascii.isDigit(body[i])) i += 1;
            },
            else => {
                const start = i;
                while (i < body.len and !std.ascii.isWhitespace(body[i]) and
                    body[i] != '(' and body[i] != ')' and body[i] != '{') i += 1;
                const tok = body[start..i];
                if (depth > 0 or tok.len == 0) continue;

                if (isMoveNumber(tok)) continue;
                if (std.mem.eql(u8, tok, "*") or std.mem.eql(u8, tok, "1-0") or
                    std.mem.eql(u8, tok, "0-1") or std.mem.eql(u8, tok, "1/2-1/2"))
                {
                    if (out.result == .unknown) out.result = Result.parse(tok);
                    continue;
                }

                if (out.count >= max_moves) break;
                if (gs.ply + 1 >= gs.history.len) break;
                const m = (san_mod.fromSan(&gs, tok) catch null) orelse return error.IllegalMove;
                out.moves[out.count] = m;
                out.count += 1;
                gs.makeMove(m) catch return error.IllegalMove;
            },
        }
    }
}

fn isMoveNumber(tok: []const u8) bool {
    var seen_digit = false;
    for (tok) |c| {
        if (std.ascii.isDigit(c)) {
            seen_digit = true;
        } else if (c != '.') {
            return false;
        }
    }
    return seen_digit;
}

test "pgn round trip" {
    try root.attacks.init();
    var gs = try root.fen.parseFEN(utils.start_position);

    const e4 = (try san_mod.fromSan(&gs, "e4")).?;
    try gs.makeMove(e4);
    const e5 = (try san_mod.fromSan(&gs, "e5")).?;
    try gs.makeMove(e5);
    const nf3 = (try san_mod.fromSan(&gs, "Nf3")).?;

    var start = try root.fen.parseFEN(utils.start_position);
    _ = &start;

    var buf: [2048]u8 = undefined;
    const text = try write(&buf, .{ .white = "A", .black = "B", .result = .draw }, start, &.{ e4, e5, nf3 });
    try std.testing.expect(std.mem.indexOf(u8, text, "1. e4 e5 2. Nf3") != null);

    var parsed: Game = undefined;
    try read(text, &parsed);
    try std.testing.expectEqual(@as(usize, 3), parsed.count);
    try std.testing.expectEqualStrings("A", parsed.whiteName());
    try std.testing.expectEqual(Result.draw, parsed.result);
}
