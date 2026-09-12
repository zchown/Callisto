const std = @import("std");
const rl = @import("raylib");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const chess = @import("chess");

const App = @import("../app.zig").App;
const vm_mod = @import("vm.zig");
const Vm = vm_mod.Vm;
const ui_mod = @import("../ui/ui.zig");
const Ui = ui_mod.Ui;
const widget = @import("../ui/widget.zig");
const match_mod = @import("../match.zig");
const engine_mod = @import("../engine/engine.zig");

pub const api_version: i64 = 1;

var vm_ptr: ?*Vm = null;
var ui_ptr: ?*Ui = null;

fn vm() *Vm {
    return vm_ptr.?;
}

fn app() *App {
    return vm_ptr.?.app;
}

fn currentUi(lua: *Lua) *Ui {
    return ui_ptr orelse lua.raiseErrorStr("ui functions can only be called while a panel is drawing", .{});
}

/// Set by the VM around a panel draw so `ui.*` knows where to draw.
pub fn beginPanelDraw(ui: *Ui) void {
    ui_ptr = ui;
}

pub fn endPanelDraw() void {
    ui_ptr = null;
}

// ---------------------------------------------------------------------------
// ui
// ---------------------------------------------------------------------------

fn uiText(lua: *Lua) i32 {
    currentUi(lua).text(lua.checkString(1));
    return 0;
}

fn uiDim(lua: *Lua) i32 {
    currentUi(lua).dim(lua.checkString(1));
    return 0;
}

fn uiHeading(lua: *Lua) i32 {
    currentUi(lua).heading(lua.checkString(1));
    return 0;
}

fn uiLabel(lua: *Lua) i32 {
    const tone = if (lua.optString(3)) |s| ui_mod.Tone.parse(s) else .normal;
    currentUi(lua).label(lua.checkString(1), lua.checkString(2), tone);
    return 0;
}

fn uiSeparator(lua: *Lua) i32 {
    currentUi(lua).separator();
    return 0;
}

fn uiSpacing(lua: *Lua) i32 {
    const px: f32 = @floatCast(lua.optNumber(1) orelse 6);
    currentUi(lua).spacing(px);
    return 0;
}

fn styleFrom(name: ?[]const u8) widget.Style {
    const s = name orelse return .normal;
    if (std.mem.eql(u8, s, "primary")) return .primary;
    if (std.mem.eql(u8, s, "danger")) return .danger;
    if (std.mem.eql(u8, s, "ghost")) return .ghost;
    return .normal;
}

fn uiButton(lua: *Lua) i32 {
    const clicked = currentUi(lua).button(lua.checkString(1), styleFrom(lua.optString(2)));
    lua.pushBoolean(clicked);
    return 1;
}

fn uiCheckbox(lua: *Lua) i32 {
    const res = currentUi(lua).checkbox(lua.checkString(1), lua.toBoolean(2));
    lua.pushBoolean(res.value);
    lua.pushBoolean(res.changed);
    return 2;
}

fn uiSlider(lua: *Lua) i32 {
    const res = currentUi(lua).slider(
        lua.checkString(1),
        @floatCast(lua.checkNumber(2)),
        @floatCast(lua.optNumber(3) orelse 0),
        @floatCast(lua.optNumber(4) orelse 100),
    );
    lua.pushNumber(res.value);
    lua.pushBoolean(res.changed);
    return 2;
}

fn uiInput(lua: *Lua) i32 {
    const res = currentUi(lua).input(
        lua.checkString(1),
        lua.optString(2) orelse "",
        lua.optString(3) orelse "",
    );
    _ = lua.pushString(res.value);
    lua.pushBoolean(res.submitted);
    return 2;
}

fn uiBadge(lua: *Lua) i32 {
    const tone = if (lua.optString(2)) |s| ui_mod.Tone.parse(s) else .accent;
    currentUi(lua).badge(lua.checkString(1), tone);
    return 0;
}

fn uiProgress(lua: *Lua) i32 {
    const tone = if (lua.optString(2)) |s| ui_mod.Tone.parse(s) else .accent;
    currentUi(lua).progressBar(@floatCast(lua.checkNumber(1)), tone);
    return 0;
}

fn uiBeginRow(lua: *Lua) i32 {
    currentUi(lua).beginRow(@floatCast(lua.optNumber(1) orelse 0));
    return 0;
}

fn uiEndRow(lua: *Lua) i32 {
    currentUi(lua).endRow();
    return 0;
}

fn uiWidth(lua: *Lua) i32 {
    currentUi(lua).setWidth(@floatCast(lua.checkNumber(1)));
    return 0;
}

fn uiIndent(lua: *Lua) i32 {
    currentUi(lua).indent = @floatCast(lua.optNumber(1) orelse 12);
    return 0;
}

fn uiAvailableWidth(lua: *Lua) i32 {
    lua.pushNumber(currentUi(lua).remainingWidth());
    return 1;
}

fn uiAvailableHeight(lua: *Lua) i32 {
    const ui = currentUi(lua);
    lua.pushNumber(@max(ui.area.height - ui.used, 0));
    return 1;
}

fn uiMoveList(lua: *Lua) i32 {
    const rows: usize = @intCast(@max(lua.optInteger(1) orelse 200, 1));
    currentUi(lua).moveList(rows);
    return 0;
}

fn uiEngineLines(lua: *Lua) i32 {
    const n: usize = @intCast(@max(lua.optInteger(1) orelse 4, 1));
    currentUi(lua).engineLines(n);
    return 0;
}

fn uiEvalBar(lua: *Lua) i32 {
    currentUi(lua).evalBar(@floatCast(lua.optNumber(1) orelse 12));
    return 0;
}

fn uiClocks(lua: *Lua) i32 {
    currentUi(lua).clocks();
    return 0;
}

/// ui.register_panel(name, title, draw_fn)
fn uiRegisterPanel(lua: *Lua) !i32 {
    const name = lua.checkString(1);
    const title = lua.checkString(2);
    lua.checkType(3, .function);

    lua.pushValue(3);
    const ref = try lua.ref(zlua.registry_index);

    if (vm().registerPanel(name, title, ref) == null) {
        lua.unref(zlua.registry_index, ref);
        lua.raiseErrorStr("too many Lua panels", .{});
    }
    return 0;
}

/// ui.set_view(name, spec)
fn uiSetView(lua: *Lua) !i32 {
    const name = lua.checkString(1);
    lua.checkType(2, .table);
    const v = vm();

    if (v.views_ref == vm_mod.no_ref) {
        lua.newTable();
        v.views_ref = try lua.ref(zlua.registry_index);
    }

    _ = lua.rawGetIndex(zlua.registry_index, v.views_ref);
    lua.pushValue(2);
    lua.setField(-2, name);
    lua.pop(1);

    v.views_dirty = true;
    return 0;
}

const ui_fns = [_]zlua.FnReg{
    .{ .name = "text", .func = zlua.wrap(uiText) },
    .{ .name = "dim", .func = zlua.wrap(uiDim) },
    .{ .name = "heading", .func = zlua.wrap(uiHeading) },
    .{ .name = "label", .func = zlua.wrap(uiLabel) },
    .{ .name = "separator", .func = zlua.wrap(uiSeparator) },
    .{ .name = "spacing", .func = zlua.wrap(uiSpacing) },
    .{ .name = "button", .func = zlua.wrap(uiButton) },
    .{ .name = "checkbox", .func = zlua.wrap(uiCheckbox) },
    .{ .name = "slider", .func = zlua.wrap(uiSlider) },
    .{ .name = "input", .func = zlua.wrap(uiInput) },
    .{ .name = "badge", .func = zlua.wrap(uiBadge) },
    .{ .name = "progress", .func = zlua.wrap(uiProgress) },
    .{ .name = "begin_row", .func = zlua.wrap(uiBeginRow) },
    .{ .name = "end_row", .func = zlua.wrap(uiEndRow) },
    .{ .name = "width", .func = zlua.wrap(uiWidth) },
    .{ .name = "indent", .func = zlua.wrap(uiIndent) },
    .{ .name = "available_width", .func = zlua.wrap(uiAvailableWidth) },
    .{ .name = "available_height", .func = zlua.wrap(uiAvailableHeight) },
    .{ .name = "move_list", .func = zlua.wrap(uiMoveList) },
    .{ .name = "engine_lines", .func = zlua.wrap(uiEngineLines) },
    .{ .name = "eval_bar", .func = zlua.wrap(uiEvalBar) },
    .{ .name = "clocks", .func = zlua.wrap(uiClocks) },
    .{ .name = "register_panel", .func = zlua.wrap(uiRegisterPanel) },
    .{ .name = "set_view", .func = zlua.wrap(uiSetView) },
};

// ---------------------------------------------------------------------------
// chess
// ---------------------------------------------------------------------------

fn chessFen(lua: *Lua) i32 {
    const a = app();
    const text = a.game.currentFen(a.allocator) catch {
        _ = lua.pushString("");
        return 1;
    };
    defer a.allocator.free(text);
    _ = lua.pushString(text);
    return 1;
}

fn chessSideToMove(lua: *Lua) i32 {
    _ = lua.pushString(if (app().game.sideToMove() == .White) "white" else "black");
    return 1;
}

fn chessMakeMove(lua: *Lua) i32 {
    const text = lua.checkString(1);
    const a = app();

    // Routed through the app, not the game, so match clocks and the
    // "is it your turn" check are not bypassed.
    if (text.len < 4) {
        lua.pushBoolean(false);
        return 1;
    }
    const from = chess.utils.squareFromString(text[0..2]);
    const to = chess.utils.squareFromString(text[2..4]);
    if (from == null or to == null) {
        lua.pushBoolean(false);
        return 1;
    }

    var promo: ?chess.Pieces = null;
    if (text.len >= 5) {
        promo = switch (text[4]) {
            'n' => .Knight,
            'b' => .Bishop,
            'r' => .Rook,
            'q' => .Queen,
            else => null,
        };
    }

    lua.pushBoolean(a.tryUserMove(from.?, to.?, promo));
    return 1;
}

fn chessUndo(lua: *Lua) i32 {
    _ = lua;
    app().game.back();
    return 0;
}

fn chessRedo(lua: *Lua) i32 {
    _ = lua;
    app().game.forward();
    return 0;
}

fn chessGoto(lua: *Lua) i32 {
    const n = lua.checkInteger(1);
    app().game.goto(@intCast(@max(n, 0)));
    return 0;
}

fn chessToStart(lua: *Lua) i32 {
    _ = lua;
    app().game.toStart();
    return 0;
}

fn chessToEnd(lua: *Lua) i32 {
    _ = lua;
    app().game.toEnd();
    return 0;
}

fn chessPly(lua: *Lua) i32 {
    lua.pushInteger(@intCast(app().game.cursor));
    return 1;
}

fn chessMoveCount(lua: *Lua) i32 {
    lua.pushInteger(@intCast(app().game.count));
    return 1;
}

fn chessMoves(lua: *Lua) i32 {
    const g = &app().game;
    lua.createTable(@intCast(g.count), 0);
    for (0..g.count) |i| {
        const ply = g.plyAt(i) orelse continue;
        _ = lua.pushString(ply.sanSlice());
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn chessLegalMoves(lua: *Lua) i32 {
    const g = &app().game;
    var list = chess.MoveList.empty;
    g.legal(&list);

    lua.createTable(@intCast(list.len), 0);
    var buf: [8]u8 = undefined;
    for (list.slice(), 0..) |m, i| {
        _ = lua.pushString(m.toUci(&buf));
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn chessNewGame(lua: *Lua) i32 {
    app().newGame(lua.optString(1) orelse chess.start_position);
    return 0;
}

fn chessSetFen(lua: *Lua) i32 {
    const a = app();
    a.game.setFen(lua.checkString(1)) catch {
        lua.pushBoolean(false);
        return 1;
    };
    a.engines.analysis_hash = 0;
    lua.pushBoolean(true);
    return 1;
}

fn chessFlipBoard(lua: *Lua) i32 {
    _ = lua;
    const a = app();
    a.flipped = !a.flipped;
    return 0;
}

fn chessIsFlipped(lua: *Lua) i32 {
    lua.pushBoolean(app().flipped);
    return 1;
}

fn chessStatus(lua: *Lua) i32 {
    _ = lua.pushString(app().game.status().label());
    return 1;
}

fn chessInCheck(lua: *Lua) i32 {
    lua.pushBoolean(app().game.inCheck());
    return 1;
}

fn chessLastMove(lua: *Lua) i32 {
    const g = &app().game;
    const m = g.lastMove() orelse {
        lua.pushNil();
        return 1;
    };
    var buf: [8]u8 = undefined;
    _ = lua.pushString(m.toUci(&buf));
    return 1;
}

const chess_fns = [_]zlua.FnReg{
    .{ .name = "fen", .func = zlua.wrap(chessFen) },
    .{ .name = "side_to_move", .func = zlua.wrap(chessSideToMove) },
    .{ .name = "make_move", .func = zlua.wrap(chessMakeMove) },
    .{ .name = "undo", .func = zlua.wrap(chessUndo) },
    .{ .name = "redo", .func = zlua.wrap(chessRedo) },
    .{ .name = "goto_ply", .func = zlua.wrap(chessGoto) },
    .{ .name = "to_start", .func = zlua.wrap(chessToStart) },
    .{ .name = "to_end", .func = zlua.wrap(chessToEnd) },
    .{ .name = "ply", .func = zlua.wrap(chessPly) },
    .{ .name = "move_count", .func = zlua.wrap(chessMoveCount) },
    .{ .name = "moves", .func = zlua.wrap(chessMoves) },
    .{ .name = "legal_moves", .func = zlua.wrap(chessLegalMoves) },
    .{ .name = "new_game", .func = zlua.wrap(chessNewGame) },
    .{ .name = "set_fen", .func = zlua.wrap(chessSetFen) },
    .{ .name = "flip_board", .func = zlua.wrap(chessFlipBoard) },
    .{ .name = "is_flipped", .func = zlua.wrap(chessIsFlipped) },
    .{ .name = "status", .func = zlua.wrap(chessStatus) },
    .{ .name = "in_check", .func = zlua.wrap(chessInCheck) },
    .{ .name = "last_move", .func = zlua.wrap(chessLastMove) },
};

// ---------------------------------------------------------------------------
// engine
// ---------------------------------------------------------------------------

/// Lua indices are 1-based. With no argument, prefer the first analysis engine
/// and fall back to the selected one.
fn engineAt(lua: *Lua, arg: i32) ?*engine_mod.Engine {
    const a = app();
    if (lua.optInteger(arg)) |n| {
        if (n < 1) return null;
        return a.engines.get(@intCast(n - 1));
    }
    for (a.engines.slice()) |*e| {
        if (e.owner == .analysis) return e;
    }
    return a.engines.current();
}

fn engineCount(lua: *Lua) i32 {
    lua.pushInteger(@intCast(app().engines.count));
    return 1;
}

fn engineList(lua: *Lua) i32 {
    const a = app();
    lua.createTable(@intCast(a.engines.count), 0);

    for (a.engines.slice(), 0..) |*e, i| {
        lua.createTable(0, 5);

        _ = lua.pushString(e.nameSlice());
        lua.setField(-2, "name");
        _ = lua.pushString(e.pathSlice());
        lua.setField(-2, "path");
        _ = lua.pushString(e.status.label());
        lua.setField(-2, "status");
        lua.pushBoolean(e.owner == .analysis);
        lua.setField(-2, "analysing");
        lua.pushInteger(@intCast(i + 1));
        lua.setField(-2, "index");

        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn engineAdd(lua: *Lua) i32 {
    app().addEnginePath(lua.checkString(1));
    lua.pushInteger(@intCast(app().engines.count));
    return 1;
}

fn engineRemove(lua: *Lua) i32 {
    const n = lua.checkInteger(1);
    if (n >= 1) {
        const a = app();
        a.engines.removeAt(@intCast(n - 1), &a.log);
        a.engines.saveConfig();
    }
    return 0;
}

fn engineRestart(lua: *Lua) i32 {
    const n = lua.checkInteger(1);
    if (n >= 1) {
        const a = app();
        a.engines.restart(@intCast(n - 1), &a.log);
    }
    return 0;
}

fn engineName(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    _ = lua.pushString(e.nameSlice());
    return 1;
}

fn engineStatus(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        _ = lua.pushString("offline");
        return 1;
    };
    _ = lua.pushString(e.status.label());
    return 1;
}

fn engineDepth(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        lua.pushInteger(0);
        return 1;
    };
    lua.pushInteger(@intCast(e.depth));
    return 1;
}

fn engineNodes(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        lua.pushInteger(0);
        return 1;
    };
    lua.pushInteger(@intCast(@min(e.nodes, std.math.maxInt(i64))));
    return 1;
}

fn engineNps(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        lua.pushInteger(0);
        return 1;
    };
    lua.pushInteger(@intCast(@min(e.nps, std.math.maxInt(i64))));
    return 1;
}

/// Centipawns from white's point of view, or nil when there is no score.
fn engineScore(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const s = e.whitePovScore() orelse {
        lua.pushNil();
        return 1;
    };
    switch (s) {
        .cp => |v| {
            lua.pushNumber(@as(f64, @floatFromInt(v)) / 100.0);
            _ = lua.pushString("cp");
        },
        .mate => |v| {
            lua.pushInteger(@intCast(v));
            _ = lua.pushString("mate");
        },
    }
    return 2;
}

fn engineScoreText(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        _ = lua.pushString("");
        return 1;
    };
    const s = e.whitePovScore() orelse {
        _ = lua.pushString("");
        return 1;
    };
    var buf: [16]u8 = undefined;
    _ = lua.pushString(s.format(&buf));
    return 1;
}

/// engine.pv([index], [line]) -> san text
fn enginePv(lua: *Lua) i32 {
    const e = engineAt(lua, 1) orelse {
        _ = lua.pushString("");
        return 1;
    };
    const line: usize = @intCast(@max(lua.optInteger(2) orelse 1, 1));
    if (line > e.pv_count or !e.pv[line - 1].valid) {
        _ = lua.pushString("");
        return 1;
    }
    const pv = &e.pv[line - 1];
    _ = lua.pushString(if (pv.san_len > 0) pv.sanSlice() else pv.uciSlice());
    return 1;
}

fn engineSetOption(lua: *Lua) i32 {
    const n = lua.checkInteger(1);
    const a = app();
    const e = a.engines.get(@intCast(@max(n - 1, 0))) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(e.setOptionByName(&a.log, lua.checkString(2), lua.checkString(3)));
    return 1;
}

fn engineSetAnalysis(lua: *Lua) i32 {
    const a = app();
    const on = lua.toBoolean(1);
    if (on and a.match.isRunning()) {
        lua.pushBoolean(false);
        return 1;
    }
    a.engines.setAnalysis(on, &a.log);
    lua.pushBoolean(true);
    return 1;
}

fn engineAnalysing(lua: *Lua) i32 {
    lua.pushBoolean(app().engines.analysis_on);
    return 1;
}

fn engineSetMultiPv(lua: *Lua) i32 {
    const a = app();
    a.engines.setMultiPv(@intCast(lua.checkInteger(1)), &a.log);
    return 0;
}

fn engineStop(lua: *Lua) i32 {
    const a = app();
    _ = lua;
    a.engines.stopAll(&a.log);
    return 0;
}

const engine_fns = [_]zlua.FnReg{
    .{ .name = "count", .func = zlua.wrap(engineCount) },
    .{ .name = "list", .func = zlua.wrap(engineList) },
    .{ .name = "add", .func = zlua.wrap(engineAdd) },
    .{ .name = "remove", .func = zlua.wrap(engineRemove) },
    .{ .name = "restart", .func = zlua.wrap(engineRestart) },
    .{ .name = "name", .func = zlua.wrap(engineName) },
    .{ .name = "status", .func = zlua.wrap(engineStatus) },
    .{ .name = "depth", .func = zlua.wrap(engineDepth) },
    .{ .name = "nodes", .func = zlua.wrap(engineNodes) },
    .{ .name = "nps", .func = zlua.wrap(engineNps) },
    .{ .name = "score", .func = zlua.wrap(engineScore) },
    .{ .name = "score_text", .func = zlua.wrap(engineScoreText) },
    .{ .name = "pv", .func = zlua.wrap(enginePv) },
    .{ .name = "set_option", .func = zlua.wrap(engineSetOption) },
    .{ .name = "set_analysis", .func = zlua.wrap(engineSetAnalysis) },
    .{ .name = "analysing", .func = zlua.wrap(engineAnalysing) },
    .{ .name = "set_multipv", .func = zlua.wrap(engineSetMultiPv) },
    .{ .name = "stop", .func = zlua.wrap(engineStop) },
};

// ---------------------------------------------------------------------------
// match
// ---------------------------------------------------------------------------

fn matchState(lua: *Lua) i32 {
    _ = lua.pushString(switch (app().match.state) {
        .idle => "idle",
        .playing => "playing",
        .between => "between",
        .finished => "finished",
    });
    return 1;
}

fn matchStart(lua: *Lua) i32 {
    _ = lua;
    app().startMatch();
    return 0;
}

fn matchAbort(lua: *Lua) i32 {
    _ = lua;
    const a = app();
    a.match.abort(&a.engines, &a.log);
    return 0;
}

fn matchScore(lua: *Lua) i32 {
    const m = &app().match;
    lua.pushInteger(@intCast(m.p1_wins));
    lua.pushInteger(@intCast(m.p2_wins));
    lua.pushInteger(@intCast(m.draws));
    return 3;
}

fn matchClock(lua: *Lua) i32 {
    const a = app();
    const side_name = lua.checkString(1);
    const side: chess.Color = if (std.mem.eql(u8, side_name, "black")) .Black else .White;
    lua.pushInteger(@intCast(a.match.remaining(side, a.game.sideToMove())));
    return 1;
}

/// match.set_player("white", "human" | engine_index)
fn matchSetPlayer(lua: *Lua) i32 {
    const m = &app().match;
    const side_name = lua.checkString(1);
    const is_white = !std.mem.eql(u8, side_name, "black");

    var player = match_mod.Player{ .kind = .human };
    if (lua.typeOf(2) == .number) {
        const n = lua.checkInteger(2);
        if (n >= 1) player = .{ .kind = .engine, .engine = @intCast(n - 1) };
    }

    if (is_white) m.white = player else m.black = player;
    return 0;
}

/// match.set_time(kind, a, b) - seconds for clock kinds, ms/depth/nodes
/// otherwise.
fn matchSetTime(lua: *Lua) i32 {
    const m = &app().match;
    const kind = lua.checkString(1);
    const first = lua.optNumber(2) orelse 180;
    const second = lua.optNumber(3) orelse 2;

    if (std.mem.eql(u8, kind, "increment")) {
        m.tc.kind = .increment;
        m.tc.base_ms = @intFromFloat(first * 1000);
        m.tc.inc_ms = @intFromFloat(second * 1000);
    } else if (std.mem.eql(u8, kind, "sudden_death")) {
        m.tc.kind = .sudden_death;
        m.tc.base_ms = @intFromFloat(first * 1000);
    } else if (std.mem.eql(u8, kind, "movetime")) {
        m.tc.kind = .movetime;
        m.tc.movetime_ms = @intFromFloat(first);
    } else if (std.mem.eql(u8, kind, "depth")) {
        m.tc.kind = .depth;
        m.tc.depth = @intFromFloat(@max(first, 1));
    } else if (std.mem.eql(u8, kind, "nodes")) {
        m.tc.kind = .nodes;
        m.tc.nodes = @intFromFloat(@max(first, 1));
    }
    return 0;
}

fn matchSetGames(lua: *Lua) i32 {
    app().match.total_games = @intCast(@max(lua.checkInteger(1), 1));
    return 0;
}

const match_fns = [_]zlua.FnReg{
    .{ .name = "state", .func = zlua.wrap(matchState) },
    .{ .name = "start", .func = zlua.wrap(matchStart) },
    .{ .name = "abort", .func = zlua.wrap(matchAbort) },
    .{ .name = "score", .func = zlua.wrap(matchScore) },
    .{ .name = "clock", .func = zlua.wrap(matchClock) },
    .{ .name = "set_player", .func = zlua.wrap(matchSetPlayer) },
    .{ .name = "set_time", .func = zlua.wrap(matchSetTime) },
    .{ .name = "set_games", .func = zlua.wrap(matchSetGames) },
};

// ---------------------------------------------------------------------------
// theme
// ---------------------------------------------------------------------------

fn themePieceSets(lua: *Lua) i32 {
    const lib = &app().piece_library;
    lua.createTable(@intCast(lib.count), 0);
    for (0..lib.count) |i| {
        _ = lua.pushString(lib.nameAt(i));
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

/// Current set name, or nil when the built-in vector pieces are in use.
fn themePieceSet(lua: *Lua) i32 {
    const name = app().pieceSetName();
    if (name.len == 0) {
        lua.pushNil();
    } else {
        _ = lua.pushString(name);
    }
    return 1;
}

/// Pass nil or "" to go back to the built-in pieces.
fn themeSetPieceSet(lua: *Lua) i32 {
    const name = lua.optString(1) orelse "";
    lua.pushBoolean(app().setPieceSet(name));
    return 1;
}

/// Applied only when the user has not picked a set, so a script can ship a
/// default without overriding someone's choice on every reload.
fn themeSetDefaultPieceSet(lua: *Lua) i32 {
    app().applyDefaultPieceSet(lua.checkString(1));
    return 0;
}

fn themePieceTint(lua: *Lua) i32 {
    lua.pushBoolean(app().theme.piece_tint);
    return 1;
}

fn themeSetPieceTint(lua: *Lua) i32 {
    app().setPieceTint(lua.toBoolean(1));
    return 0;
}

fn themePiecesDir(lua: *Lua) i32 {
    const dir = app().piece_library.dirSlice();
    if (dir.len == 0) {
        lua.pushNil();
    } else {
        _ = lua.pushString(dir);
    }
    return 1;
}

fn themeRescanPieces(lua: *Lua) i32 {
    _ = lua;
    const a = app();
    a.piece_library.discover(a.allocator);
    return 0;
}

const theme_fns = [_]zlua.FnReg{
    .{ .name = "piece_sets", .func = zlua.wrap(themePieceSets) },
    .{ .name = "piece_set", .func = zlua.wrap(themePieceSet) },
    .{ .name = "set_piece_set", .func = zlua.wrap(themeSetPieceSet) },
    .{ .name = "set_default_piece_set", .func = zlua.wrap(themeSetDefaultPieceSet) },
    .{ .name = "piece_tint", .func = zlua.wrap(themePieceTint) },
    .{ .name = "set_piece_tint", .func = zlua.wrap(themeSetPieceTint) },
    .{ .name = "pieces_dir", .func = zlua.wrap(themePiecesDir) },
    .{ .name = "rescan_pieces", .func = zlua.wrap(themeRescanPieces) },
};

fn appQuit(lua: *Lua) i32 {
    _ = lua;
    app().quit_requested = true;
    return 0;
}

fn appView(lua: *Lua) i32 {
    _ = lua.pushString(app().viewId());
    return 1;
}

fn appSetView(lua: *Lua) i32 {
    app().setView(lua.checkString(1));
    return 0;
}

fn appNewTab(lua: *Lua) i32 {
    _ = lua;
    app().newTab();
    return 0;
}

fn appTabs(lua: *Lua) i32 {
    const a = app();
    lua.createTable(@intCast(a.tab_count), 0);
    for (0..a.tab_count) |i| {
        _ = lua.pushString(a.tabName(i));
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn appSelectTab(lua: *Lua) i32 {
    const n = lua.checkInteger(1);
    if (n >= 1) app().selectTab(@intCast(n - 1));
    return 0;
}

fn appStatus(lua: *Lua) i32 {
    const a = app();
    _ = lua.pushString(a.status_buf[0..a.status_len]);
    return 1;
}

fn appSetStatus(lua: *Lua) i32 {
    app().setStatus("{s}", .{lua.checkString(1)});
    return 0;
}

fn appClipboard(lua: *Lua) i32 {
    if (lua.optString(1)) |text| {
        rl.setClipboardText(text);
        return 0;
    }
    _ = lua.pushString(rl.getClipboardText());
    return 1;
}

fn appLog(lua: *Lua) i32 {
    const msg = lua.checkString(1);
    const level = lua.optString(2) orelse "note";
    const dir: @import("../log.zig").Dir = if (std.mem.eql(u8, level, "error")) .err else .note;
    app().log.add("lua", dir, msg);
    return 0;
}

fn appReloadUi(lua: *Lua) i32 {
    _ = lua;
    reload_requested = true;
    return 0;
}

fn appScriptDir(lua: *Lua) i32 {
    const v = vm();
    if (v.script_dir_len == 0) {
        _ = lua.pushString("(embedded)");
    } else {
        _ = lua.pushString(v.scriptDir());
    }
    return 1;
}

fn eventFrom(name: []const u8) ?vm_mod.Event {
    if (std.mem.eql(u8, name, "position")) return .position;
    if (std.mem.eql(u8, name, "engine_info")) return .engine_info;
    if (std.mem.eql(u8, name, "game_over")) return .game_over;
    if (std.mem.eql(u8, name, "frame")) return .frame;
    return null;
}

fn appOn(lua: *Lua) !i32 {
    const name = lua.checkString(1);
    lua.checkType(2, .function);

    const event = eventFrom(name) orelse lua.raiseErrorStr("unknown event", .{});
    lua.pushValue(2);
    const ref = try lua.ref(zlua.registry_index);
    vm().setHandler(event, ref);
    return 0;
}

fn appMap(lua: *Lua) !i32 {
    const key = lua.checkString(1);
    lua.checkType(2, .function);

    lua.pushValue(2);
    const ref = try lua.ref(zlua.registry_index);
    vm().addKeyMap(key, ref);
    return 0;
}

const app_fns = [_]zlua.FnReg{
    .{ .name = "quit", .func = zlua.wrap(appQuit) },
    .{ .name = "view", .func = zlua.wrap(appView) },
    .{ .name = "set_view", .func = zlua.wrap(appSetView) },
    .{ .name = "new_tab", .func = zlua.wrap(appNewTab) },
    .{ .name = "tabs", .func = zlua.wrap(appTabs) },
    .{ .name = "select_tab", .func = zlua.wrap(appSelectTab) },
    .{ .name = "status", .func = zlua.wrap(appStatus) },
    .{ .name = "set_status", .func = zlua.wrap(appSetStatus) },
    .{ .name = "clipboard", .func = zlua.wrap(appClipboard) },
    .{ .name = "log", .func = zlua.wrap(appLog) },
    .{ .name = "reload_ui", .func = zlua.wrap(appReloadUi) },
    .{ .name = "script_dir", .func = zlua.wrap(appScriptDir) },
    .{ .name = "on", .func = zlua.wrap(appOn) },
    .{ .name = "map", .func = zlua.wrap(appMap) },
};

pub var reload_requested: bool = false;

pub fn takeReloadRequest() bool {
    const r = reload_requested;
    reload_requested = false;
    return r;
}

fn installTable(lua: *Lua, name: [:0]const u8, fns: []const zlua.FnReg) void {
    lua.createTable(0, @intCast(fns.len));
    lua.setFuncs(fns, 0);
    lua.setGlobal(name);
}

pub fn install(v: *Vm, lua: *Lua) void {
    vm_ptr = v;
    ui_ptr = null;

    installTable(lua, "ui", &ui_fns);
    installTable(lua, "chess", &chess_fns);
    installTable(lua, "engine", &engine_fns);
    installTable(lua, "match", &match_fns);
    installTable(lua, "theme", &theme_fns);
    installTable(lua, "app", &app_fns);

    _ = lua.getGlobal("app") catch {
        lua.pop(1);
        return;
    };
    lua.pushInteger(api_version);
    lua.setField(-2, "api_version");
    lua.pop(1);
}
