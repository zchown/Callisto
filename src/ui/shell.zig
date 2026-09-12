const std = @import("std");
const rl = @import("raylib");
const App = @import("../app.zig").App;
const widget = @import("widget.zig");
const icons = @import("icons.zig");
const pieces = @import("pieces.zig");
const theme_mod = @import("theme.zig");
const views_mod = @import("views.zig");
const panel_mod = @import("panel.zig");
const vm_mod = @import("../lua/vm.zig");

const Theme = theme_mod.Theme;
const ViewSet = views_mod.ViewSet;

pub const Result = struct {
    content: rl.Rectangle,
};

pub fn draw(
    app: *App,
    vm: *vm_mod.Vm,
    views: *ViewSet,
    registry: *panel_mod.Registry,
    screen: rl.Rectangle,
) Result {
    const t = app.theme;
    rl.drawRectangleRec(screen, t.bg);

    var body = screen;
    const status = widget.cutBottom(&body, t.statusbar_h);
    const side = widget.cutLeft(&body, if (app.sidebar_collapsed) t.sidebar_w_collapsed else t.sidebar_w);

    drawSidebar(app, views, side);

    const board_index = registry.indexOf("board");
    const has_board = blk: {
        const idx = board_index orelse break :blk false;
        const view = views.resolve(app.viewId()) orelse break :blk false;
        break :blk view.layout.containsPanel(idx);
    };

    const tabs = widget.cutTop(&body, t.tabbar_h);
    drawTabBar(app, tabs, has_board);

    if (!vm.ok) drawErrorBar(app, vm, widget.cutTop(&body, 28));

    drawStatusBar(app, vm, status);

    rl.drawRectangleRec(.{ .x = body.x, .y = body.y, .width = body.width, .height = 1 }, t.border_soft);
    body.y += 1;
    body.height -= 1;

    return .{ .content = widget.inset(body, 6) };
}

fn drawSidebar(app: *App, views: *ViewSet, r: rl.Rectangle) void {
    const t = app.theme;
    const collapsed = app.sidebar_collapsed;

    rl.drawRectangleRec(r, t.sidebar);
    rl.drawRectangleRec(
        .{ .x = r.x + r.width - 1, .y = r.y, .width = 1, .height = r.height },
        t.border_soft,
    );

    var col = widget.inset(r, 10);

    // brand 
    {
        const head = widget.cutTop(&col, 52);
        const mark = rl.Rectangle{ .x = head.x + 2, .y = head.y + 8, .width = 30, .height = 30 };
        pieces.draw(.Knight, .White, mark.x + mark.width / 2, mark.y + mark.height / 2, 30, t);

        if (!collapsed) {
            widget.text(
                head.x + 40,
                head.y + 14,
                t.big_font,
                t.text_bright,
                "Callisto",
            );
        }
        _ = widget.cutTop(&col, 6);
    }

    // navigation 
    for (views.items[0..views.count]) |*v| {
        if (!v.ready or !v.in_sidebar) continue;

        const row = widget.cutTop(&col, 36);
        _ = widget.cutTop(&col, 3);
        if (row.height < 20) break;

        const active = app.viewIs(v.idSlice());
        const over = widget.hovered(row);

        if (active) {
            widget.surface(row, 8, t.accent_soft);
            rl.drawRectangleRounded(
                .{ .x = row.x, .y = row.y + 7, .width = 3, .height = row.height - 14 },
                1.0,
                4,
                t.accent,
            );
        } else if (over) {
            widget.surface(row, 8, t.panel);
        }

        const fg = if (active) t.text_bright else if (over) t.text else t.text_dim;
        const icon_box = rl.Rectangle{ .x = row.x + 10, .y = row.y + 9, .width = 18, .height = 18 };
        icons.draw(v.icon, icon_box, if (active) t.accent else fg);

        if (!collapsed) {
            var buf: [views_mod.max_label + 1]u8 = undefined;
            widget.text(
                row.x + 38,
                row.y + (row.height - t.fontF()) / 2,
                t.font_size,
                fg,
                widget.zSlice(&buf, v.labelSlice()),
            );
        }

        if (widget.clicked(row)) app.setView(v.idSlice());
    }

    // footer 
    var footer = col;
    const bottom = widget.cutBottom(&footer, 34);
    const collapse = rl.Rectangle{
        .x = bottom.x,
        .y = bottom.y,
        .width = if (collapsed) bottom.width else 34,
        .height = 30,
    };
    if (widget.hovered(collapse)) widget.surface(collapse, 8, t.panel);
    icons.draw(
        if (collapsed) .chevron_right else .chevron_left,
        .{ .x = collapse.x + collapse.width / 2 - 8, .y = collapse.y + 7, .width = 16, .height = 16 },
        if (widget.hovered(collapse)) t.text else t.text_dim,
    );
    if (widget.clicked(collapse)) app.sidebar_collapsed = !app.sidebar_collapsed;

    if (!collapsed) {
        const info = rl.Rectangle{
            .x = bottom.x + 40,
            .y = bottom.y,
            .width = bottom.width - 40,
            .height = 30,
        };
        var buf: [48]u8 = undefined;
        const analysing = app.engines.analysis_on;
        widget.text(
            info.x,
            info.y + (info.height - t.smallF()) / 2,
            t.small_font,
            if (analysing) t.good else t.text_dim,
            widget.zBuf(&buf, "{d} engine{s}", .{
                app.engines.count,
                if (app.engines.count == 1) "" else "s",
            }),
        );
    }
}

fn drawTabBar(app: *App, r: rl.Rectangle, has_board: bool) void {
    const t = app.theme;
    rl.drawRectangleRec(r, t.bg);

    var bar = r;
    bar.y += 5;
    bar.height -= 5;

    const action_w: f32 = if (has_board) 232 else 44;
    const actions = widget.cutRight(&bar, @min(action_w, @max(bar.width - 120, 0)));
    drawActions(app, actions, has_board);

    var strip = bar;
    _ = widget.cutLeft(&strip, 6);

    const max_tab_w: f32 = 168;
    const min_tab_w: f32 = 84;
    const plus_w: f32 = 30;

    const available = @max(strip.width - plus_w - 6, 0);
    const count_f: f32 = @floatFromInt(@max(app.tab_count, 1));
    const tab_w = std.math.clamp(available / count_f, min_tab_w, max_tab_w);

    var close_index: ?usize = null;

    for (0..app.tab_count) |i| {
        if (strip.width < min_tab_w + plus_w) break;

        const tab = widget.cutLeft(&strip, tab_w);
        _ = widget.cutLeft(&strip, 3);

        const active = i == app.active_tab;
        const over = widget.hovered(tab);

        if (active) {
            widget.frame(tab, 8, t.panel, t.border_soft);
            rl.drawRectangleRounded(
                .{ .x = tab.x + 10, .y = tab.y, .width = tab.width - 20, .height = 2 },
                1.0,
                4,
                t.accent,
            );
        } else if (over) {
            widget.surface(tab, 8, t.panel_alt);
        }

        var body = widget.inset(tab, 8);
        const close = widget.cutRight(&body, 18);

        var buf: [48]u8 = undefined;
        var clip: [64]u8 = undefined;
        widget.textClipped(
            body.x + 2,
            body.y + (body.height - t.smallF()) / 2,
            body.width - 4,
            t.small_font,
            if (active) t.text_bright else t.text_dim,
            widget.zSlice(&buf, app.tabName(i)),
            &clip,
        );

        if (app.tab_count > 1 and (over or active)) {
            const hot = widget.hovered(close);
            icons.draw(
                .close,
                .{ .x = close.x + 3, .y = close.y + (close.height - 12) / 2, .width = 12, .height = 12 },
                if (hot) t.bad else t.text_dim,
            );
            if (widget.clicked(close)) close_index = i;
        }

        if (widget.clicked(tab) and close_index == null) app.selectTab(i);
    }

    // New tab.
    if (strip.width >= plus_w) {
        const plus = widget.cutLeft(&strip, plus_w);
        const box = rl.Rectangle{ .x = plus.x, .y = plus.y + 3, .width = 26, .height = plus.height - 6 };
        if (widget.hovered(box)) widget.surface(box, 7, t.panel_alt);
        icons.draw(
            .plus,
            .{ .x = box.x + 7, .y = box.y + (box.height - 12) / 2, .width = 12, .height = 12 },
            if (widget.hovered(box)) t.text_bright else t.text_dim,
        );
        if (widget.clicked(box)) app.newTab();
    }

    if (close_index) |i| app.closeTab(i);
}

fn drawActions(app: *App, r: rl.Rectangle, has_board: bool) void {
    const t = app.theme;
    var bar = r;
    _ = widget.cutRight(&bar, 4);

    const help = widget.cutRight(&bar, 30);
    if (actionButton(t, help, "?", .ghost)) {
        app.show_help = !app.show_help;
        app.help_armed = false;
    }

    if (!has_board) return;

    _ = widget.cutRight(&bar, 6);
    const analyse = widget.cutRight(&bar, 78);
    _ = widget.cutRight(&bar, 4);
    const copy = widget.cutRight(&bar, 74);
    _ = widget.cutRight(&bar, 4);
    const flip = widget.cutRight(&bar, 52);

    if (bar.width < 0) return;

    const on = app.engines.analysis_on;
    if (actionButton(t, analyse, if (on) "stop" else "analyse", if (on) .danger else .primary)) {
        app.toggleAnalysis();
    }
    if (actionButton(t, copy, "copy fen", .normal)) app.copyCurrentFen();
    if (actionButton(t, flip, "flip", .normal)) app.flipped = !app.flipped;
}

fn actionButton(t: Theme, r: rl.Rectangle, label: [:0]const u8, style: widget.Style) bool {
    const box = rl.Rectangle{ .x = r.x, .y = r.y + 3, .width = r.width, .height = r.height - 6 };
    return widget.button(t, box, label, style);
}

fn drawErrorBar(app: *App, vm: *vm_mod.Vm, r: rl.Rectangle) void {
    const t = app.theme;
    const box = widget.inset(r, 3);
    widget.frame(box, 6, rl.Color{ .r = 58, .g = 28, .b = 32, .a = 255 }, t.bad);

    var body = widget.inset(box, 4);
    const btn = widget.cutRight(&body, 70);
    if (widget.button(t, btn, "reload", .danger)) vm.reload();

    var buf: [320]u8 = undefined;
    var clip: [340]u8 = undefined;
    widget.textClipped(
        body.x + 6,
        body.y + (body.height - t.smallF()) / 2,
        body.width - 10,
        t.small_font,
        t.text_bright,
        widget.zSlice(&buf, vm.errSlice()),
        &clip,
    );
}

fn drawStatusBar(app: *App, vm: *vm_mod.Vm, r: rl.Rectangle) void {
    const t = app.theme;
    rl.drawRectangleRec(r, t.sidebar);
    rl.drawRectangleRec(.{ .x = r.x, .y = r.y, .width = r.width, .height = 1 }, t.border_soft);

    const y = r.y + (r.height - t.smallF()) / 2;
    widget.text(r.x + 14, y, t.small_font, t.text_dim, app.statusZ());

    const white_to_move = app.game.sideToMove() == .White;
    const label: [:0]const u8 = if (white_to_move) "white to move" else "black to move";
    const label_w = widget.measure(label, t.small_font);
    const cx = r.x + r.width / 2;

    rl.drawCircleV(
        .{ .x = cx - label_w / 2 - 10, .y = r.y + r.height / 2 },
        4,
        if (white_to_move) t.piece_white else t.piece_black,
    );
    widget.text(cx - label_w / 2, y, t.small_font, t.text_dim, label);

    var buf: [96]u8 = undefined;
    widget.textRight(
        r.x + r.width - 14,
        y,
        t.small_font,
        t.text_dim,
        widget.zBuf(&buf, "{s}  ·  {d} fps", .{
            if (vm.from_disk) "lua: disk" else "lua: embedded",
            rl.getFPS(),
        }),
    );
}
