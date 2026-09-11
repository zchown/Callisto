const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const engine_mod = @import("../../engine/engine.zig");

pub const AnalysisPanel = struct {
    scroll: widget.Scroll = .{},
    hovering_line: bool = false,

    const line_h: f32 = 20;

    pub fn draw(self: *AnalysisPanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        var area = widget.inset(bounds, 6);

        self.drawControls(app, widget.cutTop(&area, 26));
        _ = widget.cutTop(&area, 6);

        const was_hovering = self.hovering_line;
        self.hovering_line = false;

        if (app.engines.count == 0) {
            widget.text(area.x + 2, area.y + 4, t.small_font, t.text_dim, "no engines yet - add one in the Engines tab");
            return;
        }

        var any = false;
        var y = area.y - self.scroll.offset;
        var content_h: f32 = 0;

        rl.beginScissorMode(
            @intFromFloat(area.x),
            @intFromFloat(area.y),
            @intFromFloat(@max(area.width, 0)),
            @intFromFloat(@max(area.height, 0)),
        );

        for (app.engines.slice()) |*e| {
            if (e.owner != .analysis) continue;
            any = true;
            const used = self.drawEngineBlock(app, e, .{
                .x = area.x,
                .y = y,
                .width = area.width,
                .height = area.height,
            });
            y += used;
            content_h += used;
        }

        rl.endScissorMode();

        if (!any) {
            widget.text(area.x + 2, area.y + 4, t.small_font, t.text_dim, "no engine selected for analysis");
        }

        self.scroll.handle(area, content_h);
        self.scroll.drawBar(t, area, content_h);

        if (was_hovering and !self.hovering_line) app.game.clearPreview();
    }

    fn drawControls(self: *AnalysisPanel, app: *App, bar: rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        var r = bar;

        const go = widget.cutLeft(&r, 84);
        _ = widget.cutLeft(&r, 6);
        const mpv = widget.cutLeft(&r, 104);

        const on = app.engines.analysis_on;
        if (widget.toggle(t, go, if (on) "stop" else "analyse", on)) {
            app.toggleAnalysis();
        }

        var multipv = app.engines.multipv;
        if (widget.stepper(t, mpv, &multipv, 1, engine_mod.max_multipv, 1, " lines")) {
            app.engines.setMultiPv(multipv, &app.log);
        }

        _ = widget.cutLeft(&r, 6);
        if (r.width > 60) {
            var buf: [48]u8 = undefined;
            widget.textRight(
                r.x + r.width,
                r.y + (r.height - t.smallF()) / 2,
                t.small_font,
                t.text_dim,
                widget.zBuf(&buf, "{d} engine(s)", .{app.engines.analysisEngineCount()}),
            );
        }
    }

    fn drawEngineBlock(self: *AnalysisPanel, app: *App, e: *engine_mod.Engine, area: rl.Rectangle) f32 {
        const t = app.theme;
        var used: f32 = 0;

        const header = rl.Rectangle{ .x = area.x, .y = area.y, .width = area.width, .height = 20 };
        var nbuf: [72]u8 = undefined;
        widget.text(
            header.x,
            header.y + (header.height - t.smallF()) / 2,
            t.small_font,
            t.text_bright,
            widget.zSlice(&nbuf, e.nameSlice()),
        );

        var sbuf: [96]u8 = undefined;
        widget.textRight(
            header.x + header.width,
            header.y + (header.height - t.smallF()) / 2,
            t.small_font,
            t.text_dim,
            widget.zBuf(&sbuf, "d{d} - {d} kn - {d} knps", .{
                e.depth,
                e.nodes / 1000,
                e.nps / 1000,
            }),
        );
        used += header.height;

        widget.separator(t, area.x, area.y + used, area.width);
        used += 3;

        if (e.pv_count == 0) {
            const msg: [:0]const u8 = if (e.status == .failed) "engine stopped" else "waiting for output";
            widget.text(area.x + 4, area.y + used, t.small_font, t.text_dim, msg);
            return used + line_h + 6;
        }

        for (e.pv[0..e.pv_count], 0..) |*pv, i| {
            if (!pv.valid) continue;
            const r = rl.Rectangle{
                .x = area.x,
                .y = area.y + used,
                .width = area.width,
                .height = line_h,
            };
            self.drawPvLine(app, e, pv, r, i);
            used += line_h;
        }

        return used + 8;
    }

    fn drawPvLine(
        self: *AnalysisPanel,
        app: *App,
        e: *engine_mod.Engine,
        pv: *engine_mod.PvLine,
        r: rl.Rectangle,
        index: usize,
    ) void {
        const t = app.theme;
        const over = widget.hovered(r);
        if (over) rl.drawRectangleRec(r, t.panel_alt);

        const y = r.y + (r.height - t.smallF()) / 2;

        var score_buf: [16]u8 = undefined;
        var zbuf: [16]u8 = undefined;
        var score_text: [:0]const u8 = "";
        var score_col = t.text_dim;

        if (pv.score) |raw| {
            const s = if (e.have_root and e.search_root.to_move == .Black) raw.negate() else raw;
            score_text = widget.zSlice(&zbuf, s.format(&score_buf));
            score_col = t.evalColor(s.toCp());
        }

        const score_w: f32 = 52;
        widget.text(r.x + 4, y, t.small_font, score_col, score_text);

        var depth_buf: [12]u8 = undefined;
        widget.text(
            r.x + 4 + score_w,
            y,
            t.small_font,
            t.text_dim,
            widget.zBuf(&depth_buf, "{d}", .{pv.depth}),
        );

        const text_x = r.x + 4 + score_w + 26;
        const max_w = r.x + r.width - text_x - 4;

        var line_buf: [engine_mod.max_pv_san + 1]u8 = undefined;
        var clip_buf: [engine_mod.max_pv_san + 8]u8 = undefined;
        const text = if (pv.san_len > 0)
            widget.zSlice(&line_buf, pv.sanSlice())
        else
            widget.zSlice(&line_buf, pv.uciSlice());

        widget.textClipped(
            text_x,
            y,
            max_w,
            t.small_font,
            if (index == 0) t.text else t.text_dim,
            text,
            &clip_buf,
        );

        if (!over) return;
        self.hovering_line = true;

        app.game.setPreview(pv.uciSlice(), 12);
        if (widget.clicked(r)) {
            app.game.playLine(pv.uciSlice(), 12);
            app.engines.analysis_hash = 0;
        }
    }
};
