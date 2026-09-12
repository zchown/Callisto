const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../app.zig").App;
const widget = @import("widget.zig");
const pieces = @import("pieces.zig");
const theme_mod = @import("theme.zig");
const match_mod = @import("../match.zig");
const mini_board = @import("mini_board.zig");
const engine_mod = @import("../engine/engine.zig");

const Theme = theme_mod.Theme;

pub const default_line: f32 = 22;
pub const default_gap: f32 = 4;

pub const Ui = struct {
    app: *App,
    area: rl.Rectangle,
    offset: f32 = 0,

    used: f32 = 0,
    indent: f32 = 0,
    gap: f32 = default_gap,
    line: f32 = default_line,

    in_row: bool = false,
    row: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    row_height: f32 = default_line,
    next_w: f32 = 0,

    fault: bool = false,

    pub fn init(app: *App, area: rl.Rectangle, offset: f32) Ui {
        return .{ .app = app, .area = area, .offset = offset };
    }

    pub fn theme(self: *const Ui) Theme {
        return self.app.theme;
    }

    pub fn contentHeight(self: *const Ui) f32 {
        return self.used;
    }

    pub fn take(self: *Ui, h: f32, want_w: f32) rl.Rectangle {
        if (self.in_row) {
            var w = if (self.next_w > 0) self.next_w else want_w;
            self.next_w = 0;
            if (w <= 0 or w > self.row.width) w = self.row.width;
            const r = widget.cutLeft(&self.row, w);
            _ = widget.cutLeft(&self.row, self.gap);
            return .{ .x = r.x, .y = r.y, .width = r.width, .height = @min(h, self.row_height) };
        }

        self.next_w = 0;
        const r = rl.Rectangle{
            .x = self.area.x + self.indent,
            .y = self.area.y + self.used - self.offset,
            .width = @max(self.area.width - self.indent, 0),
            .height = h,
        };
        self.used += h + self.gap;
        return r;
    }

    pub fn visible(self: *const Ui, r: rl.Rectangle) bool {
        return r.y + r.height >= self.area.y and r.y <= self.area.y + self.area.height;
    }

    pub fn setWidth(self: *Ui, w: f32) void {
        self.next_w = w;
    }

    pub fn beginRow(self: *Ui, h: f32) void {
        if (self.in_row) self.endRow();
        self.row_height = if (h > 0) h else self.line;
        self.row = .{
            .x = self.area.x + self.indent,
            .y = self.area.y + self.used - self.offset,
            .width = @max(self.area.width - self.indent, 0),
            .height = self.row_height,
        };
        self.in_row = true;
    }

    pub fn endRow(self: *Ui) void {
        if (!self.in_row) return;
        self.in_row = false;
        self.used += self.row_height + self.gap;
    }

    pub fn finish(self: *Ui) void {
        if (self.in_row) self.endRow();
    }

    pub fn spacing(self: *Ui, px: f32) void {
        if (self.in_row) {
            _ = widget.cutLeft(&self.row, px);
        } else {
            self.used += px;
        }
    }

    pub fn remainingWidth(self: *const Ui) f32 {
        if (self.in_row) return self.row.width;
        return @max(self.area.width - self.indent, 0);
    }

    pub fn text(self: *Ui, s: []const u8) void {
        const t = self.theme();
        const r = self.take(self.line, 0);
        if (!self.visible(r)) return;

        var buf: [512]u8 = undefined;
        var clip: [528]u8 = undefined;
        widget.textClipped(
            r.x,
            r.y + (r.height - t.smallF()) / 2,
            r.width,
            t.small_font,
            t.text,
            widget.zSlice(&buf, s),
            &clip,
        );
    }

    pub fn heading(self: *Ui, s: []const u8) void {
        const t = self.theme();
        const r = self.take(self.line + 6, 0);
        if (!self.visible(r)) return;

        var buf: [256]u8 = undefined;
        widget.text(r.x, r.y + 2, t.font_size, t.text_bright, widget.zSlice(&buf, s));
    }

    pub fn dim(self: *Ui, s: []const u8) void {
        const t = self.theme();
        const r = self.take(self.line, 0);
        if (!self.visible(r)) return;

        var buf: [512]u8 = undefined;
        var clip: [528]u8 = undefined;
        widget.textClipped(
            r.x,
            r.y + (r.height - t.smallF()) / 2,
            r.width,
            t.small_font,
            t.text_dim,
            widget.zSlice(&buf, s),
            &clip,
        );
    }

    pub fn label(self: *Ui, key: []const u8, value: []const u8, tone: Tone) void {
        const t = self.theme();
        const r = self.take(self.line, 0);
        if (!self.visible(r)) return;

        var kbuf: [128]u8 = undefined;
        var vbuf: [256]u8 = undefined;
        widget.stat(
            t,
            r,
            widget.zSlice(&kbuf, key),
            widget.zSlice(&vbuf, value),
            tone.color(t),
        );
    }

    pub fn separator(self: *Ui) void {
        const t = self.theme();
        const r = self.take(7, 0);
        if (!self.visible(r)) return;
        widget.separator(t, r.x, r.y + 3, r.width);
    }

    pub fn button(self: *Ui, text_label: []const u8, style: widget.Style) bool {
        const t = self.theme();
        var buf: [128]u8 = undefined;
        const z = widget.zSlice(&buf, text_label);
        const want = widget.measure(z, t.font_size) + 26;

        const r = self.take(self.line + 4, want);
        if (!self.visible(r)) return false;
        return widget.button(t, r, z, style);
    }

    pub fn checkbox(self: *Ui, text_label: []const u8, value: bool) struct { value: bool, changed: bool } {
        const t = self.theme();
        var buf: [128]u8 = undefined;
        const z = widget.zSlice(&buf, text_label);
        const want = widget.measure(z, t.small_font) + 30;

        const r = self.take(self.line, want);
        if (!self.visible(r)) return .{ .value = value, .changed = false };

        var v = value;
        const changed = widget.checkBox(t, r, z, &v);
        return .{ .value = v, .changed = changed };
    }

    pub fn slider(self: *Ui, text_label: []const u8, value: f32, min: f32, max: f32) struct { value: f32, changed: bool } {
        const t = self.theme();
        const r = self.take(self.line, 0);
        if (!self.visible(r)) return .{ .value = value, .changed = false };

        var body = r;
        if (text_label.len > 0) {
            const lab = widget.cutLeft(&body, @min(r.width * 0.45, 120));
            var buf: [96]u8 = undefined;
            widget.textIn(lab, 0, t.small_font, t.text_dim, widget.zSlice(&buf, text_label));
        }

        const track = rl.Rectangle{
            .x = body.x,
            .y = body.y + body.height / 2 - 3,
            .width = @max(body.width - 44, 20),
            .height = 6,
        };
        const span = @max(max - min, 0.0001);
        var v = std.math.clamp(value, min, max);
        var changed = false;

        if (widget.hovered(body) and rl.isMouseButtonDown(.left)) {
            const local = (rl.getMousePosition().x - track.x) / track.width;
            const nv = min + std.math.clamp(local, 0, 1) * span;
            if (nv != v) {
                v = nv;
                changed = true;
            }
        }

        const frac = (v - min) / span;
        widget.progress(t, track, frac, t.accent);
        const knob = rl.Vector2{ .x = track.x + track.width * frac, .y = track.y + 3 };
        rl.drawCircleV(knob, 6, t.text_bright);

        var vbuf: [24]u8 = undefined;
        widget.textRight(
            body.x + body.width,
            body.y + (body.height - t.smallF()) / 2,
            t.small_font,
            t.text,
            widget.zBuf(&vbuf, "{d:.0}", .{v}),
        );

        return .{ .value = v, .changed = changed };
    }

    pub fn input(self: *Ui, id: []const u8, initial: []const u8, placeholder: []const u8) struct {
        value: []const u8,
        submitted: bool,
    } {
        const t = self.theme();
        const slot = inputFor(id, initial);
        const r = self.take(self.line + 4, 0);
        if (!self.visible(r)) return .{ .value = slot.slice(), .submitted = false };

        var pbuf: [96]u8 = undefined;
        const submitted = slot.draw(t, r, widget.zSlice(&pbuf, placeholder));
        if (slot.focused) widget.keyboard_captured = true;
        return .{ .value = slot.slice(), .submitted = submitted };
    }

    pub fn badge(self: *Ui, text_label: []const u8, tone: Tone) void {
        const t = self.theme();
        var buf: [96]u8 = undefined;
        const z = widget.zSlice(&buf, text_label);
        const want = widget.measure(z, t.small_font) + 16;

        const r = self.take(self.line, want);
        if (!self.visible(r)) return;

        const fg = tone.color(t);
        _ = widget.badge(t, r.x, r.y + 2, z, fg, t.panel_alt);
    }

    pub fn progressBar(self: *Ui, frac: f32, tone: Tone) void {
        const t = self.theme();
        const r = self.take(10, 0);
        if (!self.visible(r)) return;
        widget.progress(t, .{ .x = r.x, .y = r.y + 2, .width = r.width, .height = 6 }, frac, tone.color(t));
    }

    pub fn engineLines(self: *Ui, max_lines: usize) void {
        const t = self.theme();
        const app = self.app;

        var shown: usize = 0;
        for (app.engines.slice()) |*e| {
            if (e.owner != .analysis) continue;

            self.beginRow(self.line);
            var nbuf: [64]u8 = undefined;
            const head = self.take(self.line, self.remainingWidth() * 0.5);
            if (self.visible(head)) {
                widget.textIn(head, 0, t.small_font, t.text_bright, widget.zSlice(&nbuf, e.nameSlice()));
            }
            var sbuf: [64]u8 = undefined;
            const stats = self.take(self.line, self.remainingWidth());
            if (self.visible(stats)) {
                widget.textRight(
                    stats.x + stats.width,
                    stats.y + (stats.height - t.smallF()) / 2,
                    t.small_font,
                    t.text_dim,
                    widget.zBuf(&sbuf, "d{d}  {d} kn/s", .{ e.depth, e.nps / 1000 }),
                );
            }
            self.endRow();

            for (e.pv[0..e.pv_count], 0..) |*pv, i| {
                if (!pv.valid or shown >= max_lines) break;
                shown += 1;

                const r = self.take(self.line, 0);
                if (!self.visible(r)) continue;

                const over = widget.hovered(r);
                if (over) rl.drawRectangleRec(r, t.panel_alt);

                const y = r.y + (r.height - t.smallF()) / 2;

                if (pv.score) |raw| {
                    const s = if (e.have_root and e.search_root.to_move == .Black) raw.negate() else raw;
                    var fbuf: [16]u8 = undefined;
                    var zbuf: [16]u8 = undefined;
                    widget.text(r.x + 4, y, t.small_font, t.evalColor(s.toCp()), widget.zSlice(&zbuf, s.format(&fbuf)));
                }

                var line_buf: [engine_mod.max_pv_san + 1]u8 = undefined;
                var clip_buf: [engine_mod.max_pv_san + 8]u8 = undefined;
                const body = if (pv.san_len > 0) pv.sanSlice() else pv.uciSlice();
                widget.textClipped(
                    r.x + 58,
                    y,
                    @max(r.width - 62, 20),
                    t.small_font,
                    if (i == 0) t.text else t.text_dim,
                    widget.zSlice(&line_buf, body),
                    &clip_buf,
                );

                if (over) {
                    app.game.setPreview(pv.uciSlice(), 12);
                    if (widget.clicked(r)) {
                        app.game.playLine(pv.uciSlice(), 12);
                        app.engines.analysis_hash = 0;
                    }
                }
            }
        }

        if (shown == 0) self.dim("no analysis running");
    }

    pub fn moveList(self: *Ui, rows_max: usize) void {
        const t = self.theme();
        const g = &self.app.game;
        if (g.count == 0) {
            self.dim("no moves yet");
            return;
        }

        const first_abs = g.root.ply;
        const first_full = (first_abs + @intFromBool(first_abs % 2 == 1)) / 2;

        var row_index: usize = 0;
        while (row_index < rows_max) : (row_index += 1) {
            const full = first_full + row_index;
            if (full == 0) continue;

            const white_idx = indexForAbs(g, full * 2 - 1);
            const black_idx = indexForAbs(g, full * 2);
            if (white_idx == null and black_idx == null) break;

            const r = self.take(self.line, 0);
            if (!self.visible(r)) continue;
            if (row_index % 2 == 1) rl.drawRectangleRec(r, t.row_alt);

            var body = r;
            const num = widget.cutLeft(&body, 40);
            var nbuf: [16]u8 = undefined;
            widget.textIn(num, 2, t.small_font, t.text_dim, widget.zBuf(&nbuf, "{d}.", .{full}));

            const cell_w = body.width / 2;
            self.moveCell(widget.cutLeft(&body, cell_w), white_idx);
            self.moveCell(body, black_idx);
        }
    }

    fn moveCell(self: *Ui, cell: rl.Rectangle, idx: ?usize) void {
        const t = self.theme();
        const g = &self.app.game;
        const i = idx orelse return;
        const ply = g.plyAt(i) orelse return;

        const current = g.cursor == i + 1;
        const over = widget.hovered(cell);
        if (current) {
            widget.frame(cell, 5, t.accent_dim, t.accent);
        } else if (over) {
            rl.drawRectangleRec(cell, t.panel_alt);
        }

        var sbuf: [24]u8 = undefined;
        widget.textIn(cell, 6, t.small_font, if (current) t.text_bright else t.text, widget.zSlice(&sbuf, ply.sanSlice()));

        if (ply.has_eval) {
            var ebuf: [16]u8 = undefined;
            const label_text = if (ply.eval_is_mate)
                widget.zBuf(&ebuf, "#{d}", .{ply.eval_mate})
            else
                widget.zBuf(&ebuf, "{d:.2}", .{@as(f32, @floatFromInt(ply.eval_cp)) / 100.0});
            widget.textRight(
                cell.x + cell.width - 6,
                cell.y + (cell.height - t.smallF()) / 2,
                t.small_font,
                t.evalColor(ply.eval_cp),
                label_text,
            );
        }

        if (widget.clicked(cell)) g.goto(i + 1);
    }

    fn indexForAbs(g: *const @import("../game.zig").Game, abs: usize) ?usize {
        if (abs < g.root.ply) return null;
        const idx = abs - g.root.ply;
        if (idx >= g.count) return null;
        return idx;
    }


    pub const CardOptions = struct {
        engine: ?usize = null,
        side: ?chess.Color = null,
        name: []const u8 = "",
        lines: usize = 1,
        board: bool = true,
        clock: bool = false,
    };

    pub fn engineCard(self: *Ui, opts: CardOptions) void {
        const t = self.theme();
        const e = if (opts.engine) |i| self.app.engines.get(i) else null;

        const line_h: f32 = 18;
        const listed = if (e == null) 0 else @max(opts.lines, 1);
        const want_board = opts.board and e != null;

        const pv_text_h = @as(f32, @floatFromInt(listed)) * line_h + 20;
        const pv_h = if (want_board) @max(pv_text_h, 146) else pv_text_h;

        const height: f32 = if (e == null)
            78
        else
            44 + 62 + 46 + pv_h + 26;

        const outer = self.take(height, 0);
        if (!self.visible(outer)) return;

        widget.frame(outer, t.card_radius_px, t.panel, t.border_soft);
        var body = widget.inset(outer, 14);

        self.cardHeader(&body, opts, e);

        const engine = e orelse return;

        self.cardEval(&body, engine);
        self.cardStats(&body, engine);

        widget.separator(t, body.x, body.y, body.width);
        body.y += 8;
        body.height -= 8;

        var pv_area = widget.cutTop(&body, pv_h);
        if (want_board and pv_area.width > 300) {
            const board_side = @min(pv_area.height, 146);
            const board_rect = widget.cutRight(&pv_area, board_side);
            _ = widget.cutRight(&pv_area, 12);
            self.cardBoard(board_rect, engine, opts);
        }
        self.cardLines(pv_area, engine, listed, line_h);
    }

    fn cardHeader(self: *Ui, body: *rl.Rectangle, opts: CardOptions, e: ?*engine_mod.Engine) void {
        const t = self.theme();
        const row = widget.cutTop(body, 44);

        var caps: [24]u8 = undefined;
        const side_text: []const u8 = if (opts.side) |c|
            (if (c == .White) "WHITE" else "BLACK")
        else
            "ENGINE";
        widget.text(row.x, row.y, t.small_font - 1, t.text_dim, widget.zSlice(&caps, side_text));

        var name_buf: [64]u8 = undefined;
        var clip: [80]u8 = undefined;
        const name = if (e) |eng| eng.nameSlice() else if (opts.name.len > 0) opts.name else "Human";
        widget.textClipped(
            row.x,
            row.y + 17,
            row.width - 110,
            t.font_size,
            t.text_bright,
            widget.zSlice(&name_buf, name),
            &clip,
        );

        if (opts.clock and opts.side != null and self.app.match.state != .idle) {
            widget.textRight(row.x + row.width, row.y, t.small_font - 1, t.text_dim, "TIME");

            var cb: [24]u8 = undefined;
            var cz: [24]u8 = undefined;
            const to_move = self.app.game.sideToMove();
            const ms = self.app.match.remaining(opts.side.?, to_move);
            const active = self.app.match.state == .playing and to_move == opts.side.?;
            widget.textRight(
                row.x + row.width,
                row.y + 17,
                t.font_size,
                if (ms < 10_000) t.bad else if (active) t.text_bright else t.text,
                widget.zSlice(&cz, match_mod.clockText(&cb, ms)),
            );
        } else if (e) |eng| {
            widget.textRight(row.x + row.width, row.y + 17, t.small_font, t.text_dim, eng.status.label());
        }
    }

    fn cardEval(self: *Ui, body: *rl.Rectangle, e: *engine_mod.Engine) void {
        const t = self.theme();
        const block = widget.cutTop(body, 62);
        const cx = block.x + block.width / 2;

        widget.textCentered(cx, block.y + 2, t.small_font - 1, t.text_dim, "EVALUATION");

        var buf: [16]u8 = undefined;
        var zbuf: [20]u8 = undefined;
        var card_label: [:0]const u8 = "-";
        var color = t.text_dim;

        if (e.whitePovScore()) |score| {
            card_label = widget.zSlice(&zbuf, score.format(&buf));
            color = switch (score) {
                .cp => |v| if (v > 30) t.good else if (v < -30) t.bad else t.text,
                .mate => |v| if (v >= 0) t.good else t.bad,
            };
        }
        widget.textCentered(cx, block.y + 20, t.title_font + 6, color, card_label);
    }

    fn cardStats(self: *Ui, body: *rl.Rectangle, e: *engine_mod.Engine) void {
        const t = self.theme();
        const row = widget.cutTop(body, 46);
        const col_w = row.width / 4;

        var depth_buf: [24]u8 = undefined;
        var nodes_buf: [24]u8 = undefined;
        var nps_buf: [24]u8 = undefined;
        var hash_buf: [24]u8 = undefined;

        const depth = widget.zBuf(&depth_buf, "{d}/{d}", .{ e.depth, e.seldepthOf() });
        var n_raw: [16]u8 = undefined;
        var s_raw: [16]u8 = undefined;
        const nodes = widget.zSlice(&nodes_buf, fmtCount(&n_raw, e.nodes));
        const nps = widget.zSlice(&nps_buf, fmtCount(&s_raw, e.nps));
        const hash = if (e.hashfull > 0)
            widget.zBuf(&hash_buf, "{d}.{d}%", .{ e.hashfull / 10, e.hashfull % 10 })
        else
            widget.zBuf(&hash_buf, "-", .{});

        const labels = [_][:0]const u8{ "DEPTH", "NODES", "NPS", "HASHFULL" };
        const values = [_][:0]const u8{ depth, nodes, nps, hash };

        for (labels, values, 0..) |l, value, i| {
            const x = row.x + @as(f32, @floatFromInt(i)) * col_w;
            widget.text(x, row.y + 2, t.small_font - 1, t.text_dim, l);
            widget.text(x, row.y + 19, t.font_size, t.text, value);
            if (i > 0) {
                rl.drawRectangleRec(
                    .{ .x = x - 6, .y = row.y + 2, .width = 1, .height = 30 },
                    t.border_soft,
                );
            }
        }
    }

    fn cardBoard(self: *Ui, r: rl.Rectangle, e: *engine_mod.Engine, opts: CardOptions) void {
        const t = self.theme();
        widget.text(r.x, r.y, t.small_font - 1, t.text_dim, "PV POSITION");

        var area = r;
        _ = widget.cutTop(&area, 16);

        if (e.pv_count == 0 or !e.pv[0].valid or !e.pv[0].has_end) {
            widget.frame(area, 6, t.panel_alt, t.border_soft);
            return;
        }

        const flipped = if (opts.side) |c| c == .Black else self.app.flipped;
        _ = mini_board.draw(t, area, &e.pv[0].end_position, .{
            .flipped = flipped,
            .last = e.pv[0].end_move,
        });
    }

    fn cardLines(self: *Ui, r: rl.Rectangle, e: *engine_mod.Engine, listed: usize, line_h: f32) void {
        const t = self.theme();
        widget.text(r.x, r.y, t.small_font - 1, t.text_dim, "PRINCIPAL VARIATION");

        var area = r;
        _ = widget.cutTop(&area, 18);

        if (e.pv_count == 0) {
            widget.text(area.x, area.y + 2, t.small_font, t.text_dim, "waiting for output");
            return;
        }

        var shown: usize = 0;
        for (e.pv[0..e.pv_count]) |*pv| {
            if (shown >= listed) break;
            if (!pv.valid) continue;

            const row = widget.cutTop(&area, line_h);
            if (row.height < line_h - 0.5) break;
            shown += 1;

            var x = row.x;
            if (listed > 1) {
                if (pv.score) |raw| {
                    const score = if (e.have_root and e.search_root.to_move == .Black) raw.negate() else raw;
                    var fbuf: [16]u8 = undefined;
                    var zbuf: [20]u8 = undefined;
                    widget.text(x, row.y + 2, t.small_font, t.evalColor(score.toCp()), widget.zSlice(&zbuf, score.format(&fbuf)));
                }
                x += 52;
            }

            var buf: [engine_mod.max_pv_san + 1]u8 = undefined;
            var clip: [engine_mod.max_pv_san + 8]u8 = undefined;
            const text_body = if (pv.san_len > 0) pv.sanSlice() else pv.uciSlice();
            widget.textClipped(
                x,
                row.y + 2,
                @max(row.x + row.width - x, 20),
                t.small_font,
                if (shown == 1) t.text else t.text_dim,
                widget.zSlice(&buf, text_body),
                &clip,
            );

            if (widget.hovered(row)) {
                self.app.game.setPreview(pv.uciSlice(), 12);
                if (widget.clicked(row)) {
                    self.app.game.playLine(pv.uciSlice(), 12);
                    self.app.engines.analysis_hash = 0;
                }
            }
        }
    }

    pub fn evalBar(self: *Ui, height: f32) void {
        const t = self.theme();
        const r = self.take(height, 0);
        if (!self.visible(r)) return;

        var score: ?chess.uci.Score = null;
        for (self.app.engines.slice()) |*e| {
            if (e.owner != .analysis) continue;
            if (e.whitePovScore()) |s| {
                score = s;
                break;
            }
        }

        const cp: f32 = if (score) |s| @floatFromInt(s.toCp()) else 0;
        const frac = std.math.clamp(0.5 + 0.5 * std.math.tanh(cp / 400.0), 0.02, 0.98);

        rl.drawRectangleRec(r, t.piece_black);
        rl.drawRectangleRec(.{ .x = r.x, .y = r.y, .width = r.width * frac, .height = r.height }, t.piece_white);
        rl.drawRectangleRec(.{ .x = r.x + r.width / 2, .y = r.y, .width = 1, .height = r.height }, t.border);
    }

    pub fn clocks(self: *Ui) void {
        const m = &self.app.match;
        if (m.state == .idle) {
            self.dim("no match running");
            return;
        }
        const to_move = self.app.game.sideToMove();
        var wb: [24]u8 = undefined;
        var bb: [24]u8 = undefined;
        self.label("white", match_mod.clockText(&wb, m.remaining(.White, to_move)), .normal);
        self.label("black", match_mod.clockText(&bb, m.remaining(.Black, to_move)), .normal);
    }

    pub fn piece(self: *Ui, kind: chess.Pieces, color: chess.Color, size: f32) void {
        const r = self.take(size, size);
        if (!self.visible(r)) return;
        pieces.draw(kind, color, r.x + size / 2, r.y + size / 2, size * 0.9, self.theme());
    }
};

pub fn fmtCount(buf: []u8, n: u64) []const u8 {
    if (n >= 1_000_000_000) {
        return std.fmt.bufPrint(buf, "{d}.{d}B", .{ n / 1_000_000_000, (n / 100_000_000) % 10 }) catch "?";
    }
    if (n >= 1_000_000) {
        return std.fmt.bufPrint(buf, "{d}.{d}M", .{ n / 1_000_000, (n / 100_000) % 10 }) catch "?";
    }
    if (n >= 1_000) {
        return std.fmt.bufPrint(buf, "{d}.{d}K", .{ n / 1_000, (n / 100) % 10 }) catch "?";
    }
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch "?";
}

pub const Tone = enum {
    normal,
    dim,
    bright,
    good,
    bad,
    warn,
    accent,

    pub fn color(self: Tone, t: Theme) rl.Color {
        return switch (self) {
            .normal => t.text,
            .dim => t.text_dim,
            .bright => t.text_bright,
            .good => t.good,
            .bad => t.bad,
            .warn => t.warn,
            .accent => t.accent,
        };
    }

    pub fn parse(s: []const u8) Tone {
        inline for (@typeInfo(Tone).@"enum".fields) |f| {
            if (std.mem.eql(u8, f.name, s)) return @enumFromInt(f.value);
        }
        return .normal;
    }
};

const max_inputs = 12;

const InputSlot = struct {
    id: [48]u8 = undefined,
    id_len: usize = 0,
    input: widget.TextInput = .{},
    live: bool = false,
};

var input_pool: [max_inputs]InputSlot = @splat(.{});

fn inputFor(id: []const u8, initial: []const u8) *widget.TextInput {
    for (&input_pool) |*slot| {
        if (!slot.live) continue;
        if (std.mem.eql(u8, slot.id[0..slot.id_len], id)) return &slot.input;
    }
    for (&input_pool) |*slot| {
        if (slot.live) continue;
        const n = @min(id.len, slot.id.len);
        @memcpy(slot.id[0..n], id[0..n]);
        slot.id_len = n;
        slot.input = widget.TextInput.init(initial);
        slot.live = true;
        return &slot.input;
    }
    return &input_pool[0].input;
}

pub fn resetInputs() void {
    for (&input_pool) |*slot| slot.live = false;
}
