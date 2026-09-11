const std = @import("std");
const chess = @import("chess");
const game_mod = @import("game.zig");
const manager_mod = @import("engine/manager.zig");
const engine_mod = @import("engine/engine.zig");
const log_mod = @import("log.zig");

const Game = game_mod.Game;
const Manager = manager_mod.Manager;
const Log = log_mod.Log;
const Move = chess.Move;
const Color = chess.Color;

pub const PlayerKind = enum { human, engine };

pub const Player = struct {
    kind: PlayerKind = .human,
    engine: usize = 0,

    pub fn name(self: Player, mgr: *Manager) []const u8 {
        if (self.kind == .human) return "Human";
        const e = mgr.get(self.engine) orelse return "engine?";
        return e.nameSlice();
    }
};

pub const TcKind = enum {
    increment,
    sudden_death,
    movetime,
    depth,
    nodes,

    pub fn usesClock(self: TcKind) bool {
        return self == .increment or self == .sudden_death;
    }

    pub fn label(self: TcKind) [:0]const u8 {
        return switch (self) {
            .increment => "clock + increment",
            .sudden_death => "sudden death",
            .movetime => "fixed time / move",
            .depth => "fixed depth",
            .nodes => "fixed nodes",
        };
    }
};

pub const TimeControl = struct {
    kind: TcKind = .increment,
    base_ms: i64 = 180_000,
    inc_ms: i64 = 2_000,
    movetime_ms: i64 = 1_000,
    depth: u32 = 12,
    nodes: u64 = 500_000,

    pub fn describe(self: TimeControl, buf: []u8) []const u8 {
        return switch (self.kind) {
            .increment => std.fmt.bufPrint(buf, "{d}+{d}", .{
                @divTrunc(self.base_ms, 1000),
                @divTrunc(self.inc_ms, 1000),
            }) catch "?",
            .sudden_death => std.fmt.bufPrint(buf, "{d}s", .{@divTrunc(self.base_ms, 1000)}) catch "?",
            .movetime => std.fmt.bufPrint(buf, "{d}ms/move", .{self.movetime_ms}) catch "?",
            .depth => std.fmt.bufPrint(buf, "depth {d}", .{self.depth}) catch "?",
            .nodes => std.fmt.bufPrint(buf, "{d} nodes", .{self.nodes}) catch "?",
        };
    }
};

pub const State = enum {
    idle,
    playing,
    between,
    finished,
};

pub const Match = struct {
    white: Player = .{},
    black: Player = .{},
    tc: TimeControl = .{},
    total_games: u32 = 1,
    swap_colors: bool = true,
    save_pgn: bool = true,
    start_fen: [128]u8 = undefined,
    start_fen_len: usize = 0,

    state: State = .idle,
    game_index: u32 = 0,
    seats: [2]Player = .{ .{}, .{} },

    clock: [2]i64 = .{ 0, 0 },
    move_start_ms: i64 = 0,
    thinking: bool = false,
    thinking_side: Color = .White,

    p1_wins: u32 = 0,
    p2_wins: u32 = 0,
    draws: u32 = 0,

    result: chess.GameResult = .Ongoing,
    message: [96]u8 = undefined,
    message_len: usize = 0,

    next_game_at: i64 = 0,
    between_ms: i64 = 1200,

    pgn_path: [96]u8 = undefined,
    pgn_path_len: usize = 0,
    pgn_buf: [24 * 1024]u8 = undefined,

    pub fn init(self: *Match) void {
        self.* = .{};
        self.setStartFen(chess.start_position);
        self.setPgnPath("callisto_games.pgn");
    }

    pub fn setStartFen(self: *Match, fen_text: []const u8) void {
        const t = std.mem.trim(u8, fen_text, " \t\r\n");
        const n = @min(t.len, self.start_fen.len);
        @memcpy(self.start_fen[0..n], t[0..n]);
        self.start_fen_len = n;
    }

    pub fn startFen(self: *const Match) []const u8 {
        return self.start_fen[0..self.start_fen_len];
    }

    pub fn setPgnPath(self: *Match, path: []const u8) void {
        const n = @min(path.len, self.pgn_path.len);
        @memcpy(self.pgn_path[0..n], path[0..n]);
        self.pgn_path_len = n;
    }

    pub fn messageSlice(self: *const Match) []const u8 {
        return self.message[0..self.message_len];
    }

    fn setMessage(self: *Match, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(&self.message, fmt, args) catch {
            self.message_len = 0;
            return;
        };
        self.message_len = w.len;
    }

    pub fn isRunning(self: *const Match) bool {
        return self.state == .playing or self.state == .between;
    }

    pub fn seat(self: *const Match, c: Color) Player {
        return self.seats[c.idx()];
    }

    pub fn humanMayMove(self: *const Match, side: Color) bool {
        if (self.state != .playing) return true; 
        return self.seats[side.idx()].kind == .human;
    }

    pub fn usesEngine(self: *const Match, idx: usize) bool {
        if (!self.isRunning()) return false;
        for (self.seats) |p| {
            if (p.kind == .engine and p.engine == idx) return true;
        }
        return false;
    }

    pub fn remaining(self: *const Match, c: Color, to_move: Color) i64 {
        var ms = self.clock[c.idx()];
        if (self.state == .playing and c == to_move and self.move_start_ms != 0) {
            ms -= std.time.milliTimestamp() - self.move_start_ms;
        }
        return ms;
    }

    pub fn start(self: *Match, game: *Game, mgr: *Manager, log: *Log) !void {
        for ([_]Player{ self.white, self.black }) |p| {
            if (p.kind != .engine) continue;
            const e = mgr.get(p.engine) orelse return error.NoSuchEngine;
            if (!e.isReady()) return error.EngineNotReady;
        }

        mgr.setAnalysis(false, log);
        self.game_index = 0;
        self.p1_wins = 0;
        self.p2_wins = 0;
        self.draws = 0;
        self.state = .playing;

        var tcb: [32]u8 = undefined;
        log.print("match", .note, "starting {d} game(s), {s}", .{
            self.total_games,
            self.tc.describe(&tcb),
        });

        try self.beginGame(game, mgr, log);
    }

    pub fn abort(self: *Match, mgr: *Manager, log: *Log) void {
        if (self.state == .idle) return;
        self.releaseEngines(mgr, log);
        self.state = .idle;
        self.thinking = false;
        self.setMessage("match aborted", .{});
        log.add("match", .note, "aborted");
    }

    fn releaseEngines(self: *Match, mgr: *Manager, log: *Log) void {
        for (self.seats) |p| {
            if (p.kind != .engine) continue;
            const e = mgr.get(p.engine) orelse continue;
            if (e.searching) e.stopSearch(log);
            if (e.owner == .match) e.owner = .none;
        }
    }

    fn beginGame(self: *Match, game: *Game, mgr: *Manager, log: *Log) !void {
        const swapped = self.swap_colors and (self.game_index % 2 == 1);
        self.seats[0] = if (swapped) self.black else self.white;
        self.seats[1] = if (swapped) self.white else self.black;

        try game.setFen(self.startFen());
        game.setNames(self.seats[0].name(mgr), self.seats[1].name(mgr));
        game.result = .Ongoing;
        game.setTermination("");

        self.clock[0] = self.tc.base_ms;
        self.clock[1] = self.tc.base_ms;
        self.move_start_ms = 0;
        self.thinking = false;
        self.result = .Ongoing;

        for (self.seats) |p| {
            if (p.kind != .engine) continue;
            const e = mgr.get(p.engine) orelse continue;
            e.owner = .match;
            e.newGame(log);
        }

        self.state = .playing;
        self.setMessage("game {d} of {d}", .{ self.game_index + 1, self.total_games });
        log.print("match", .note, "game {d}: {s} vs {s}", .{
            self.game_index + 1,
            game.whiteName(),
            game.blackName(),
        });
    }

    pub fn update(self: *Match, game: *Game, mgr: *Manager, log: *Log) void {
        switch (self.state) {
            .idle, .finished => return,
            .between => {
                if (std.time.milliTimestamp() >= self.next_game_at) {
                    self.game_index += 1;
                    if (self.game_index >= self.total_games) {
                        self.finish(mgr, log);
                    } else {
                        self.beginGame(game, mgr, log) catch |err| {
                            log.print("match", .err, "cannot start game: {s}", .{@errorName(err)});
                            self.finish(mgr, log);
                        };
                    }
                }
                return;
            },
            .playing => {},
        }

        if (!game.atEnd()) game.toEnd();

        const st = game.status();
        if (st.isOver()) {
            self.endGame(game, mgr, log, game.resultFor(st), st.label());
            return;
        }

        const side = game.sideToMove();
        const player = self.seats[side.idx()];

        if (self.move_start_ms == 0) self.move_start_ms = std.time.milliTimestamp();

        if (player.kind == .human) {
            self.thinking = false;
            return;
        }

        const e = mgr.get(player.engine) orelse {
            self.endGame(game, mgr, log, winnerAgainst(side), "engine missing");
            return;
        };

        if (e.status == .failed or !e.isRunning()) {
            self.endGame(game, mgr, log, winnerAgainst(side), "engine crashed");
            return;
        }

        if (!self.thinking) {
            if (!e.isReady() or e.searching or e.pending_ready > 0) return;
            e.go(log, game.rootFen(), game.movesToCursor(), game.state(), self.limits());
            self.thinking = true;
            self.thinking_side = side;
            return;
        }

        if (self.tc.kind.usesClock() and self.remaining(side, side) <= 0) {
            e.stopSearch(log);
            self.endGame(game, mgr, log, winnerAgainst(side), "loss on time");
            return;
        }

        if (e.takeBestMove(game.state())) |m| {
            self.commitMove(game, side, m, e);
        } else if (e.has_best) {
            const text = e.bestMoveText();
            log.print(e.nameSlice(), .err, "illegal bestmove '{s}'", .{text});
            e.has_best = false;
            self.endGame(game, mgr, log, winnerAgainst(side), "illegal move");
        }
    }

    fn commitMove(self: *Match, game: *Game, side: Color, m: Move, e: *engine_mod.Engine) void {
        const now = std.time.milliTimestamp();
        const spent = if (self.move_start_ms == 0) 0 else now - self.move_start_ms;

        if (self.tc.kind.usesClock()) {
            self.clock[side.idx()] -= spent;
            if (self.tc.kind == .increment) self.clock[side.idx()] += self.tc.inc_ms;
        }

        game.play(m) catch {
            self.setMessage("move list is full", .{});
            return;
        };

        if (game.count > 0) {
            const p = &game.plies[game.count - 1];
            p.time_ms = @intCast(@max(spent, 0));
            if (e.whitePovScore()) |s| {
                switch (s) {
                    .cp => |v| {
                        p.eval_cp = v;
                        p.eval_is_mate = false;
                    },
                    .mate => |v| {
                        p.eval_mate = v;
                        p.eval_is_mate = true;
                    },
                }
                p.has_eval = true;
            }
        }

        self.thinking = false;
        self.move_start_ms = 0;
    }

    pub fn onHumanMove(self: *Match, game: *Game) void {
        if (self.state != .playing) return;
        const mover = game.sideToMove().oposite();
        const now = std.time.milliTimestamp();
        const spent = if (self.move_start_ms == 0) 0 else now - self.move_start_ms;

        if (self.tc.kind.usesClock()) {
            self.clock[mover.idx()] -= spent;
            if (self.tc.kind == .increment) self.clock[mover.idx()] += self.tc.inc_ms;
        }
        if (game.count > 0) {
            game.plies[game.count - 1].time_ms = @intCast(@max(spent, 0));
        }
        self.move_start_ms = 0;
        self.thinking = false;
    }

    fn limits(self: *const Match) chess.uci.Limits {
        return switch (self.tc.kind) {
            .movetime => .{ .movetime_ms = @intCast(@max(self.tc.movetime_ms, 1)) },
            .depth => .{ .depth = self.tc.depth },
            .nodes => .{ .nodes = self.tc.nodes },
            .increment => .{
                .wtime_ms = @max(self.clock[0], 1),
                .btime_ms = @max(self.clock[1], 1),
                .winc_ms = self.tc.inc_ms,
                .binc_ms = self.tc.inc_ms,
            },
            .sudden_death => .{
                .wtime_ms = @max(self.clock[0], 1),
                .btime_ms = @max(self.clock[1], 1),
            },
        };
    }

    fn winnerAgainst(loser: Color) chess.GameResult {
        return if (loser == .White) .BlackWin else .WhiteWin;
    }

    fn endGame(
        self: *Match,
        game: *Game,
        mgr: *Manager,
        log: *Log,
        result: chess.GameResult,
        reason: []const u8,
    ) void {
        self.result = result;
        game.result = result;
        game.setTermination(reason);
        self.thinking = false;
        self.move_start_ms = 0;

        for (self.seats) |p| {
            if (p.kind != .engine) continue;
            const e = mgr.get(p.engine) orelse continue;
            if (e.searching) e.stopSearch(log);
        }

        const swapped = self.swap_colors and (self.game_index % 2 == 1);
        switch (result) {
            .WhiteWin => if (swapped) {
                self.p2_wins += 1;
            } else {
                self.p1_wins += 1;
            },
            .BlackWin => if (swapped) {
                self.p1_wins += 1;
            } else {
                self.p2_wins += 1;
            },
            else => self.draws += 1,
        }

        self.setMessage("{s}: {s}", .{ chess.pgn.Result.fromGameResult(result).text(), reason });
        log.print("match", .note, "game {d} ended {s} ({s})", .{
            self.game_index + 1,
            chess.pgn.Result.fromGameResult(result).text(),
            reason,
        });

        if (self.save_pgn) self.writePgn(game, reason, log);

        if (self.game_index + 1 >= self.total_games) {
            self.finish(mgr, log);
        } else {
            self.state = .between;
            self.next_game_at = std.time.milliTimestamp() + self.between_ms;
        }
    }

    fn finish(self: *Match, mgr: *Manager, log: *Log) void {
        self.releaseEngines(mgr, log);
        self.state = .finished;
        log.print("match", .note, "final score {d} - {d} - {d}", .{ self.p1_wins, self.p2_wins, self.draws });
    }

    fn writePgn(self: *Match, game: *Game, reason: []const u8, log: *Log) void {
        var date_buf: [16]u8 = undefined;
        var tc_buf: [32]u8 = undefined;
        var round_buf: [16]u8 = undefined;

        const tags = chess.pgn.Tags{
            .event = "Callisto match",
            .site = "local",
            .date = todayString(&date_buf),
            .round = std.fmt.bufPrint(&round_buf, "{d}", .{self.game_index + 1}) catch "-",
            .white = game.whiteName(),
            .black = game.blackName(),
            .result = chess.pgn.Result.fromGameResult(self.result),
            .fen = if (std.mem.eql(u8, self.startFen(), chess.start_position)) null else self.startFen(),
            .time_control = self.tc.describe(&tc_buf),
            .termination = reason,
        };

        const text = chess.pgn.write(&self.pgn_buf, tags, game.root, game.moves[0..game.count]) catch {
            log.add("match", .err, "PGN buffer too small, game not saved");
            return;
        };

        chess.pgn.appendToFile(self.pgn_path[0..self.pgn_path_len], text) catch |err| {
            log.print("match", .err, "could not write PGN: {s}", .{@errorName(err)});
            return;
        };
    }
};

pub fn todayString(buf: []u8) []const u8 {
    const now = std.time.timestamp();
    if (now <= 0) return "????.??.??";
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    return std.fmt.bufPrint(buf, "{d:0>4}.{d:0>2}.{d:0>2}", .{
        yd.year,
        md.month.numeric(),
        @as(u32, md.day_index) + 1,
    }) catch "????.??.??";
}

pub fn clockText(buf: []u8, ms: i64) []const u8 {
    const clamped = @max(ms, 0);
    const total_s = @divTrunc(clamped, 1000);
    const m = @divTrunc(total_s, 60);
    const s = @mod(total_s, 60);
    if (m == 0 and total_s < 20) {
        const tenths = @divTrunc(@mod(clamped, 1000), 100);
        return std.fmt.bufPrint(buf, "{d}.{d}", .{ s, tenths }) catch "?";
    }
    return std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ m, s }) catch "?";
}
