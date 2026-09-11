const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const engine_mod = @import("../../engine/engine.zig");

pub const EnginesPanel = struct {
    list_scroll: widget.Scroll = .{},
    opt_scroll: widget.Scroll = .{},

    const row_h: f32 = 30;
    const opt_h: f32 = 26;

    pub fn draw(self: *EnginesPanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        var area = widget.inset(bounds, 6);

        self.handleFileDrop(app);

        var add_row = widget.cutTop(&area, 26);
        const add_btn = widget.cutRight(&add_row, 56);
        _ = widget.cutRight(&add_row, 6);

        if (app.engine_path_input.draw(t, add_row, "path to a UCI engine binary")) {
            app.addEngineFromInput();
        }
        if (widget.button(t, add_btn, "add", .primary)) {
            app.addEngineFromInput();
        }

        const hint = widget.cutTop(&area, 18);
        widget.text(hint.x + 2, hint.y + 2, t.small_font, t.text_dim, "or drop an engine binary onto the window");
        _ = widget.cutTop(&area, 4);

        if (app.engines.count == 0) {
            widget.text(area.x + 2, area.y + 6, t.small_font, t.text_dim, "no engines configured");
            return;
        }

        const list_h = @min(area.height * 0.55, @as(f32, @floatFromInt(app.engines.count)) * row_h + 4);
        const list_area = widget.cutTop(&area, list_h);
        self.drawList(app, list_area);

        _ = widget.cutTop(&area, 4);
        widget.separator(t, area.x, area.y, area.width);
        _ = widget.cutTop(&area, 6);

        self.drawOptions(app, area);
    }

    fn handleFileDrop(self: *EnginesPanel, app: *App) void {
        _ = self;
        if (!rl.isFileDropped()) return;

        const dropped = rl.loadDroppedFiles();
        defer rl.unloadDroppedFiles(dropped);

        var i: usize = 0;
        while (i < dropped.count) : (i += 1) {
            const c_path = dropped.paths[i];
            if (c_path == null) continue;
            const path = std.mem.span(@as([*:0]const u8, @ptrCast(c_path)));
            app.addEnginePath(path);
        }
    }

    fn drawList(self: *EnginesPanel, app: *App, area: rl.Rectangle) void {
        const t = app.theme;
        const content_h = @as(f32, @floatFromInt(app.engines.count)) * row_h;
        self.list_scroll.handle(area, content_h);

        rl.beginScissorMode(
            @intFromFloat(area.x),
            @intFromFloat(area.y),
            @intFromFloat(@max(area.width, 0)),
            @intFromFloat(@max(area.height, 0)),
        );
        defer rl.endScissorMode();

        var remove_index: ?usize = null;

        for (app.engines.slice(), 0..) |*e, i| {
            const y = area.y + @as(f32, @floatFromInt(i)) * row_h - self.list_scroll.offset;
            if (y + row_h < area.y or y > area.y + area.height) continue;

            const r = rl.Rectangle{ .x = area.x, .y = y, .width = area.width, .height = row_h };
            const is_sel = app.engines.selected == i;
            if (is_sel) {
                widget.frame(widget.inset(r, 1), 0.2, t.panel_alt, t.accent_dim);
            } else if (widget.hovered(r)) {
                rl.drawRectangleRec(r, t.row_alt);
            }
            if (widget.clicked(r)) app.engines.selected = i;

            var body = widget.inset(r, 4);

            const kill = widget.cutRight(&body, 24);
            _ = widget.cutRight(&body, 4);
            const reload = widget.cutRight(&body, 30);
            _ = widget.cutRight(&body, 4);
            const analyse = widget.cutRight(&body, 62);
            _ = widget.cutRight(&body, 6);

            const in_match = app.match.usesEngine(i);
            const analysing = e.owner == .analysis;

            if (widget.buttonEx(t, analyse, "analyse", if (analysing) .primary else .normal, !in_match)) {
                app.engines.setAnalysisEngine(i, !analysing, &app.log);
                if (!app.engines.analysis_on and !analysing) app.engines.setAnalysis(true, &app.log);
            }
            if (widget.buttonEx(t, reload, "re", .normal, !in_match)) {
                app.engines.restart(i, &app.log);
            }
            if (widget.buttonEx(t, kill, "x", .danger, !in_match)) {
                remove_index = i;
            }

            var nbuf: [72]u8 = undefined;
            var clip: [96]u8 = undefined;
            widget.textClipped(
                body.x + 2,
                body.y + 1,
                body.width - 4,
                t.small_font,
                if (is_sel) t.text_bright else t.text,
                widget.zSlice(&nbuf, e.nameSlice()),
                &clip,
            );

            const col = switch (e.status) {
                .ready => t.good,
                .thinking => t.accent,
                .failed => t.bad,
                else => t.text_dim,
            };
            var sbuf: [64]u8 = undefined;
            const label = if (in_match)
                widget.zBuf(&sbuf, "in match - {s}", .{e.status.label()})
            else
                widget.zBuf(&sbuf, "{s}", .{e.status.label()});
            widget.text(body.x + 2, body.y + 14, t.small_font - 1, col, label);
        }

        self.list_scroll.drawBar(t, area, content_h);

        if (remove_index) |idx| {
            app.engines.removeAt(idx, &app.log);
            app.engines.saveConfig();
            app.setStatus("engine removed", .{});
        }
    }

    fn drawOptions(self: *EnginesPanel, app: *App, area: rl.Rectangle) void {
        const t = app.theme;
        const e = app.engines.current() orelse {
            widget.text(area.x + 2, area.y, t.small_font, t.text_dim, "select an engine to see its options");
            return;
        };

        var head = area;
        const head_row = widget.cutTop(&head, 18);
        var pbuf: [140]u8 = undefined;
        var clip: [160]u8 = undefined;
        widget.textClipped(
            head_row.x + 2,
            head_row.y,
            head_row.width - 4,
            t.small_font,
            t.text_dim,
            widget.zSlice(&pbuf, e.pathSlice()),
            &clip,
        );

        if (e.option_count == 0) {
            widget.text(head.x + 2, head.y + 4, t.small_font, t.text_dim, "no options reported");
            return;
        }

        const content_h = @as(f32, @floatFromInt(e.option_count)) * opt_h;
        self.opt_scroll.handle(head, content_h);

        rl.beginScissorMode(
            @intFromFloat(head.x),
            @intFromFloat(head.y),
            @intFromFloat(@max(head.width, 0)),
            @intFromFloat(@max(head.height, 0)),
        );
        defer rl.endScissorMode();

        for (e.options[0..e.option_count], 0..) |*o, i| {
            const y = head.y + @as(f32, @floatFromInt(i)) * opt_h - self.opt_scroll.offset;
            if (y + opt_h < head.y or y > head.y + head.height) continue;

            const r = rl.Rectangle{ .x = head.x, .y = y, .width = head.width, .height = opt_h };
            var label_rect = widget.inset(r, 3);
            const control = widget.cutRight(&label_rect, @min(140, r.width * 0.5));

            var nbuf: [64]u8 = undefined;
            var nclip: [80]u8 = undefined;
            widget.textClipped(
                label_rect.x,
                label_rect.y + (label_rect.height - t.smallF()) / 2,
                label_rect.width - 6,
                t.small_font,
                t.text,
                widget.zSlice(&nbuf, o.nameSlice()),
                &nclip,
            );

            self.drawOptionControl(app, e, o, control);
        }

        self.opt_scroll.drawBar(t, head, content_h);
    }

    fn drawOptionControl(
        self: *EnginesPanel,
        app: *App,
        e: *engine_mod.Engine,
        o: *engine_mod.Option,
        r: rl.Rectangle,
    ) void {
        _ = self;
        const t = app.theme;

        switch (o.kind) {
            .check => {
                var on = std.ascii.eqlIgnoreCase(o.valueSlice(), "true");
                if (widget.checkBox(t, r, if (on) "true" else "false", &on)) {
                    _ = e.setOptionByName(&app.log, o.nameSlice(), if (on) "true" else "false");
                }
            },
            .spin => {
                var value: i32 = std.fmt.parseInt(i32, o.valueSlice(), 10) catch 0;
                const lo: i32 = if (o.min) |m| @intCast(std.math.clamp(m, -1_000_000, 1_000_000)) else -1_000_000;
                const hi: i32 = if (o.max) |m| @intCast(std.math.clamp(m, -1_000_000, 1_000_000)) else 1_000_000;
                const step: i32 = if (hi - lo > 1000) 16 else 1;
                if (widget.stepper(t, r, &value, lo, hi, step, "")) {
                    var buf: [16]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
                    _ = e.setOptionByName(&app.log, o.nameSlice(), text);
                }
            },
            .button => {
                if (widget.button(t, r, "press", .normal)) {
                    var buf: [128]u8 = undefined;
                    const cmd = chess.uci.setOptionCmd(&buf, o.nameSlice(), null) catch return;
                    e.send(&app.log, cmd);
                }
            },
            else => {
                var vbuf: [72]u8 = undefined;
                var vclip: [88]u8 = undefined;
                widget.textClipped(
                    r.x,
                    r.y + (r.height - t.smallF()) / 2,
                    r.width,
                    t.small_font,
                    t.text_dim,
                    widget.zSlice(&vbuf, o.valueSlice()),
                    &vclip,
                );
            },
        }
    }
};
