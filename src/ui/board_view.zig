const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../app.zig").App;
const widget = @import("widget.zig");
const pieces = @import("pieces.zig");
const theme_mod = @import("theme.zig");
const match_mod = @import("../match.zig");

const Theme = theme_mod.Theme;
const Square = chess.Square;
const Color = chess.Color;
const Move = chess.Move;

pub const Arrow = struct {
    from: Square,
    to: Square,
    color: rl.Color,
};

pub const BoardView = struct {
    pub const draws_own_background = true;

    board: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    sq: f32 = 0,

    selected: ?Square = null,
    drag_from: ?Square = null,
    dragging: bool = false,
    press_pos: rl.Vector2 = .{ .x = 0, .y = 0 },

    arrow_from: ?Square = null,
    arrows: [24]Arrow = undefined,
    arrow_count: usize = 0,

    promo_from: ?Square = null,
    promo_to: ?Square = null,

    legal: chess.MoveList = .{},
    show_coords: bool = true,

    pub fn clearArrows(self: *BoardView) void {
        self.arrow_count = 0;
        self.arrow_from = null;
    }

    pub fn clearSelection(self: *BoardView) void {
        self.selected = null;
        self.drag_from = null;
        self.dragging = false;
        self.promo_from = null;
        self.promo_to = null;
    }

    fn colOf(app: *App, sq: Square) f32 {
        const file: f32 = @floatFromInt(chess.utils.fileOf(sq));
        return if (app.flipped) 7 - file else file;
    }

    fn rowOf(app: *App, sq: Square) f32 {
        const rank: f32 = @floatFromInt(chess.utils.rankOf(sq));
        return if (app.flipped) rank else 7 - rank;
    }

    fn squareRect(self: *const BoardView, app: *App, sq: Square) rl.Rectangle {
        return .{
            .x = self.board.x + colOf(app, sq) * self.sq,
            .y = self.board.y + rowOf(app, sq) * self.sq,
            .width = self.sq,
            .height = self.sq,
        };
    }

    fn squareCenter(self: *const BoardView, app: *App, sq: Square) rl.Vector2 {
        const r = self.squareRect(app, sq);
        return .{ .x = r.x + r.width / 2, .y = r.y + r.height / 2 };
    }

    fn squareAt(self: *const BoardView, app: *App, v: rl.Vector2) ?Square {
        if (self.sq <= 0) return null;
        if (!rl.checkCollisionPointRec(v, self.board)) return null;
        const cx: i32 = @intFromFloat((v.x - self.board.x) / self.sq);
        const cy: i32 = @intFromFloat((v.y - self.board.y) / self.sq);
        if (cx < 0 or cx > 7 or cy < 0 or cy > 7) return null;

        const file: u3 = @intCast(if (app.flipped) 7 - cx else cx);
        const rank: u3 = @intCast(if (app.flipped) cy else 7 - cy);
        return chess.pos.squareFromFileRank(file, rank);
    }

    pub fn draw(self: *BoardView, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        rl.drawRectangleRec(bounds, t.bg);

        var area = widget.inset(bounds, 6);
        const show_players = app.match.isRunning() or app.match.state == .finished;

        var top_strip: ?rl.Rectangle = null;
        var bottom_strip: ?rl.Rectangle = null;
        if (show_players and area.height > 240) {
            top_strip = widget.cutTop(&area, 26);
            bottom_strip = widget.cutBottom(&area, 26);
            area.y += 2;
            area.height -= 4;
        }

        var eval_bar: ?rl.Rectangle = null;
        if (app.engines.analysis_on and area.width > 260) {
            eval_bar = widget.cutLeft(&area, 14);
            _ = widget.cutLeft(&area, 6);
        }

        const size = @min(area.width, area.height);
        self.sq = @floor(size / 8);
        const board_size = self.sq * 8;
        self.board = .{
            .x = @round(area.x + (area.width - board_size) / 2),
            .y = @round(area.y + (area.height - board_size) / 2),
            .width = board_size,
            .height = board_size,
        };
        if (self.sq < 8) return;

        app.game.legal(&self.legal);

        self.handleInput(app);

        if (eval_bar) |r| self.drawEvalBar(app, r);
        self.drawSquares(app);
        self.drawHighlights(app);
        self.drawPieces(app);
        self.drawArrows(app);
        self.drawDragged(app);

        if (top_strip) |r| self.drawPlayerStrip(app, r, if (app.flipped) .White else .Black);
        if (bottom_strip) |r| self.drawPlayerStrip(app, r, if (app.flipped) .Black else .White);

        if (self.promo_to != null) self.drawPromotion(app);
        self.drawBanner(app);
    }

    fn drawSquares(self: *BoardView, app: *App) void {
        const t = app.theme;
        for (0..64) |i| {
            const sq: Square = @intCast(i);
            const r = self.squareRect(app, sq);
            const light = (@as(usize, @intCast(chess.utils.fileOf(sq))) + @as(usize, @intCast(chess.utils.rankOf(sq)))) % 2 == 1;
            rl.drawRectangleRec(r, if (light) t.sq_light else t.sq_dark);

            if (!self.show_coords or self.sq < 34) continue;
            const fg = if (light) t.coord_light else t.coord_dark;
            const is_bottom = rowOf(app, sq) == 7;
            const is_left = colOf(app, sq) == 0;

            if (is_bottom) {
                var buf: [4]u8 = undefined;
                buf[0] = 'a' + @as(u8, chess.utils.fileOf(sq));
                buf[1] = 0;
                widget.text(r.x + r.width - 10, r.y + r.height - 15, t.small_font, fg, buf[0..1 :0]);
            }
            if (is_left) {
                var buf: [4]u8 = undefined;
                buf[0] = '1' + @as(u8, chess.utils.rankOf(sq));
                buf[1] = 0;
                widget.text(r.x + 3, r.y + 2, t.small_font, fg, buf[0..1 :0]);
            }
        }
    }

    fn tint(self: *BoardView, app: *App, sq: Square, color: rl.Color, alpha: f32) void {
        rl.drawRectangleRec(self.squareRect(app, sq), rl.fade(color, alpha));
    }

    fn drawHighlights(self: *BoardView, app: *App) void {
        const t = app.theme;
        const pos_now = app.game.boardPosition();

        if (app.game.lastMove()) |m| {
            self.tint(app, m.from, t.hl_last, 0.35);
            self.tint(app, m.to, t.hl_last, 0.45);
        }

        if (!app.game.preview_active and app.game.inCheck()) {
            const king = pos_now.getPieceColorBoard(.King, app.game.sideToMove());
            if (king != 0) self.tint(app, chess.utils.lsb(king), t.hl_check, 0.55);
        }

        if (self.selected) |sel| {
            self.tint(app, sel, t.hl_select, 0.45);
            if (app.show_legal) {
                for (self.legal.slice()) |m| {
                    if (m.from != sel) continue;
                    const r = self.squareRect(app, m.to);
                    const c = rl.Vector2{ .x = r.x + r.width / 2, .y = r.y + r.height / 2 };
                    const occupied = !pos_now.getFromSquare(m.to).isNone() or m.isEP();
                    if (occupied) {
                        rl.drawCircleLinesV(c, self.sq * 0.44, rl.fade(t.hl_select, 0.9));
                        rl.drawCircleLinesV(c, self.sq * 0.42, rl.fade(t.hl_select, 0.9));
                    } else {
                        rl.drawCircleV(c, self.sq * 0.14, rl.fade(t.hl_select, 0.65));
                    }
                }
            }
        }

        if (self.dragging) {
            if (self.squareAt(app, rl.getMousePosition())) |over| {
                const r = self.squareRect(app, over);
                rl.drawRectangleLinesEx(r, 3, rl.fade(t.hl_hover, 0.8));
            }
        }
    }

    fn drawPieces(self: *BoardView, app: *App) void {
        const t = app.theme;
        const p = app.game.boardPosition();
        const psize = self.sq * 0.86;

        for (0..64) |i| {
            const sq: Square = @intCast(i);
            const piece = p.getFromSquare(sq);
            if (piece.isNone()) continue;

            const c = self.squareCenter(app, sq);
            if (self.dragging and self.drag_from == sq) {
                pieces.drawGhost(piece.piece, piece.color, c.x, c.y, psize, t);
            } else {
                pieces.draw(piece.piece, piece.color, c.x, c.y, psize, t);
            }
        }
    }

    fn drawDragged(self: *BoardView, app: *App) void {
        if (!self.dragging) return;
        const from = self.drag_from orelse return;
        const piece = app.game.boardPosition().getFromSquare(from);
        if (piece.isNone()) return;

        const m = rl.getMousePosition();
        pieces.draw(piece.piece, piece.color, m.x, m.y, self.sq * 0.95, app.theme);
    }

    fn drawArrows(self: *BoardView, app: *App) void {
        const t = app.theme;

        if (app.show_pv_arrows) {
            var drawn: usize = 0;
            for (app.engines.slice()) |*e| {
                if (e.owner != .analysis or e.pv_count == 0) continue;
                for (e.pv[0..e.pv_count], 0..) |*line, i| {
                    if (!line.valid or drawn >= 4) continue;
                    const uci_text = line.firstMoveUci();
                    if (uci_text.len < 4) continue;
                    const from = chess.utils.squareFromString(uci_text[0..2]) orelse continue;
                    const to = chess.utils.squareFromString(uci_text[2..4]) orelse continue;
                    const col = if (i == 0) t.arrow_pv else t.arrow_pv_alt;
                    const alpha: f32 = if (i == 0) 0.75 else 0.4;
                    self.arrow(app, from, to, rl.fade(col, alpha), if (i == 0) 0.16 else 0.11);
                    drawn += 1;
                }
                if (drawn >= 4) break;
            }
        }

        for (self.arrows[0..self.arrow_count]) |a| {
            self.arrow(app, a.from, a.to, rl.fade(a.color, 0.8), 0.16);
        }

        if (self.arrow_from) |from| {
            if (self.squareAt(app, rl.getMousePosition())) |to| {
                if (to != from) self.arrow(app, from, to, rl.fade(t.arrow_user, 0.5), 0.16);
            }
        }
    }

    fn arrow(self: *BoardView, app: *App, from: Square, to: Square, color: rl.Color, thickness: f32) void {
        const a = self.squareCenter(app, from);
        const b = self.squareCenter(app, to);

        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 1) return;

        const ux = dx / len;
        const uy = dy / len;
        const head = self.sq * 0.34;
        const shaft = self.sq * thickness;

        const tip = rl.Vector2{ .x = b.x - ux * self.sq * 0.06, .y = b.y - uy * self.sq * 0.06 };
        const neck = rl.Vector2{ .x = tip.x - ux * head, .y = tip.y - uy * head };
        const start = rl.Vector2{ .x = a.x + ux * self.sq * 0.18, .y = a.y + uy * self.sq * 0.18 };

        rl.drawLineEx(start, neck, shaft, color);

        const px = -uy;
        const py = ux;
        widget.tri(
            tip,
            .{ .x = neck.x + px * head * 0.55, .y = neck.y + py * head * 0.55 },
            .{ .x = neck.x - px * head * 0.55, .y = neck.y - py * head * 0.55 },
            color,
        );
    }

    fn drawEvalBar(self: *BoardView, app: *App, area: rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        var r = area;
        r.height = @min(r.height, area.height);

        var score: ?chess.uci.Score = null;
        for (app.engines.slice()) |*e| {
            if (e.owner != .analysis) continue;
            if (e.whitePovScore()) |s| {
                score = s;
                break;
            }
        }

        rl.drawRectangleRec(r, t.piece_black);
        const cp: f32 = if (score) |s| @floatFromInt(s.toCp()) else 0;
        const frac = 0.5 + 0.5 * std.math.tanh(cp / 400.0);
        const white_h = r.height * std.math.clamp(frac, 0.02, 0.98);

        rl.drawRectangleRec(.{
            .x = r.x,
            .y = r.y + r.height - white_h,
            .width = r.width,
            .height = white_h,
        }, t.piece_white);

        rl.drawRectangleRec(.{ .x = r.x, .y = r.y + r.height / 2, .width = r.width, .height = 1 }, t.border);
    }

    fn drawPlayerStrip(self: *BoardView, app: *App, r: rl.Rectangle, side: Color) void {
        _ = self;
        const t = app.theme;
        const m = &app.match;

        const name = if (side == .White) app.game.whiteName() else app.game.blackName();
        var nbuf: [64]u8 = undefined;
        const to_move = app.game.sideToMove();
        const active = m.state == .playing and to_move == side;

        widget.frame(r, 0.2, if (active) t.panel_alt else t.panel, if (active) t.accent else t.border);

        const dot = rl.Rectangle{ .x = r.x + 8, .y = r.y + r.height / 2 - 5, .width = 10, .height = 10 };
        rl.drawRectangleRec(dot, if (side == .White) t.piece_white else t.piece_black);
        rl.drawRectangleLinesEx(dot, 1, t.border);

        widget.text(
            r.x + 26,
            r.y + (r.height - t.smallF()) / 2,
            t.small_font,
            if (active) t.text_bright else t.text,
            widget.zSlice(&nbuf, name),
        );

        if (m.tc.kind.usesClock() and m.state != .idle) {
            var cbuf: [24]u8 = undefined;
            var zbuf: [24]u8 = undefined;
            const ms = m.remaining(side, to_move);
            const label = widget.zSlice(&zbuf, match_mod.clockText(&cbuf, ms));
            const col = if (ms < 10_000) t.bad else if (active) t.text_bright else t.text_dim;
            widget.textRight(r.x + r.width - 10, r.y + (r.height - t.fontF()) / 2, t.font_size, col, label);
        }
    }

    fn drawPromotion(self: *BoardView, app: *App) void {
        const t = app.theme;
        const to = self.promo_to orelse return;

        rl.drawRectangleRec(self.board, rl.fade(t.bg, 0.55));

        const mover = app.game.sideToMove();
        const choices = [_]chess.Pieces{ .Queen, .Knight, .Rook, .Bishop };

        const col = colOf(app, to);
        const going_down = rowOf(app, to) > 3.5;
        const start_row: f32 = if (going_down) 4 else 0;

        for (choices, 0..) |kind, i| {
            const idx: f32 = @floatFromInt(i);
            const row_pos = if (going_down) start_row + (3 - idx) else start_row + idx;
            const r = rl.Rectangle{
                .x = self.board.x + col * self.sq,
                .y = self.board.y + row_pos * self.sq,
                .width = self.sq,
                .height = self.sq,
            };
            const over = widget.hovered(r);
            rl.drawRectangleRec(r, if (over) t.accent_dim else t.panel_alt);
            rl.drawRectangleLinesEx(r, 1, if (over) t.accent else t.border);
            pieces.draw(kind, mover, r.x + r.width / 2, r.y + r.height / 2, self.sq * 0.82, t);

            if (widget.clicked(r)) {
                const from = self.promo_from.?;
                _ = app.tryUserMove(from, to, kind);
                self.promo_from = null;
                self.promo_to = null;
                self.clearSelection();
                return;
            }
        }

        if (rl.isMouseButtonPressed(.right) or rl.isKeyPressed(.escape)) {
            self.promo_from = null;
            self.promo_to = null;
        }
    }

    fn drawBanner(self: *BoardView, app: *App) void {
        const t = app.theme;
        const st = app.game.status();
        const finished = app.match.state == .finished;
        if (!st.isOver() and !finished) return;

        var buf: [96]u8 = undefined;
        const label: [:0]const u8 = if (st.isOver())
            widget.zBuf(&buf, "{s}", .{st.label()})
        else
            widget.zBuf(&buf, "match finished  {d} - {d} - {d}", .{
                app.match.p1_wins,
                app.match.p2_wins,
                app.match.draws,
            });

        const w = widget.measure(label, t.font_size) + 32;
        const r = rl.Rectangle{
            .x = self.board.x + (self.board.width - w) / 2,
            .y = self.board.y + self.board.height / 2 - 20,
            .width = w,
            .height = 34,
        };
        widget.frame(r, 0.3, rl.fade(t.panel, 0.94), t.accent);
        widget.textCentered(r.x + r.width / 2, r.y + (r.height - t.fontF()) / 2, t.font_size, t.text_bright, label);
    }

    fn handleInput(self: *BoardView, app: *App) void {
        if (self.promo_to != null) return;

        const mouse = rl.getMousePosition();
        const over_board = rl.checkCollisionPointRec(mouse, self.board);
        const hovered_sq = self.squareAt(app, mouse);

        if (over_board) {
            const wheel = rl.getMouseWheelMove();
            if (wheel > 0.5) app.game.back();
            if (wheel < -0.5) app.game.forward();
        }

        if (over_board and rl.isMouseButtonPressed(.right)) {
            self.arrow_from = hovered_sq;
        }
        if (rl.isMouseButtonReleased(.right)) {
            if (self.arrow_from) |from| {
                if (hovered_sq) |to| {
                    if (to == from) {
                        self.clearArrows();
                    } else {
                        self.addArrow(from, to, app.theme.arrow_user);
                    }
                }
            }
            self.arrow_from = null;
        }

        if (!app.boardInteractive()) {
            self.selected = null;
            self.dragging = false;
            self.drag_from = null;
            return;
        }

        const p = app.game.boardPosition();
        const stm = app.game.sideToMove();

        if (over_board and rl.isMouseButtonPressed(.left)) {
            const sq = hovered_sq orelse return;
            self.press_pos = mouse;

            if (self.selected) |sel| {
                if (sel != sq and self.hasLegal(sel, sq)) {
                    self.beginMove(app, sel, sq);
                    return;
                }
            }

            const piece = p.getFromSquare(sq);
            if (!piece.isNone() and piece.color == stm) {
                self.selected = sq;
                self.drag_from = sq;
                self.dragging = true;
                app.game.clearPreview();
            } else if (self.selected != null) {
                self.selected = null;
            }
            return;
        }

        if (self.dragging and rl.isMouseButtonReleased(.left)) {
            self.dragging = false;
            const from = self.drag_from orelse return;
            self.drag_from = null;

            const to = hovered_sq orelse {
                self.selected = null;
                return;
            };
            if (to == from) {
                return;
            }
            if (self.hasLegal(from, to)) {
                self.beginMove(app, from, to);
            } else {
                self.selected = null;
            }
        }
    }

    fn hasLegal(self: *BoardView, from: Square, to: Square) bool {
        for (self.legal.slice()) |m| {
            if (m.from == from and m.to == to) return true;
        }
        return false;
    }

    fn beginMove(self: *BoardView, app: *App, from: Square, to: Square) void {
        var promo = false;
        for (self.legal.slice()) |m| {
            if (m.from == from and m.to == to and m.isPromo()) promo = true;
        }
        if (promo) {
            self.promo_from = from;
            self.promo_to = to;
            self.dragging = false;
            return;
        }
        _ = app.tryUserMove(from, to, null);
        self.selected = null;
    }

    fn addArrow(self: *BoardView, from: Square, to: Square, color: rl.Color) void {
        for (self.arrows[0..self.arrow_count], 0..) |a, i| {
            if (a.from == from and a.to == to) {
                var j = i;
                while (j + 1 < self.arrow_count) : (j += 1) self.arrows[j] = self.arrows[j + 1];
                self.arrow_count -= 1;
                return;
            }
        }
        if (self.arrow_count >= self.arrows.len) return;
        self.arrows[self.arrow_count] = .{ .from = from, .to = to, .color = color };
        self.arrow_count += 1;
    }
};
