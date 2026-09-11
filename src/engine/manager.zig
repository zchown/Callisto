const std = @import("std");
const chess = @import("chess");
const engine_mod = @import("engine.zig");
const log_mod = @import("../log.zig");
const game_mod = @import("../game.zig");

const Engine = engine_mod.Engine;
const Log = log_mod.Log;
const Game = game_mod.Game;

pub const max_engines = 8;
pub const config_file = "callisto_engines.txt";

pub const Manager = struct {
    allocator: std.mem.Allocator,
    list: [max_engines]Engine = undefined,
    count: usize = 0,
    applied: [max_engines]bool = @splat(false),

    selected: usize = 0,

    analysis_on: bool = false,
    analysis_hash: u64 = 0,
    multipv: i32 = 1,
    hash_mb: i32 = 128,
    threads: i32 = 1,

    pub fn init(self: *Manager, allocator: std.mem.Allocator) void {
        self.* = .{ .allocator = allocator };
        for (&self.list) |*e| e.* = .{};
    }

    pub fn deinit(self: *Manager, log: *Log) void {
        for (self.list[0..self.count]) |*e| {
            if (e.used) e.shutdown(log);
        }
        self.count = 0;
    }

    pub fn get(self: *Manager, idx: usize) ?*Engine {
        if (idx >= self.count) return null;
        if (!self.list[idx].used) return null;
        return &self.list[idx];
    }

    pub fn current(self: *Manager) ?*Engine {
        return self.get(self.selected);
    }

    pub fn slice(self: *Manager) []Engine {
        return self.list[0..self.count];
    }

    pub fn add(self: *Manager, path: []const u8, log: *Log) !usize {
        const trimmed = std.mem.trim(u8, path, " \t\r\n\"");
        if (trimmed.len == 0) return error.EmptyPath;
        if (self.count >= max_engines) return error.TooManyEngines;

        try std.fs.cwd().access(trimmed, .{});

        for (self.list[0..self.count]) |*e| {
            if (std.mem.eql(u8, e.pathSlice(), trimmed)) return error.AlreadyAdded;
        }

        const idx = self.count;
        self.list[idx].configure(idx, trimmed);
        self.applied[idx] = false;
        self.count += 1;
        self.selected = idx;

        self.list[idx].start(self.allocator, log);
        return idx;
    }

    pub fn removeAt(self: *Manager, idx: usize, log: *Log) void {
        if (idx >= self.count) return;
        self.list[idx].shutdown(log);

        var i = idx;
        while (i + 1 < self.count) : (i += 1) {
            self.list[i] = self.list[i + 1];
            self.list[i].id = i;
            self.applied[i] = self.applied[i + 1];
        }
        self.list[self.count - 1] = .{};
        self.count -= 1;
        if (self.selected >= self.count) self.selected = if (self.count == 0) 0 else self.count - 1;
    }

    pub fn restart(self: *Manager, idx: usize, log: *Log) void {
        const e = self.get(idx) orelse return;
        e.shutdown(log);
        self.applied[idx] = false;
        e.start(self.allocator, log);
    }

    pub fn stopAll(self: *Manager, log: *Log) void {
        for (self.list[0..self.count]) |*e| {
            if (e.searching) e.stopSearch(log);
        }
        self.analysis_on = false;
    }

    pub fn newGameAll(self: *Manager, log: *Log) void {
        for (self.list[0..self.count]) |*e| {
            if (e.isReady()) e.newGame(log);
        }
        self.analysis_hash = 0;
    }

    pub fn setAnalysisEngine(self: *Manager, idx: usize, on: bool, log: *Log) void {
        const e = self.get(idx) orelse return;
        if (e.owner == .match) return;
        if (on) {
            e.owner = .analysis;
            self.analysis_hash = 0;
        } else {
            e.owner = .none;
            if (e.searching) e.stopSearch(log);
        }
    }

    pub fn analysisEngineCount(self: *Manager) usize {
        var n: usize = 0;
        for (self.list[0..self.count]) |*e| {
            if (e.owner == .analysis) n += 1;
        }
        return n;
    }

    pub fn setAnalysis(self: *Manager, on: bool, log: *Log) void {
        self.analysis_on = on;
        self.analysis_hash = 0;
        if (!on) {
            for (self.list[0..self.count]) |*e| {
                if (e.owner == .analysis and e.searching) e.stopSearch(log);
            }
        } else if (self.analysisEngineCount() == 0) {
            for (self.list[0..self.count], 0..) |*e, i| {
                if (e.isReady()) {
                    self.setAnalysisEngine(i, true, log);
                    break;
                }
            }
        }
    }

    pub fn poll(self: *Manager, log: *Log, game: *Game) void {
        for (self.list[0..self.count], 0..) |*e, i| {
            if (!e.used) continue;
            e.poll(log);

            if (e.got_uciok and !self.applied[i]) {
                self.applied[i] = true;
                self.applyCommonOptions(e, log);
            }
        }
        self.updateAnalysis(log, game);
    }

    fn applyCommonOptions(self: *Manager, e: *Engine, log: *Log) void {
        var buf: [24]u8 = undefined;
        _ = e.setOptionByName(log, "Hash", std.fmt.bufPrint(&buf, "{d}", .{self.hash_mb}) catch "128");
        var buf2: [24]u8 = undefined;
        _ = e.setOptionByName(log, "Threads", std.fmt.bufPrint(&buf2, "{d}", .{self.threads}) catch "1");
        _ = e.setOptionByName(log, "Ponder", "false");
        self.pushMultiPv(e, log);
    }

    fn pushMultiPv(self: *Manager, e: *Engine, log: *Log) void {
        var buf: [16]u8 = undefined;
        const n = std.math.clamp(self.multipv, 1, engine_mod.max_multipv);
        _ = e.setOptionByName(log, "MultiPV", std.fmt.bufPrint(&buf, "{d}", .{n}) catch "1");
    }

    pub fn setMultiPv(self: *Manager, n: i32, log: *Log) void {
        self.multipv = std.math.clamp(n, 1, engine_mod.max_multipv);
        for (self.list[0..self.count]) |*e| {
            if (!e.isReady()) continue;
            if (e.searching) e.stopSearch(log);
            self.pushMultiPv(e, log);
        }
        self.analysis_hash = 0;
    }

    fn updateAnalysis(self: *Manager, log: *Log, game: *Game) void {
        if (!self.analysis_on) return;

        const hash = game.displayState().cur_position.hash;
        if (hash != self.analysis_hash) {
            for (self.list[0..self.count]) |*e| {
                if (e.owner == .analysis and e.searching) e.stopSearch(log);
            }
            self.analysis_hash = hash;
        }

        for (self.list[0..self.count]) |*e| {
            if (e.owner != .analysis) continue;
            if (!e.isReady() or e.searching or e.pending_ready > 0) continue;

            if (game.status() != .ongoing) continue;

            e.go(
                log,
                game.rootFen(),
                game.movesToCursor(),
                game.displayState(),
                .{ .infinite = true },
            );
        }
    }

    pub fn saveConfig(self: *Manager) void {
        const file = std.fs.cwd().createFile(config_file, .{}) catch return;
        defer file.close();
        for (self.list[0..self.count]) |*e| {
            file.writeAll(e.pathSlice()) catch return;
            file.writeAll("\n") catch return;
        }
    }

    pub fn loadConfig(self: *Manager, log: *Log) void {
        const file = std.fs.cwd().openFile(config_file, .{}) catch return;
        defer file.close();

        var buf: [8192]u8 = undefined;
        const n = file.readAll(&buf) catch return;

        var it = std.mem.splitScalar(u8, buf[0..n], '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r\n");
            if (line.len == 0 or line[0] == '#') continue;
            _ = self.add(line, log) catch |err| {
                log.print("engines", .err, "skipping {s}: {s}", .{ line, @errorName(err) });
                continue;
            };
        }
    }
};
