const std = @import("std");
const rl = @import("raylib");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const log_mod = @import("../../log.zig");

pub const LogPanel = struct {
    scroll: widget.Scroll = .{},
    follow: bool = true,
    last_revision: u64 = 0,

    const line_h: f32 = 17;

    pub fn draw(self: *LogPanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        var area = widget.inset(bounds, 6);

        var bar = widget.cutTop(&area, 24);
        const clear_btn = widget.cutRight(&bar, 52);
        _ = widget.cutRight(&bar, 5);
        const pause_btn = widget.cutRight(&bar, 58);
        _ = widget.cutRight(&bar, 5);
        const follow_btn = widget.cutRight(&bar, 62);

        if (widget.button(t, clear_btn, "clear", .normal)) app.log.clear();
        if (widget.toggle(t, pause_btn, if (app.log.paused) "paused" else "pause", app.log.paused)) {
            app.log.paused = !app.log.paused;
        }
        if (widget.toggle(t, follow_btn, "follow", self.follow)) self.follow = !self.follow;

        var cbuf: [32]u8 = undefined;
        widget.text(
            bar.x + 2,
            bar.y + (bar.height - t.smallF()) / 2,
            t.small_font,
            t.text_dim,
            widget.zBuf(&cbuf, "{d} lines", .{app.log.count}),
        );

        _ = widget.cutTop(&area, 4);
        if (area.height < 20) return;

        const content_h = @as(f32, @floatFromInt(app.log.count)) * line_h;
        self.scroll.handle(area, content_h);

        if (self.follow and self.last_revision != app.log.revision) {
            self.last_revision = app.log.revision;
            self.scroll.toBottom(area, content_h);
        }

        rl.beginScissorMode(
            @intFromFloat(area.x),
            @intFromFloat(area.y),
            @intFromFloat(@max(area.width, 0)),
            @intFromFloat(@max(area.height, 0)),
        );
        defer rl.endScissorMode();

        var i: usize = 0;
        while (i < app.log.count) : (i += 1) {
            const y = area.y + @as(f32, @floatFromInt(i)) * line_h - self.scroll.offset;
            if (y + line_h < area.y or y > area.y + area.height) continue;

            const entry = app.log.at(i) orelse continue;
            const marker: [:0]const u8 = switch (entry.dir) {
                .in => "<",
                .out => ">",
                .note => "-",
                .err => "!",
            };
            const col = switch (entry.dir) {
                .in => t.text,
                .out => t.accent,
                .note => t.text_dim,
                .err => t.bad,
            };

            widget.text(area.x + 2, y, t.small_font, col, marker);

            var tag_buf: [24]u8 = undefined;
            var tag_clip: [32]u8 = undefined;
            widget.textClipped(
                area.x + 14,
                y,
                72,
                t.small_font,
                t.text_dim,
                widget.zSlice(&tag_buf, entry.tagSlice()),
                &tag_clip,
            );

            var text_buf: [log_mod.max_text + 1]u8 = undefined;
            var clip_buf: [log_mod.max_text + 8]u8 = undefined;
            widget.textClipped(
                area.x + 92,
                y,
                @max(area.width - 96, 20),
                t.small_font,
                col,
                widget.zSlice(&text_buf, entry.textSlice()),
                &clip_buf,
            );
        }

        self.scroll.drawBar(t, area, content_h);
    }
};
