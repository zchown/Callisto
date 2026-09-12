const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const game_mod = @import("game.zig");
const match_mod = @import("match.zig");
const manager_mod = @import("engine/manager.zig");
const log_mod = @import("log.zig");
const theme_mod = @import("ui/theme.zig");
const widget = @import("ui/widget.zig");
const piece_set_mod = @import("ui/piece_set.zig");

const Game = game_mod.Game;
const Match = match_mod.Match;
const Manager = manager_mod.Manager;
const Log = log_mod.Log;
const Theme = theme_mod.Theme;
const Square = chess.Square;

pub const ui_config_file = "callisto_ui.txt";

pub const default_piece_set: []const u8 = "caliente";

pub const max_tabs = 8;
pub const max_view_id = 24;

pub const Tab = struct {
    game: Game = undefined,
    name: [40]u8 = undefined,
    name_len: usize = 0,
    used: bool = false,

    pub fn nameSlice(self: *const Tab) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    theme: Theme = theme_mod.default,

    view_id: [max_view_id]u8 = undefined,
    view_id_len: usize = 0,

    tabs: [max_tabs]Tab = @splat(.{}),
    tab_count: usize = 0,
    active_tab: usize = 0,
    sidebar_collapsed: bool = false,

    piece_library: piece_set_mod.Library = .{},
    piece_pref_set: bool = false,
    game: Game = undefined,
    match: Match = undefined,
    engines: Manager = undefined,
    log: Log = undefined,

    flipped: bool = false,
    show_help: bool = false,
    help_armed: bool = false,
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

        self.piece_library = .{};
        self.piece_library.discover(allocator);
        self.loadUiConfig();
        self.applyDefaultPieceSet(default_piece_set);

        self.setView("home");
        self.tabs[0] = .{ .used = true };
        self.setTabName(0, "Game 1");
        self.tab_count = 1;
        self.active_tab = 0;

        self.setStatus("ready", .{});
        self.log.add("callisto", .note, "started");
        return self;
    }

    pub fn destroy(self: *App) void {
        self.theme.pieces = null;
        self.piece_library.unload();
        self.engines.deinit(&self.log);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn setPieceSet(self: *App, name: []const u8) bool {
        self.piece_library.select(name) catch |err| {
            self.setStatus("piece set '{s}': {s}", .{ name, @errorName(err) });
            return false;
        };
        self.theme.pieces = self.piece_library.current();
        self.piece_pref_set = true;
        self.saveUiConfig();

        if (name.len == 0) {
            self.setStatus("using the built-in pieces", .{});
        } else {
            self.setStatus("piece set: {s}", .{name});
        }
        return true;
    }

    pub fn applyDefaultPieceSet(self: *App, name: []const u8) void {
        if (self.piece_pref_set) return;
        if (name.len == 0) return;

        const wanted = if (std.mem.eql(u8, name, "auto")) blk: {
            if (self.piece_library.count == 0) return;
            break :blk self.piece_library.nameAt(0);
        } else name;

        self.piece_library.select(wanted) catch |err| {
            self.log.print("ui", .err, "default piece set '{s}': {s}", .{ wanted, @errorName(err) });
            return;
        };
        self.theme.pieces = self.piece_library.current();
    }

    pub fn pieceSetName(self: *const App) []const u8 {
        return self.piece_library.currentName();
    }

    pub fn setPieceTint(self: *App, on: bool) void {
        self.theme.piece_tint = on;
        self.saveUiConfig();
    }

    pub fn saveUiConfig(self: *App) void {
        const file = std.fs.cwd().createFile(ui_config_file, .{}) catch return;
        defer file.close();

        var buf: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "piece_set={s}\npiece_tint={d}\n", .{
            self.pieceSetName(),
            @intFromBool(self.theme.piece_tint),
        }) catch return;
        file.writeAll(text) catch {};
    }

    pub fn loadUiConfig(self: *App) void {
        const file = std.fs.cwd().openFile(ui_config_file, .{}) catch return;
        defer file.close();

        var buf: [1024]u8 = undefined;
        const n = file.readAll(&buf) catch return;

        var it = std.mem.splitScalar(u8, buf[0..n], '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = line[0..eq];
            const value = line[eq + 1 ..];

            if (std.mem.eql(u8, key, "piece_set")) {
                self.piece_pref_set = true;
                if (value.len == 0) continue;
                self.piece_library.select(value) catch continue;
                self.theme.pieces = self.piece_library.current();
            } else if (std.mem.eql(u8, key, "piece_tint")) {
                self.theme.piece_tint = value.len > 0 and value[0] == '1';
            }
        }
    }

    pub fn viewId(self: *const App) []const u8 {
        return self.view_id[0..self.view_id_len];
    }

    pub fn setView(self: *App, id: []const u8) void {
        const n = @min(id.len, max_view_id);
        @memcpy(self.view_id[0..n], id[0..n]);
        self.view_id_len = n;
    }

    pub fn viewIs(self: *const App, id: []const u8) bool {
        return std.mem.eql(u8, self.viewId(), id);
    }

    pub fn setTabName(self: *App, index: usize, name: []const u8) void {
        if (index >= max_tabs) return;
        const t = &self.tabs[index];
        const n = @min(name.len, t.name.len);
        @memcpy(t.name[0..n], name[0..n]);
        t.name_len = n;
    }

    pub fn tabName(self: *App, index: usize) []const u8 {
        if (index >= self.tab_count) return "";
        return self.tabs[index].nameSlice();
    }

    pub fn newTab(self: *App) void {
        if (self.match.isRunning()) {
            self.setStatus("finish or abort the match before opening a tab", .{});
            return;
        }
        if (self.tab_count >= max_tabs) {
            self.setStatus("that is as many tabs as fit", .{});
            return;
        }

        self.tabs[self.active_tab].game = self.game;

        const index = self.tab_count;
        self.tabs[index] = .{ .used = true };
        self.tabs[index].game.init();

        var buf: [24]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "Game {d}", .{index + 1}) catch "Game";
        self.setTabName(index, name);

        self.tab_count += 1;
        self.active_tab = index;
        self.game = self.tabs[index].game;

        self.engines.analysis_hash = 0;
        self.fen_synced_revision = std.math.maxInt(u64);
    }

    pub fn selectTab(self: *App, index: usize) void {
        if (index >= self.tab_count or index == self.active_tab) return;
        if (self.match.isRunning()) {
            self.setStatus("a match is running in this tab", .{});
            return;
        }

        self.tabs[self.active_tab].game = self.game;
        self.active_tab = index;
        self.game = self.tabs[index].game;

        self.engines.analysis_hash = 0;
        self.fen_synced_revision = std.math.maxInt(u64);
    }

    pub fn closeTab(self: *App, index: usize) void {
        if (index >= self.tab_count or self.tab_count <= 1) return;
        if (self.match.isRunning()) {
            self.setStatus("finish or abort the match first", .{});
            return;
        }

        self.tabs[self.active_tab].game = self.game;

        var i = index;
        while (i + 1 < self.tab_count) : (i += 1) self.tabs[i] = self.tabs[i + 1];
        self.tabs[self.tab_count - 1] = .{};
        self.tab_count -= 1;

        if (self.active_tab > index) {
            self.active_tab -= 1;
        } else if (self.active_tab == index) {
            self.active_tab = @min(index, self.tab_count - 1);
        }

        self.game = self.tabs[self.active_tab].game;
        self.engines.analysis_hash = 0;
        self.fen_synced_revision = std.math.maxInt(u64);
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

    pub fn loadFenFromClipboard(self: *App) void {
        const text = rl.getClipboardText();
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len < 10) {
            self.setStatus("clipboard does not look like a FEN", .{});
            return;
        }
        self.game.setFen(trimmed) catch |err| {
            self.setStatus("bad FEN in clipboard: {s}", .{@errorName(err)});
            return;
        };
        self.fen_input.set(trimmed);
        self.engines.analysis_hash = 0;
        self.setStatus("position pasted from the clipboard", .{});
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
        self.setView("game");
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
