const std = @import("std");
const chess = @import("chess");
const uci = chess.uci;
const process = @import("process.zig");
const log_mod = @import("../log.zig");

const Log = log_mod.Log;
const Move = chess.Move;
const GameState = chess.GameState;

pub const max_options = 64;
pub const max_multipv = 4;
pub const max_name = 56;
pub const max_path = 512;
pub const max_opt_name = 48;
pub const max_opt_value = 64;
pub const max_pv_text = 320;
pub const max_pv_san = 288;

pub const Status = enum {
    offline,
    starting,
    ready,
    thinking,
    failed,

    pub fn label(self: Status) [:0]const u8 {
        return switch (self) {
            .offline => "offline",
            .starting => "starting",
            .ready => "ready",
            .thinking => "searching",
            .failed => "failed",
        };
    }
};

pub const Owner = enum { none, analysis, match };

pub const Option = struct {
    name: [max_opt_name]u8 = undefined,
    name_len: u8 = 0,
    kind: uci.OptionKind = .unknown,
    value: [max_opt_value]u8 = undefined,
    value_len: u8 = 0,
    default: [max_opt_value]u8 = undefined,
    default_len: u8 = 0,
    min: ?i64 = null,
    max: ?i64 = null,
    dirty: bool = false,

    pub fn nameSlice(self: *const Option) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn valueSlice(self: *const Option) []const u8 {
        return self.value[0..self.value_len];
    }
    pub fn defaultSlice(self: *const Option) []const u8 {
        return self.default[0..self.default_len];
    }
    pub fn isDefault(self: *const Option) bool {
        return std.mem.eql(u8, self.valueSlice(), self.defaultSlice());
    }
};

pub const PvLine = struct {
    valid: bool = false,
    depth: u32 = 0,
    seldepth: u32 = 0,
    score: ?uci.Score = null,
    nodes: u64 = 0,
    nps: u64 = 0,
    time_ms: u64 = 0,
    text: [max_pv_text]u8 = undefined,
    text_len: u16 = 0,
    san: [max_pv_san]u8 = undefined,
    san_len: u16 = 0,
    end_position: chess.Position = undefined,
    end_move: ?Move = null,
    has_end: bool = false,

    pub fn uciSlice(self: *const PvLine) []const u8 {
        return self.text[0..self.text_len];
    }
    pub fn sanSlice(self: *const PvLine) []const u8 {
        return self.san[0..self.san_len];
    }
    pub fn firstMoveUci(self: *const PvLine) []const u8 {
        const s = self.uciSlice();
        const end = std.mem.indexOfScalar(u8, s, ' ') orelse s.len;
        return s[0..end];
    }
};

pub const Engine = struct {
    id: usize = 0,
    used: bool = false,

    path: [max_path]u8 = undefined,
    path_len: usize = 0,
    name: [max_name]u8 = undefined,
    name_len: usize = 0,
    author: [max_name]u8 = undefined,
    author_len: usize = 0,

    proc: ?*process.Process = null,
    status: Status = .offline,
    owner: Owner = .none,

    got_uciok: bool = false,
    pending_ready: u32 = 0,
    searching: bool = false,

    options: [max_options]Option = undefined,
    option_count: usize = 0,

    pv: [max_multipv]PvLine = undefined,
    pv_count: usize = 0,
    depth: u32 = 0,
    nodes: u64 = 0,
    nps: u64 = 0,
    hashfull: u32 = 0,
    time_ms: u64 = 0,

    best_uci: [8]u8 = undefined,
    best_len: usize = 0,
    has_best: bool = false,

    search_root: GameState = undefined,
    have_root: bool = false,

    err_text: [96]u8 = undefined,
    err_len: usize = 0,

    trace: bool = true,

    pub fn nameSlice(self: *const Engine) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn pathSlice(self: *const Engine) []const u8 {
        return self.path[0..self.path_len];
    }
    pub fn errSlice(self: *const Engine) []const u8 {
        return self.err_text[0..self.err_len];
    }

    fn setName(self: *Engine, s: []const u8) void {
        const n = @min(s.len, max_name);
        @memcpy(self.name[0..n], s[0..n]);
        self.name_len = n;
    }

    fn setError(self: *Engine, s: []const u8) void {
        const n = @min(s.len, self.err_text.len);
        @memcpy(self.err_text[0..n], s[0..n]);
        self.err_len = n;
    }

    pub fn configure(self: *Engine, id: usize, path: []const u8) void {
        self.* = .{};
        self.id = id;
        self.used = true;

        const n = @min(path.len, max_path);
        @memcpy(self.path[0..n], path[0..n]);
        self.path_len = n;

        const base = std.fs.path.basename(self.pathSlice());
        self.setName(if (base.len > 0) base else "engine");
        for (&self.pv) |*p| p.* = .{};
    }

    pub fn start(self: *Engine, allocator: std.mem.Allocator, log: *Log) void {
        if (self.proc != null) return;
        self.err_len = 0;

        self.proc = process.Process.spawn(allocator, self.pathSlice()) catch |err| {
            self.status = .failed;
            self.setError(@errorName(err));
            log.print(self.nameSlice(), .err, "could not start: {s}", .{@errorName(err)});
            return;
        };

        self.status = .starting;
        self.got_uciok = false;
        self.option_count = 0;
        self.searching = false;
        self.has_best = false;
        self.resetSearch();

        log.print(self.nameSlice(), .note, "started {s}", .{self.pathSlice()});
        self.send(log, "uci");
    }

    pub fn shutdown(self: *Engine, log: *Log) void {
        if (self.proc) |p| {
            if (self.searching) self.send(log, "stop");
            log.print(self.nameSlice(), .note, "stopping", .{});
            p.destroy();
            self.proc = null;
        }
        self.status = .offline;
        self.searching = false;
        self.owner = .none;
        self.got_uciok = false;
        self.pending_ready = 0;
        self.resetSearch();
    }

    pub fn isRunning(self: *const Engine) bool {
        return self.proc != null and self.status != .failed;
    }

    pub fn isReady(self: *const Engine) bool {
        return self.proc != null and (self.status == .ready or self.status == .thinking);
    }

    pub fn send(self: *Engine, log: *Log, cmd: []const u8) void {
        const p = self.proc orelse return;
        p.writeLine(cmd);
        if (self.trace) log.add(self.nameSlice(), .out, cmd);
    }

    pub fn sendFmt(self: *Engine, log: *Log, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const cmd = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.send(log, cmd);
    }

    pub fn isReadySync(self: *Engine, log: *Log) void {
        self.pending_ready += 1;
        self.send(log, "isready");
    }

    pub fn newGame(self: *Engine, log: *Log) void {
        if (!self.isReady()) return;
        if (self.searching) self.stopSearch(log);
        self.send(log, "ucinewgame");
        self.isReadySync(log);
        self.resetSearch();
    }

    pub fn setOptionByName(self: *Engine, log: *Log, name: []const u8, value: []const u8) bool {
        var found = false;
        for (self.options[0..self.option_count]) |*o| {
            if (!std.ascii.eqlIgnoreCase(o.nameSlice(), name)) continue;
            const n: u8 = @intCast(@min(value.len, max_opt_value));
            @memcpy(o.value[0..n], value[0..n]);
            o.value_len = n;
            found = true;
            break;
        }
        if (!found) return false;
        if (self.isReady()) {
            var buf: [256]u8 = undefined;
            const cmd = uci.setOptionCmd(&buf, name, value) catch return true;
            self.send(log, cmd);
        }
        return true;
    }

    fn sendConfiguredOptions(self: *Engine, log: *Log) void {
        var buf: [256]u8 = undefined;
        for (self.options[0..self.option_count]) |*o| {
            if (o.kind == .button) continue;
            if (o.isDefault()) continue;
            const cmd = uci.setOptionCmd(&buf, o.nameSlice(), o.valueSlice()) catch continue;
            self.send(log, cmd);
        }
    }

    pub fn stopSearch(self: *Engine, log: *Log) void {
        if (!self.searching) return;
        self.send(log, "stop");
    }

    pub fn go(
        self: *Engine,
        log: *Log,
        start_fen: ?[]const u8,
        moves: []const Move,
        state: *const GameState,
        limits: uci.Limits,
    ) void {
        if (!self.isReady() or self.searching) return;

        self.search_root = state.*;
        self.have_root = true;
        self.resetSearch();
        self.has_best = false;

        var buf: [4096]u8 = undefined;
        const pcmd = uci.positionCmd(&buf, start_fen, moves) catch {
            log.print(self.nameSlice(), .err, "move list too long for one command", .{});
            return;
        };
        self.send(log, pcmd);

        var gbuf: [160]u8 = undefined;
        const gcmd = uci.goCmd(&gbuf, limits) catch return;
        self.send(log, gcmd);

        self.searching = true;
        self.status = .thinking;
    }

    pub fn resetSearch(self: *Engine) void {
        for (&self.pv) |*p| p.valid = false;
        self.pv_count = 0;
        self.depth = 0;
        self.nodes = 0;
        self.nps = 0;
        self.hashfull = 0;
        self.time_ms = 0;
    }

    pub fn takeBestMove(self: *Engine, gs: *GameState) ?Move {
        if (!self.has_best) return null;
        self.has_best = false;
        const text = self.best_uci[0..self.best_len];
        if (std.mem.eql(u8, text, "(none)") or text.len < 4) return null;
        return (chess.san.fromUci(gs, text) catch null) orelse null;
    }

    pub fn bestMoveText(self: *const Engine) []const u8 {
        return self.best_uci[0..self.best_len];
    }

    pub fn poll(self: *Engine, log: *Log) void {
        const p = self.proc orelse return;

        var buf: [process.max_line]u8 = undefined;
        var budget: usize = 512;
        while (budget > 0) : (budget -= 1) {
            const line = p.next(&buf) orelse break;
            self.handle(log, line);
        }

        const dropped = p.takeDropped();
        if (dropped > 0) {
            log.print(self.nameSlice(), .err, "dropped {d} lines (GUI too slow)", .{dropped});
        }

        if (p.writeFailed() or (!p.isAlive() and self.status != .failed)) {
            self.status = .failed;
            self.setError("engine process exited");
            self.searching = false;
            log.print(self.nameSlice(), .err, "process exited", .{});
        }
    }

    fn handle(self: *Engine, log: *Log, line: []const u8) void {
        const msg = uci.parse(line);

        if (self.trace and msg != .info) log.add(self.nameSlice(), .in, line);

        switch (msg) {
            .id_name => |n| self.setName(n),
            .id_author => |a| {
                const n = @min(a.len, max_name);
                @memcpy(self.author[0..n], a[0..n]);
                self.author_len = n;
            },
            .option => |decl| self.addOption(decl),
            .uciok => {
                self.got_uciok = true;
                self.status = .ready;
                self.sendConfiguredOptions(log);
                self.isReadySync(log);
            },
            .readyok => {
                if (self.pending_ready > 0) self.pending_ready -= 1;
                if (self.status == .starting) self.status = .ready;
            },
            .bestmove => |bm| {
                const n = @min(bm.move.len, self.best_uci.len);
                @memcpy(self.best_uci[0..n], bm.move[0..n]);
                self.best_len = n;
                self.has_best = true;
                self.searching = false;
                if (self.status == .thinking) self.status = .ready;
            },
            .info => |info| self.applyInfo(info),
            .copyprotection, .registration => {},
            .text, .unknown, .none => {},
        }
    }

    fn addOption(self: *Engine, decl: uci.OptionDecl) void {
        if (self.option_count >= max_options) return;
        const o = &self.options[self.option_count];
        o.* = .{};

        const nn: u8 = @intCast(@min(decl.name.len, max_opt_name));
        @memcpy(o.name[0..nn], decl.name[0..nn]);
        o.name_len = nn;

        const dn: u8 = @intCast(@min(decl.default.len, max_opt_value));
        @memcpy(o.default[0..dn], decl.default[0..dn]);
        o.default_len = dn;
        @memcpy(o.value[0..dn], decl.default[0..dn]);
        o.value_len = dn;

        o.kind = decl.kind;
        o.min = decl.min;
        o.max = decl.max;

        self.option_count += 1;
    }

    fn applyInfo(self: *Engine, info: uci.Info) void {
        if (info.string != null) return;

        if (info.depth) |d| self.depth = d;
        if (info.nodes) |n| self.nodes = n;
        if (info.nps) |n| self.nps = n;
        if (info.hashfull) |h| self.hashfull = h;
        if (info.time_ms) |t| self.time_ms = t;

        const pv_text = info.pv orelse return;
        if (info.lowerbound or info.upperbound) return;

        const slot = info.multipv;
        if (slot == 0 or slot > max_multipv) return;
        const line = &self.pv[slot - 1];

        const changed = !std.mem.eql(u8, line.uciSlice(), pv_text);

        const n: u16 = @intCast(@min(pv_text.len, max_pv_text));
        @memcpy(line.text[0..n], pv_text[0..n]);
        line.text_len = n;

        if (info.depth) |d| line.depth = d;
        if (info.seldepth) |d| line.seldepth = d;
        if (info.score) |s| line.score = s;
        if (info.nodes) |v| line.nodes = v;
        if (info.nps) |v| line.nps = v;
        if (info.time_ms) |v| line.time_ms = v;
        line.valid = true;

        if (changed and self.have_root) {
            const detail = chess.san.pvDetail(&self.search_root, line.uciSlice(), &line.san, 24);
            line.san_len = @intCast(detail.san.len);
            line.end_position = detail.end;
            line.end_move = detail.last;
            line.has_end = detail.plies > 0;
        }

        if (slot > self.pv_count) self.pv_count = slot;
    }

    pub fn seldepthOf(self: *const Engine) u32 {
        if (self.pv_count == 0 or !self.pv[0].valid) return 0;
        return self.pv[0].seldepth;
    }

    pub fn whitePovScore(self: *const Engine) ?uci.Score {
        if (self.pv_count == 0 or !self.pv[0].valid) return null;
        const s = self.pv[0].score orelse return null;
        if (!self.have_root) return s;
        return if (self.search_root.to_move == .White) s else s.negate();
    }
};
