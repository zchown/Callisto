const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");

pub const MovesPanel = struct {
    scroll: widget.Scroll = .{},
    last_cursor: usize = std.math.maxInt(usize),

    const row_h: f32 = 22;

    pub fn draw(self: *MovesPanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        var area = widget.inset(bounds, 6);

        const bar = widget.cutTop(&area, 26);
        self.drawNavBar(app, bar);
        _ = widget.cutTop(&area, 4);

        const g = &app.game;
        if (g.count == 0) {
            widget.text(area.x + 4, area.y + 6, t.small_font, t.text_dim, "no moves yet");
            return;
        }

        const first_full = fullMoveOf(g.root.ply, isWhitePly(g.root.ply));
        const rows = rowCount(g);
        const content_h = @as(f32, @floatFromInt(rows)) * row_h;

        self.scroll.handle(area, content_h);

        if (self.last_cursor != g.cursor) {
            self.last_cursor = g.cursor;
            if (g.cursor > 0) {
                const idx = g.cursor - 1;
                const r = rowOf(g, idx, first_full);
                self.scroll.revealRow(area, @as(f32, @floatFromInt(r)) * row_h, row_h);
            } else {
                self.scroll.offset = 0;
            }
        }

        rl.beginScissorMode(
            @intFromFloat(area.x),
            @intFromFloat(area.y),
            @intFromFloat(@max(area.width, 0)),
            @intFromFloat(@max(area.height, 0)),
        );
        defer rl.endScissorMode();

        const num_w: f32 = 40;
        const cell_w = @max((area.width - num_w - 8) / 2, 40);

        var r: usize = 0;
        while (r < rows) : (r += 1) {
            const y = area.y + @as(f32, @floatFromInt(r)) * row_h - self.scroll.offset;
            if (y + row_h < area.y or y > area.y + area.height) continue;

            const row_rect = rl.Rectangle{ .x = area.x, .y = y, .width = area.width, .height = row_h };
            if (r % 2 == 1) rl.drawRectangleRec(row_rect, t.row_alt);

            var nbuf: [16]u8 = undefined;
            widget.text(
                area.x + 4,
                y + (row_h - t.smallF()) / 2,
                t.small_font,
                t.text_dim,
                widget.zBuf(&nbuf, "{d}.", .{first_full + r}),
            );

            for (0..2) |col| {
                const idx = plyIndexAt(g, r, col, first_full) orelse continue;
                const cell = rl.Rectangle{
                    .x = area.x + num_w + @as(f32, @floatFromInt(col)) * cell_w,
                    .y = y,
                    .width = cell_w,
                    .height = row_h,
                };
                self.drawCell(app, cell, idx);
            }
        }

        self.scroll.drawBar(t, area, content_h);
    }

    fn drawCell(self: *MovesPanel, app: *App, cell: rl.Rectangle, idx: usize) void {
        _ = self;
        const t = app.theme;
        const g = &app.game;
        const ply = g.plyAt(idx) orelse return;

        const is_current = g.cursor == idx + 1;
        const over = widget.hovered(cell);

        if (is_current) {
            widget.frame(cell, 0.2, t.accent_dim, t.accent);
        } else if (over) {
            rl.drawRectangleRec(cell, t.panel_alt);
        }

        var sbuf: [24]u8 = undefined;
        widget.text(
            cell.x + 6,
            cell.y + (cell.height - t.smallF()) / 2,
            t.small_font,
            if (is_current) t.text_bright else t.text,
            widget.zSlice(&sbuf, ply.sanSlice()),
        );

        if (ply.has_eval) {
            var ebuf: [16]u8 = undefined;
            const label = if (ply.eval_is_mate)
                widget.zBuf(&ebuf, "#{d}", .{ply.eval_mate})
            else
                widget.zBuf(&ebuf, "{d:.2}", .{@as(f32, @floatFromInt(ply.eval_cp)) / 100.0});
            widget.textRight(
                cell.x + cell.width - 6,
                cell.y + (cell.height - t.smallF()) / 2,
                t.small_font,
                t.evalColor(ply.eval_cp),
                label,
            );
        }

        if (widget.clicked(cell)) g.goto(idx + 1);
    }

    fn drawNavBar(self: *MovesPanel, app: *App, bar: rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        const g = &app.game;

        var r = bar;
        const bw: f32 = 34;
        const b1 = widget.cutLeft(&r, bw);
        _ = widget.cutLeft(&r, 3);
        const b2 = widget.cutLeft(&r, bw);
        _ = widget.cutLeft(&r, 3);
        const b3 = widget.cutLeft(&r, bw);
        _ = widget.cutLeft(&r, 3);
        const b4 = widget.cutLeft(&r, bw);

        if (widget.button(t, b1, "|<", .normal)) g.toStart();
        if (widget.button(t, b2, "<", .normal)) g.back();
        if (widget.button(t, b3, ">", .normal)) g.forward();
        if (widget.button(t, b4, ">|", .normal)) g.toEnd();

        var buf: [64]u8 = undefined;
        widget.textRight(
            bar.x + bar.width,
            bar.y + (bar.height - t.smallF()) / 2,
            t.small_font,
            t.text_dim,
            widget.zBuf(&buf, "ply {d}/{d}", .{ g.cursor, g.count }),
        );
    }

    fn isWhitePly(ply: usize) bool {
        return ply % 2 == 1;
    }

    fn fullMoveOf(ply: usize, white: bool) usize {
        return (ply + @intFromBool(white)) / 2;
    }

    fn rowOf(g: *const @import("../../game.zig").Game, idx: usize, first_full: usize) usize {
        const abs = g.root.ply + idx;
        const full = fullMoveOf(abs, isWhitePly(abs));
        return if (full >= first_full) full - first_full else 0;
    }

    fn rowCount(g: *const @import("../../game.zig").Game) usize {
        if (g.count == 0) return 0;
        const first_full = fullMoveOf(g.root.ply, isWhitePly(g.root.ply));
        const last = rowOf(g, g.count - 1, first_full);
        return last + 1;
    }

    fn plyIndexAt(g: *const @import("../../game.zig").Game, row: usize, col: usize, first_full: usize) ?usize {
        const full = first_full + row;
        if (full == 0) return null;
        const abs = if (col == 0) full * 2 - 1 else full * 2;
        if (abs < g.root.ply) return null;
        const idx = abs - g.root.ply;
        if (idx >= g.count) return null;
        return idx;
    }
};
