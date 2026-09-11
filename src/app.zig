const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const game_mod = @import("game.zig");
const match_mod = @import("match.zig");
const manager_mod = @import("engine/manager.zig");
const log_mod = @import("log.zig");
const theme_mod = @import("ui/theme.zig");
const widget = @import("ui/widget.zig");

const Game = game_mod.Game;
const Match = match_mod.Match;
const Manager = manager_mod.Manager;
const Log = log_mod.Log;
const Theme = theme_mod.Theme;
const Square = chess.Square;

pub const View = enum {
    home,
    game,
    analysis,

    pub fn label(self: View) [:0]const u8 {
        return switch (self) {
            .home => "home",
            .game => "game",
            .analysis => "analysis",
        };
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    theme: Theme = theme_mod.default,

    view: View = .home,
    game: Game = undefined,
    match: Match = undefined,
    engines: Manager = undefined,
    log: Log = undefined,

    flipped: bool = false,
    show_help: bool = false,
    show_pv_arrows: bool = true,
    show_legal: bool = true,
    quit_requested: bool = false,

    fen_input: widget.TextInput = .{},
    engine_path_input: widget.TextInput = .{},

    fen_dirty: bool = false,
    fen_synced_revision: u64 = std.math.maxInt(u64),

    status_buf: [160]u8 = undefined,
    status_len: usize = 0,

    pub fn create(allocator: std.mem.Allocator) !*App {
        const self = try allocator.create(App);
        self.* = .{ .allocator = allocator };

        self.game.init();
        self.match.init();
        self.engines.init(allocator);
        self.log.init();
        self.fen_input = widget.TextInput.init(chess.start_position);
        self.engine_path_input = widget.TextInput.init("");

        self.setStatus("ready", .{});
        self.log.add("callisto", .note, "started");
        return self;
    }

    pub fn destroy(self: *App) void {
        self.engines.deinit(&self.log);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn setStatus(self: *App, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(&self.status_buf, fmt, args) catch {
            self.status_len = 0;
            return;
        };
        self.status_len = w.len;
    }

    pub fn statusZ(self: *App) [:0]const u8 {
        const n = @min(self.status_len, self.status_buf.len - 1);
        self.status_buf[n] = 0;
        return self.status_buf[0..n :0];
    }

    pub fn update(self: *App) void {
        widget.keyboard_captured = self.fen_input.focused or self.engine_path_input.focused;

        self.engines.poll(&self.log, &self.game);
        self.match.update(&self.game, &self.engines, &self.log);
        self.syncFenBox();
    }

    fn syncFenBox(self: *App) void {
        if (self.fen_input.focused) return;
        if (self.fen_synced_revision == self.game.revision) return;
        self.fen_synced_revision = self.game.revision;

        const text = self.game.currentFen(self.allocator) catch return;
        defer self.allocator.free(text);
        self.fen_input.set(text);
    }

    pub fn boardInteractive(self: *App) bool {
        if (self.game.preview_active) return false;
        if (self.game.status().isOver()) return false;
        if (!self.game.atEnd() and self.match.isRunning()) return false;
        return self.match.humanMayMove(self.game.sideToMove());
    }

    pub fn tryUserMove(self: *App, from: Square, to: Square, promo: ?chess.Pieces) bool {
        if (!self.boardInteractive()) return false;

        const m = self.game.findMove(from, to, promo) orelse return false;
        self.game.play(m) catch |err| {
            self.setStatus("cannot play move: {s}", .{@errorName(err)});
            return false;
        };

        self.match.onHumanMove(&self.game);
        self.engines.analysis_hash = 0;
        return true;
    }

    pub fn newGame(self: *App, fen_text: []const u8) void {
        if (self.match.isRunning()) self.match.abort(&self.engines, &self.log);

        self.game.setFen(fen_text) catch |err| {
            self.setStatus("bad FEN: {s}", .{@errorName(err)});
            return;
        };
        self.game.setNames("White", "Black");
        self.match.state = .idle;
        self.engines.newGameAll(&self.log);
        self.setStatus("new game", .{});
    }

    pub fn loadFenFromInput(self: *App) void {
        const text = self.fen_input.slice();
        self.game.setFen(text) catch |err| {
            self.setStatus("bad FEN: {s}", .{@errorName(err)});
            return;
        };
        if (self.match.isRunning()) self.match.abort(&self.engines, &self.log);
        self.engines.newGameAll(&self.log);
        self.setStatus("position loaded", .{});
    }

    pub fn copyCurrentFen(self: *App) void {
        const text = self.game.currentFen(self.allocator) catch {
            self.setStatus("could not build FEN", .{});
            return;
        };
        defer self.allocator.free(text);

        var buf: [160]u8 = undefined;
        rl.setClipboardText(widget.zSlice(&buf, text));
        self.setStatus("FEN copied to the clipboard", .{});
    }

    pub fn startMatch(self: *App) void {
        self.match.setStartFen(self.game.rootFen() orelse chess.start_position);
        self.match.start(&self.game, &self.engines, &self.log) catch |err| {
            self.setStatus("cannot start match: {s}", .{@errorName(err)});
            return;
        };
        self.view = .game;
        self.setStatus("match started", .{});
    }

    pub fn toggleAnalysis(self: *App) void {
        const on = !self.engines.analysis_on;
        if (on and self.match.isRunning()) {
            self.setStatus("stop the match before analysing", .{});
            return;
        }
        self.engines.setAnalysis(on, &self.log);
        if (on) {
            self.setStatus("analysis on", .{});
        } else {
            self.setStatus("analysis off", .{});
        }
    }

    pub fn addEngineFromInput(self: *App) void {
        const path = self.engine_path_input.slice();
        _ = self.engines.add(path, &self.log) catch |err| {
            self.setStatus("could not add engine: {s}", .{@errorName(err)});
            return;
        };
        self.engine_path_input.clear();
        self.engines.saveConfig();
        self.setStatus("engine added", .{});
    }

    pub fn addEnginePath(self: *App, path: []const u8) void {
        _ = self.engines.add(path, &self.log) catch |err| {
            self.setStatus("could not add engine: {s}", .{@errorName(err)});
            return;
        };
        self.engines.saveConfig();
        self.setStatus("engine added", .{});
    }
};
