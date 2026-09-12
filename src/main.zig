const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const app_mod = @import("app.zig");
const App = app_mod.App;
const View = app_mod.View;

const widget = @import("ui/widget.zig");
const panel_mod = @import("ui/panel.zig");
const views_mod = @import("ui/views.zig");
const board_view = @import("ui/board_view.zig");

const home_panel = @import("ui/panels/home.zig");
const moves_panel = @import("ui/panels/moves.zig");
const analysis_panel = @import("ui/panels/analysis.zig");
const engines_panel = @import("ui/panels/engines.zig");
const match_panel = @import("ui/panels/match.zig");
const log_panel = @import("ui/panels/log.zig");
const lua_panel = @import("ui/panels/lua_panel.zig");

const vm_mod = @import("lua/vm.zig");
const api = @import("lua/api.zig");
const layout_spec = @import("lua/layout_spec.zig");

const toolbar_h: f32 = 36.0;
const statusbar_h: f32 = 22.0;
const error_bar_h: f32 = 26.0;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try chess.attacks.init();

    rl.setConfigFlags(.{ .window_resizable = true, .msaa_4x_hint = true, .vsync_hint = true });
    rl.initWindow(1440, 900, "Callisto");
    defer rl.closeWindow();
    rl.setWindowMinSize(960, 640);
    rl.setTargetFPS(60);
    rl.setExitKey(.null);

    const app = try App.create(allocator);
    defer app.destroy();

    widget.font = tryLoadFont(app.theme.font_size);
    defer if (widget.font) |f| rl.unloadFont(f);

    app.engines.loadConfig(&app.log);

    var home = home_panel.HomePanel{};
    var board = board_view.BoardView{};
    var moves = moves_panel.MovesPanel{};
    var analysis = analysis_panel.AnalysisPanel{};
    var engines = engines_panel.EnginesPanel{};
    var match = match_panel.MatchPanel{};
    var logs = log_panel.LogPanel{};

    var registry = panel_mod.Registry{};
    const ids = views_mod.Ids{
        .home = registry.add(panel_mod.Panel.named(&home, "home", "Home")),
        .board = registry.add(panel_mod.Panel.named(&board, "board", "Board")),
        .moves = registry.add(panel_mod.Panel.named(&moves, "moves", "Moves")),
        .analysis = registry.add(panel_mod.Panel.named(&analysis, "analysis", "Analysis")),
        .engines = registry.add(panel_mod.Panel.named(&engines, "engines", "Engines")),
        .match = registry.add(panel_mod.Panel.named(&match, "match", "Match")),
        .log = registry.add(panel_mod.Panel.named(&logs, "log", "UCI log")),
    };

    // -- Lua ---------------------------------------------------------------
    const vm = try allocator.create(vm_mod.Vm);
    defer {
        vm.deinit();
        allocator.destroy(vm);
    }
    vm.init(allocator, app);

    var slots = lua_panel.Slots{};
    var views = try views_mod.Views.build(ids);

    vm.load();
    syncLuaPanels(vm, &registry, &slots);
    applyLuaViews(vm, &registry, &views);

    while (!rl.windowShouldClose() and !app.quit_requested) {
        const dt = rl.getFrameTime();

        if (handleReload(vm, &registry, &slots, &views)) continue;

        handleShortcuts(app, vm, &board);

        // Text boxes set this while drawing; clear it once shortcuts have had
        // their look at the previous frame's value.
        widget.keyboard_captured = false;

        app.update();
        vm.update();
        for (registry.slice()) |p| p.update(app, dt);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(app.theme.bg);

        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());

        rl.setMouseCursor(.default);

        var body = rl.Rectangle{ .x = 0, .y = 0, .width = w, .height = h };
        drawToolbar(app, widget.cutTop(&body, toolbar_h));
        _ = widget.cutBottom(&body, statusbar_h);

        if (!vm.ok) drawErrorBar(app, vm, widget.cutTop(&body, error_bar_h));

        views.current(app.view).draw(app, &registry, body);
        drawStatusBar(app, .{ .x = 0, .y = h - statusbar_h, .width = w, .height = statusbar_h }, vm);

        if (app.show_help) drawHelp(app, w, h);
    }

    app.engines.saveConfig();
}

fn tryLoadFont(size: i32) ?rl.Font {
    const candidates = [_][:0]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "C:\\Windows\\Fonts\\segoeui.ttf",
    };

    for (candidates) |path| {
        if (!rl.fileExists(path)) continue;
        const font = rl.loadFontEx(path, size * 2, null) catch continue;
        rl.setTextureFilter(font.texture, .bilinear);
        return font;
    }
    return null;
}

fn handleShortcuts(app: *App, vm: *vm_mod.Vm, board: *board_view.BoardView) void {
    if (widget.keyboard_captured) return;

    // Scripts get first refusal on letter and digit keys.
    if (dispatchLuaKeys(vm)) return;

    if (rl.isKeyPressed(.left)) app.game.back();
    if (rl.isKeyPressed(.right)) app.game.forward();
    if (rl.isKeyPressed(.up)) app.game.toStart();
    if (rl.isKeyPressed(.down)) app.game.toEnd();

    if (rl.isKeyPressed(.f)) app.flipped = !app.flipped;
    if (rl.isKeyPressed(.one)) app.view = .home;
    if (rl.isKeyPressed(.two)) app.view = .game;
    if (rl.isKeyPressed(.three)) app.view = .analysis;

    if (rl.isKeyPressed(.escape)) {
        app.game.clearPreview();
        board.clearSelection();
        board.clearArrows();
        app.show_help = false;
    }

    if (rl.isKeyPressed(.space)) app.toggleAnalysis();

    const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control) or
        rl.isKeyDown(.left_super) or rl.isKeyDown(.right_super);
    if (ctrl and rl.isKeyPressed(.n)) app.newGame(chess.start_position);
    if (ctrl and rl.isKeyPressed(.c)) app.copyCurrentFen();
}

fn drawToolbar(app: *App, r: rl.Rectangle) void {
    const t = app.theme;
    rl.drawRectangleRec(r, t.panel);
    rl.drawRectangleRec(
        .{ .x = r.x, .y = r.y + r.height - 1, .width = r.width, .height = 1 },
        t.border,
    );

    const h: f32 = 24;
    var bar = rl.Rectangle{ .x = r.x + 8, .y = r.y + (r.height - h) / 2, .width = r.width - 16, .height = h };

    // View switcher.
    inline for (.{ View.home, View.game, View.analysis }) |v| {
        const btn = widget.cutLeft(&bar, 78);
        if (widget.toggle(t, btn, v.label(), app.view == v)) app.view = v;
        _ = widget.cutLeft(&bar, 4);
    }

    _ = widget.cutLeft(&bar, 8);

    const new_btn = widget.cutLeft(&bar, 54);
    _ = widget.cutLeft(&bar, 4);
    const flip_btn = widget.cutLeft(&bar, 48);
    _ = widget.cutLeft(&bar, 4);
    const copy_btn = widget.cutLeft(&bar, 52);
    _ = widget.cutLeft(&bar, 8);

    if (widget.button(t, new_btn, "new", .normal)) app.newGame(chess.start_position);
    if (widget.button(t, flip_btn, "flip", .normal)) app.flipped = !app.flipped;
    if (widget.button(t, copy_btn, "copy", .normal)) app.copyCurrentFen();

    // Right hand side first, so the FEN box can take what is left.
    const help_btn = widget.cutRight(&bar, 28);
    _ = widget.cutRight(&bar, 6);
    const arrows_btn = widget.cutRight(&bar, 104);
    _ = widget.cutRight(&bar, 6);
    const analyse_btn = widget.cutRight(&bar, 80);
    _ = widget.cutRight(&bar, 8);
    const load_btn = widget.cutRight(&bar, 52);
    _ = widget.cutRight(&bar, 5);

    if (widget.button(t, help_btn, "?", .ghost)) app.show_help = !app.show_help;
    _ = widget.checkBox(t, arrows_btn, "pv arrows", &app.show_pv_arrows);
    if (widget.toggle(t, analyse_btn, if (app.engines.analysis_on) "stop" else "analyse", app.engines.analysis_on)) {
        app.toggleAnalysis();
    }
    if (widget.button(t, load_btn, "load", .normal)) app.loadFenFromInput();

    if (bar.width > 120) {
        if (app.fen_input.draw(t, bar, "FEN")) app.loadFenFromInput();
    }
}

fn drawStatusBar(app: *App, r: rl.Rectangle, vm: *vm_mod.Vm) void {
    const t = app.theme;
    rl.drawRectangleRec(r, t.panel);
    rl.drawRectangleRec(.{ .x = r.x, .y = r.y, .width = r.width, .height = 1 }, t.border);

    const y = r.y + (r.height - t.smallF()) / 2;
    widget.text(r.x + 8, y, t.small_font, t.text, app.statusZ());

    const side: [:0]const u8 = if (app.game.sideToMove() == .White) "white to move" else "black to move";
    widget.text(r.x + r.width * 0.52, y, t.small_font, t.text_dim, side);

    var buf: [96]u8 = undefined;
    widget.textRight(
        r.x + r.width - 8,
        y,
        t.small_font,
        t.text_dim,
        widget.zBuf(&buf, "{s}   {d} engine(s)   {d} fps", .{
            if (vm.from_disk) "lua: disk" else "lua: embedded",
            app.engines.count,
            rl.getFPS(),
        }),
    );
}

// ---------------------------------------------------------------------------
// Lua integration
// ---------------------------------------------------------------------------

/// Give every Lua-registered panel a slot in the Zig registry. A slot is handed
/// out once per panel name and kept across reloads, so view specs stay valid.
fn syncLuaPanels(vm: *vm_mod.Vm, registry: *panel_mod.Registry, slots: *lua_panel.Slots) void {
    for (0..vm.panel_count) |i| {
        const p = vm.panelAt(i) orelse continue;
        if (p.registry_index != null) continue;

        const slot = slots.make(vm, i) orelse continue;
        p.registry_index = registry.add(panel_mod.Panel.named(slot, p.nameSlice(), p.titleZ()));
    }
}

fn applyLuaViews(vm: *vm_mod.Vm, registry: *panel_mod.Registry, views: *views_mod.Views) void {
    if (!vm.views_dirty) return;
    vm.views_dirty = false;
    const n = layout_spec.apply(vm, registry, views);
    if (n > 0) vm.app.log.print("lua", .note, "{d} view(s) described by script", .{n});
}

/// Returns true when the VM was reloaded this frame, so the caller can skip the
/// rest of the frame rather than draw against a half-built state.
fn handleReload(
    vm: *vm_mod.Vm,
    registry: *panel_mod.Registry,
    slots: *lua_panel.Slots,
    views: *views_mod.Views,
) bool {
    const asked = api.takeReloadRequest() or
        (!widget.keyboard_captured and rl.isKeyPressed(.f5));
    if (!asked) {
        applyLuaViews(vm, registry, views);
        return false;
    }

    vm.reload();
    syncLuaPanels(vm, registry, slots);
    applyLuaViews(vm, registry, views);
    return true;
}

/// Letters and digits are offered to script bindings first. raylib's key codes
/// are ASCII for both ranges, so the mapping is arithmetic.
fn dispatchLuaKeys(vm: *vm_mod.Vm) bool {
    if (vm.keymap_count == 0) return false;

    var i: u8 = 0;
    while (i < 26) : (i += 1) {
        const key: rl.KeyboardKey = @enumFromInt(@as(i32, 'A') + @as(i32, i));
        if (!rl.isKeyPressed(key)) continue;
        const name = [_]u8{'a' + i};
        if (vm.fireKey(&name)) return true;
    }

    var d: u8 = 0;
    while (d < 10) : (d += 1) {
        const key: rl.KeyboardKey = @enumFromInt(@as(i32, '0') + @as(i32, d));
        if (!rl.isKeyPressed(key)) continue;
        const name = [_]u8{'0' + d};
        if (vm.fireKey(&name)) return true;
    }

    return false;
}

fn drawErrorBar(app: *App, vm: *vm_mod.Vm, r: rl.Rectangle) void {
    const t = app.theme;
    rl.drawRectangleRec(r, rl.Color{ .r = 70, .g = 30, .b = 30, .a = 255 });
    rl.drawRectangleRec(.{ .x = r.x, .y = r.y + r.height - 1, .width = r.width, .height = 1 }, t.bad);

    var body = widget.inset(r, 4);
    const btn = widget.cutRight(&body, 76);
    if (widget.button(t, btn, "reload", .danger)) vm.reload();

    var buf: [320]u8 = undefined;
    var clip: [340]u8 = undefined;
    widget.textClipped(
        body.x + 4,
        body.y + (body.height - t.smallF()) / 2,
        body.width - 8,
        t.small_font,
        t.text_bright,
        widget.zSlice(&buf, vm.errSlice()),
        &clip,
    );
}

fn drawHelp(app: *App, w: f32, h: f32) void {
    const t = app.theme;
    rl.drawRectangleRec(.{ .x = 0, .y = 0, .width = w, .height = h }, rl.fade(t.bg, 0.85));

    const bw: f32 = 520;
    const bh: f32 = 440;
    const r = rl.Rectangle{ .x = (w - bw) / 2, .y = (h - bh) / 2, .width = bw, .height = bh };
    widget.frame(r, 0.04, t.panel, t.border);

    const lines = [_][2][:0]const u8{
        .{ "left drag / click", "make a move" },
        .{ "right drag", "draw an arrow (right click a square to clear)" },
        .{ "left / right", "step through the game" },
        .{ "up / down", "jump to the start / end" },
        .{ "wheel over board", "step through the game" },
        .{ "1 / 2 / 3", "home, game, analysis views" },
        .{ "f", "flip the board" },
        .{ "space", "toggle analysis" },
        .{ "F5", "reload the Lua UI" },
        .{ "ctrl + n", "new game" },
        .{ "ctrl + c", "copy the FEN" },
        .{ "esc", "clear selection, preview and arrows" },
        .{ "hover a pv move", "preview the position at that ply" },
        .{ "click a pv move", "play that line on the board" },
    };

    widget.text(r.x + 20, r.y + 18, t.big_font, t.text_bright, "shortcuts");
    var y = r.y + 56;
    for (lines) |l| {
        widget.text(r.x + 20, y, t.small_font, t.accent, l[0]);
        widget.text(r.x + 190, y, t.small_font, t.text, l[1]);
        y += 22;
    }

    widget.text(r.x + 20, r.y + bh - 48, t.small_font, t.text_dim, "scripts bind their own keys; see lua/init.lua");
    widget.text(r.x + 20, r.y + bh - 28, t.small_font, t.text_dim, "engines: point at any UCI binary, or drop one onto the window");
    if (rl.isMouseButtonPressed(.left)) app.show_help = false;
}
