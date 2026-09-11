const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const match_panel = @import("match.zig");
const pieces = @import("../pieces.zig");

pub const HomePanel = struct {
    pub const draws_own_background = true;

    scroll: widget.Scroll = .{},

    pub fn draw(self: *HomePanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        rl.drawRectangleRec(bounds, t.bg);

        const max_w: f32 = 780;
        const width = @min(bounds.width - 32, max_w);
        const column = rl.Rectangle{
            .x = bounds.x + (bounds.width - width) / 2,
            .y = bounds.y,
            .width = width,
            .height = bounds.height,
        };

        const content_h = self.measureContent(app);
        self.scroll.handle(bounds, content_h);

        rl.beginScissorMode(
            @intFromFloat(bounds.x),
            @intFromFloat(bounds.y),
            @intFromFloat(@max(bounds.width, 0)),
            @intFromFloat(@max(bounds.height, 0)),
        );
        defer rl.endScissorMode();

        var r = column;
        r.y -= self.scroll.offset;

        self.drawHeader(app, &r);
        self.drawNewGame(app, &r);
        self.drawPosition(app, &r);
        self.drawEngines(app, &r);

        self.scroll.drawBar(t, bounds, content_h);
    }

    fn measureContent(self: *HomePanel, app: *App) f32 {
        _ = self;
        const engines_h = 96 + @as(f32, @floatFromInt(app.engines.count)) * 22;
        return 120 + 250 + 120 + engines_h + 60;
    }

    fn card(app: *App, r: *rl.Rectangle, height: f32, title: [:0]const u8) rl.Rectangle {
        const t = app.theme;
        const outer = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.width, .height = height };
        widget.frame(outer, 0.06, t.panel, t.border);

        var inner = widget.inset(outer, 14);
        const head = widget.cutTop(&inner, 22);
        widget.text(head.x, head.y, t.font_size, t.text_bright, title);
        _ = widget.cutTop(&inner, 8);

        r.y += height + 14;
        r.height -= height + 14;
        return inner;
    }

    fn drawHeader(self: *HomePanel, app: *App, r: *rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        const head = widget.cutTop(r, 96);

        const cy = head.y + 46;
        pieces.draw(.Knight, .White, head.x + 30, cy, 54, t);

        widget.text(head.x + 68, head.y + 26, t.big_font + 8, t.text_bright, "Callisto");
        widget.text(head.x + 70, head.y + 60, t.small_font, t.text_dim, "a chess workbench: play, analyse, and run engine matches");
    }

    fn drawNewGame(self: *HomePanel, app: *App, r: *rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        var inner = card(app, r, 250, "new game");

        const used = match_panel.drawConfig(app, inner);
        inner.y += used;
        inner.height -= used;

        _ = widget.cutTop(&inner, 6);
        var buttons = widget.cutTop(&inner, 30);
        const start = widget.cutLeft(&buttons, 130);
        _ = widget.cutLeft(&buttons, 8);
        const free = widget.cutLeft(&buttons, 130);
        _ = widget.cutLeft(&buttons, 8);
        const analyse = widget.cutLeft(&buttons, 130);

        const running = app.match.isRunning();

        if (widget.buttonEx(t, start, "start match", .primary, !running)) {
            app.startMatch();
        }
        if (widget.buttonEx(t, free, "free play", .normal, !running)) {
            app.match.white = .{ .kind = .human };
            app.match.black = .{ .kind = .human };
            app.newGame(app.match.startFen());
            app.view = .game;
        }
        if (widget.button(t, analyse, "analyse board", .normal)) {
            app.view = .analysis;
            if (!app.engines.analysis_on and app.engines.count > 0) app.toggleAnalysis();
        }

        if (running) {
            _ = widget.cutTop(&inner, 8);
            const note = widget.cutTop(&inner, 18);
            widget.text(note.x, note.y, t.small_font, t.warn, "a match is running - abort it from the game view to change settings");
        }
    }

    fn drawPosition(self: *HomePanel, app: *App, r: *rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        var inner = card(app, r, 106, "start position");

        var line = widget.cutTop(&inner, 26);
        const load = widget.cutRight(&line, 60);
        _ = widget.cutRight(&line, 6);

        if (app.fen_input.draw(t, line, "FEN")) app.loadFenFromInput();
        if (widget.button(t, load, "load", .primary)) app.loadFenFromInput();

        _ = widget.cutTop(&inner, 8);
        var buttons = widget.cutTop(&inner, 26);
        const std_btn = widget.cutLeft(&buttons, 110);
        _ = widget.cutLeft(&buttons, 8);
        const board_btn = widget.cutLeft(&buttons, 140);

        if (widget.button(t, std_btn, "standard", .normal)) {
            app.fen_input.set(chess.start_position);
            app.newGame(chess.start_position);
            app.match.setStartFen(chess.start_position);
        }
        if (widget.button(t, board_btn, "use current board", .normal)) {
            const text = app.game.currentFen(app.allocator) catch return;
            defer app.allocator.free(text);
            app.match.setStartFen(text);
            app.setStatus("matches will start from the board position", .{});
        }
    }

    fn drawEngines(self: *HomePanel, app: *App, r: *rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        const height = 96 + @as(f32, @floatFromInt(app.engines.count)) * 22;
        var inner = card(app, r, height, "engines");

        var line = widget.cutTop(&inner, 26);
        const add = widget.cutRight(&line, 56);
        _ = widget.cutRight(&line, 6);

        if (app.engine_path_input.draw(t, line, "path to a UCI engine binary")) app.addEngineFromInput();
        if (widget.button(t, add, "add", .primary)) app.addEngineFromInput();

        _ = widget.cutTop(&inner, 6);

        if (app.engines.count == 0) {
            widget.text(inner.x, inner.y + 2, t.small_font, t.text_dim, "point at any UCI engine binary, or drop one onto the window");
            return;
        }

        for (app.engines.slice()) |*e| {
            const row = widget.cutTop(&inner, 22);
            if (row.height < 12) break;

            var nbuf: [72]u8 = undefined;
            var clip: [88]u8 = undefined;
            widget.textClipped(
                row.x,
                row.y + 3,
                row.width - 160,
                t.small_font,
                t.text,
                widget.zSlice(&nbuf, e.nameSlice()),
                &clip,
            );

            const col = switch (e.status) {
                .ready => t.good,
                .thinking => t.accent,
                .failed => t.bad,
                else => t.text_dim,
            };
            var sbuf: [48]u8 = undefined;
            widget.textRight(
                row.x + row.width,
                row.y + 3,
                t.small_font,
                col,
                widget.zBuf(&sbuf, "{s}", .{e.status.label()}),
            );
        }
    }
};
