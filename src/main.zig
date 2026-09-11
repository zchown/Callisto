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

const toolbar_h: f32 = 36.0;
const statusbar_h: f32 = 22.0;

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
        .home = registry.add(panel_mod.Panel.from(&home, "Home")),
        .board = registry.add(panel_mod.Panel.from(&board, "Board")),
        .moves = registry.add(panel_mod.Panel.from(&moves, "Moves")),
        .analysis = registry.add(panel_mod.Panel.from(&analysis, "Analysis")),
        .engines = registry.add(panel_mod.Panel.from(&engines, "Engines")),
        .match = registry.add(panel_mod.Panel.from(&match, "Match")),
        .log = registry.add(panel_mod.Panel.from(&logs, "UCI log")),
    };

    var views = try views_mod.Views.build(ids);

    while (!rl.windowShouldClose() and !app.quit_requested) {
        const dt = rl.getFrameTime();

        handleShortcuts(app, &board);
        app.update();
        for (registry.slice()) |p| p.update(app, dt);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(app.theme.bg);

        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());

        rl.setMouseCursor(.default);

        drawToolbar(app, .{ .x = 0, .y = 0, .width = w, .height = toolbar_h });

        views.current(app.view).draw(app, &registry, .{
            .x = 0,
            .y = toolbar_h,
            .width = w,
            .height = @max(h - toolbar_h - statusbar_h, 0),
        });

        drawStatusBar(app, .{ .x = 0, .y = h - statusbar_h, .width = w, .height = statusbar_h });

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

fn handleShortcuts(app: *App, board: *board_view.BoardView) void {
    if (widget.keyboard_captured) return;

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

fn drawStatusBar(app: *App, r: rl.Rectangle) void {
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
        widget.zBuf(&buf, "{d} engine(s)   {d} fps", .{ app.engines.count, rl.getFPS() }),
    );
}

fn drawHelp(app: *App, w: f32, h: f32) void {
    const t = app.theme;
    rl.drawRectangleRec(.{ .x = 0, .y = 0, .width = w, .height = h }, rl.fade(t.bg, 0.85));

    const bw: f32 = 520;
    const bh: f32 = 400;
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

    widget.text(r.x + 20, r.y + bh - 30, t.small_font, t.text_dim, "engines: point at any UCI binary, or drop one onto the window");
    if (rl.isMouseButtonPressed(.left)) app.show_help = false;
}
