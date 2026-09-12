const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const app_mod = @import("app.zig");
const App = app_mod.App;

const widget = @import("ui/widget.zig");
const panel_mod = @import("ui/panel.zig");
const views_mod = @import("ui/views.zig");
const shell = @import("ui/shell.zig");
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

    const vm = try allocator.create(vm_mod.Vm);
    defer {
        vm.deinit();
        allocator.destroy(vm);
    }
    vm.init(allocator, app);

    var slots = lua_panel.Slots{};
    var views = views_mod.ViewSet{};
    try views.buildDefaults(ids);

    vm.load();
    syncLuaPanels(vm, &registry, &slots);
    applyLuaViews(vm, &registry, &views);

    while (!rl.windowShouldClose() and !app.quit_requested) {
        const dt = rl.getFrameTime();

        if (handleReload(vm, &registry, &slots, &views)) continue;

        handleShortcuts(app, vm, &board);
        handleViewKeys(app, &views);

        widget.keyboard_captured = false;

        app.update();
        vm.update();

        if (app.piece_library.applyPending()) {
            app.log.print("ui", .note, "pieces re-rendered at {d}px", .{app.piece_library.renderSize()});
        }
        for (registry.slice()) |p| p.update(app, dt);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(app.theme.bg);

        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());

        rl.setMouseCursor(.default);

        if (!app.show_help) app.help_armed = false;
        widget.input_blocked = app.show_help;

        const chrome = shell.draw(app, vm, &views, &registry, .{ .x = 0, .y = 0, .width = w, .height = h });
        if (views.resolve(app.viewId())) |view| {
            view.layout.draw(app, &registry, chrome.content);
        }

        widget.input_blocked = false;
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

    if (dispatchLuaKeys(vm)) return;

    if (rl.isKeyPressed(.left)) app.game.back();
    if (rl.isKeyPressed(.right)) app.game.forward();
    if (rl.isKeyPressed(.up)) app.game.toStart();
    if (rl.isKeyPressed(.down)) app.game.toEnd();

    if (rl.isKeyPressed(.f)) app.flipped = !app.flipped;

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
    if (ctrl and rl.isKeyPressed(.t)) app.newTab();
    if (ctrl and rl.isKeyPressed(.w)) app.closeTab(app.active_tab);
    if (ctrl and rl.isKeyPressed(.v)) app.loadFenFromClipboard();
}

fn handleViewKeys(app: *App, views: *views_mod.ViewSet) void {
    if (widget.keyboard_captured) return;

    var shown: usize = 0;
    for (views.items[0..views.count]) |*v| {
        if (!v.ready or !v.in_sidebar) continue;
        shown += 1;
        if (shown > 9) break;

        const key: rl.KeyboardKey = @enumFromInt(@as(i32, '0') + @as(i32, @intCast(shown)));
        if (rl.isKeyPressed(key)) app.setView(v.idSlice());
    }
}



fn syncLuaPanels(vm: *vm_mod.Vm, registry: *panel_mod.Registry, slots: *lua_panel.Slots) void {
    for (0..vm.panel_count) |i| {
        const p = vm.panelAt(i) orelse continue;
        if (p.registry_index != null) continue;

        const slot = slots.make(vm, i) orelse continue;
        p.registry_index = registry.add(panel_mod.Panel.named(slot, p.nameSlice(), p.titleZ()));
    }
}

fn applyLuaViews(vm: *vm_mod.Vm, registry: *panel_mod.Registry, views: *views_mod.ViewSet) void {
    if (!vm.views_dirty) return;
    vm.views_dirty = false;
    const n = layout_spec.apply(vm, registry, views);
    if (n > 0) vm.app.log.print("lua", .note, "{d} view(s) described by script", .{n});
}

fn handleReload(
    vm: *vm_mod.Vm,
    registry: *panel_mod.Registry,
    slots: *lua_panel.Slots,
    views: *views_mod.ViewSet,
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


fn drawHelp(app: *App, w: f32, h: f32) void {
    const t = app.theme;
    rl.drawRectangleRec(.{ .x = 0, .y = 0, .width = w, .height = h }, rl.fade(t.bg, 0.85));

    const bw: f32 = 520;
    const bh: f32 = 440;
    const r = rl.Rectangle{ .x = (w - bw) / 2, .y = (h - bh) / 2, .width = bw, .height = bh };
    widget.frame(r, 14, t.panel, t.border);

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
        .{ "ctrl + t / w", "new tab / close tab" },
        .{ "ctrl + c / v", "copy / paste a FEN" },
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
    widget.text(r.x + 20, r.y + bh - 28, t.small_font, t.text_dim, "click anywhere or press esc to close");

    if (app.help_armed) {
        if (rl.isMouseButtonPressed(.left)) app.show_help = false;
    } else {
        app.help_armed = true;
    }
}
