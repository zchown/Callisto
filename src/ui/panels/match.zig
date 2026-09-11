const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const match_mod = @import("../../match.zig");

const Player = match_mod.Player;
const TcKind = match_mod.TcKind;

const row_h: f32 = 26;
const gap: f32 = 5;
const label_w: f32 = 74;

fn playerIndex(p: Player) usize {
    return if (p.kind == .human) 0 else p.engine + 1;
}

fn playerFromIndex(idx: usize) Player {
    if (idx == 0) return .{ .kind = .human };
    return .{ .kind = .engine, .engine = idx - 1 };
}

fn playerLabel(app: *App, idx: usize, buf: []u8) [:0]const u8 {
    if (idx == 0) return widget.zSlice(buf, "Human");
    const e = app.engines.get(idx - 1) orelse return widget.zSlice(buf, "missing engine");
    return widget.zSlice(buf, e.nameSlice());
}

fn labelled(app: *App, r: rl.Rectangle, text: [:0]const u8) rl.Rectangle {
    const t = app.theme;
    widget.text(r.x, r.y + (r.height - t.smallF()) / 2, t.small_font, t.text_dim, text);
    return .{ .x = r.x + label_w, .y = r.y, .width = @max(r.width - label_w, 20), .height = r.height };
}

pub fn drawConfig(app: *App, area: rl.Rectangle) f32 {
    const t = app.theme;
    const m = &app.match;
    const locked = m.isRunning();

    var r = area;
    var used: f32 = 0;
    const options = app.engines.count + 1;

    var buf: [72]u8 = undefined;

    {
        const line = widget.cutTop(&r, row_h);
        const field = labelled(app, line, "white");
        var idx = playerIndex(m.white);
        if (!locked and widget.selector(t, field, playerLabel(app, idx, &buf), &idx, options)) {
            m.white = playerFromIndex(idx);
        } else if (locked) {
            widget.textIn(field, 8, t.small_font, t.text_dim, playerLabel(app, idx, &buf));
        }
        _ = widget.cutTop(&r, gap);
        used += row_h + gap;
    }
    {
        const line = widget.cutTop(&r, row_h);
        const field = labelled(app, line, "black");
        var idx = playerIndex(m.black);
        if (!locked and widget.selector(t, field, playerLabel(app, idx, &buf), &idx, options)) {
            m.black = playerFromIndex(idx);
        } else if (locked) {
            widget.textIn(field, 8, t.small_font, t.text_dim, playerLabel(app, idx, &buf));
        }
        _ = widget.cutTop(&r, gap);
        used += row_h + gap;
    }

    {
        const line = widget.cutTop(&r, row_h);
        const field = labelled(app, line, "time");
        var idx: usize = @intFromEnum(m.tc.kind);
        const kinds = @typeInfo(TcKind).@"enum".fields.len;
        if (!locked and widget.selector(t, field, m.tc.kind.label(), &idx, kinds)) {
            m.tc.kind = @enumFromInt(idx);
        } else if (locked) {
            widget.textIn(field, 8, t.small_font, t.text_dim, m.tc.kind.label());
        }
        _ = widget.cutTop(&r, gap);
        used += row_h + gap;
    }

    {
        const line = widget.cutTop(&r, row_h);
        var field = labelled(app, line, "limit");
        switch (m.tc.kind) {
            .increment, .sudden_death => {
                const half = (field.width - 6) / 2;
                const base_r = widget.cutLeft(&field, if (m.tc.kind == .increment) half else field.width);
                var base_s: i32 = @intCast(@divTrunc(m.tc.base_ms, 1000));
                if (widget.stepper(t, base_r, &base_s, 1, 3600, 30, "s")) {
                    m.tc.base_ms = @as(i64, base_s) * 1000;
                }
                if (m.tc.kind == .increment) {
                    _ = widget.cutLeft(&field, 6);
                    var inc_s: i32 = @intCast(@divTrunc(m.tc.inc_ms, 1000));
                    if (widget.stepper(t, field, &inc_s, 0, 60, 1, "s inc")) {
                        m.tc.inc_ms = @as(i64, inc_s) * 1000;
                    }
                }
            },
            .movetime => {
                var ms: i32 = @intCast(m.tc.movetime_ms);
                if (widget.stepper(t, field, &ms, 10, 60_000, 100, "ms")) m.tc.movetime_ms = ms;
            },
            .depth => {
                var d: i32 = @intCast(m.tc.depth);
                if (widget.stepper(t, field, &d, 1, 60, 1, "")) m.tc.depth = @intCast(d);
            },
            .nodes => {
                var kn: i32 = @intCast(@divTrunc(m.tc.nodes, 1000));
                if (widget.stepper(t, field, &kn, 1, 1_000_000, 100, "k nodes")) {
                    m.tc.nodes = @as(u64, @intCast(kn)) * 1000;
                }
            },
        }
        _ = widget.cutTop(&r, gap);
        used += row_h + gap;
    }

    {
        const line = widget.cutTop(&r, row_h);
        var field = labelled(app, line, "games");
        const games_r = widget.cutLeft(&field, @min(120, field.width));
        var games: i32 = @intCast(m.total_games);
        if (widget.stepper(t, games_r, &games, 1, 1000, 1, "")) m.total_games = @intCast(@max(games, 1));

        _ = widget.cutLeft(&field, 10);
        if (field.width > 90) {
            const swap_r = widget.cutLeft(&field, @min(110, field.width));
            _ = widget.checkBox(t, swap_r, "swap colours", &m.swap_colors);
        }
        if (field.width > 80) {
            _ = widget.checkBox(t, field, "save pgn", &m.save_pgn);
        }
        _ = widget.cutTop(&r, gap);
        used += row_h + gap;
    }

    return used;
}

pub const MatchPanel = struct {
    pub fn draw(self: *MatchPanel, app: *App, bounds: rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        const m = &app.match;
        var area = widget.inset(bounds, 8);

        const used = drawConfig(app, area);
        area.y += used;
        area.height -= used;

        widget.separator(t, area.x, area.y, area.width);
        _ = widget.cutTop(&area, 8);

        var controls = widget.cutTop(&area, 28);
        const primary = widget.cutLeft(&controls, 110);
        _ = widget.cutLeft(&controls, 8);
        const secondary = widget.cutLeft(&controls, 90);

        if (m.isRunning()) {
            if (widget.button(t, primary, "abort match", .danger)) {
                m.abort(&app.engines, &app.log);
            }
        } else {
            if (widget.button(t, primary, "start match", .primary)) {
                app.startMatch();
            }
        }
        if (widget.buttonEx(t, secondary, "new board", .normal, !m.isRunning())) {
            app.newGame(chess.start_position);
        }

        _ = widget.cutTop(&area, 10);

        const line_h: f32 = 20;
        var buf: [96]u8 = undefined;

        widget.stat(t, widget.cutTop(&area, line_h), "state", switch (m.state) {
            .idle => "free play",
            .playing => "playing",
            .between => "between games",
            .finished => "finished",
        }, t.text);

        if (m.state != .idle) {
            widget.stat(
                t,
                widget.cutTop(&area, line_h),
                "game",
                widget.zBuf(&buf, "{d} / {d}", .{ m.game_index + 1, m.total_games }),
                t.text,
            );

            var sbuf: [64]u8 = undefined;
            widget.stat(
                t,
                widget.cutTop(&area, line_h),
                "score",
                widget.zBuf(&sbuf, "{d} - {d} - {d}", .{ m.p1_wins, m.p2_wins, m.draws }),
                t.text_bright,
            );

            if (m.tc.kind.usesClock()) {
                const to_move = app.game.sideToMove();
                var cb: [24]u8 = undefined;
                var cz: [24]u8 = undefined;
                widget.stat(
                    t,
                    widget.cutTop(&area, line_h),
                    "white clock",
                    widget.zSlice(&cz, match_mod.clockText(&cb, m.remaining(.White, to_move))),
                    t.text,
                );
                var cb2: [24]u8 = undefined;
                var cz2: [24]u8 = undefined;
                widget.stat(
                    t,
                    widget.cutTop(&area, line_h),
                    "black clock",
                    widget.zSlice(&cz2, match_mod.clockText(&cb2, m.remaining(.Black, to_move))),
                    t.text,
                );
            }

            if (m.messageSlice().len > 0) {
                var mb: [96]u8 = undefined;
                var clip: [120]u8 = undefined;
                const line = widget.cutTop(&area, line_h);
                widget.textClipped(
                    line.x,
                    line.y + 3,
                    line.width,
                    t.small_font,
                    t.warn,
                    widget.zSlice(&mb, m.messageSlice()),
                    &clip,
                );
            }
        }

        if (m.save_pgn and area.height > 20) {
            var pb: [120]u8 = undefined;
            var clip: [140]u8 = undefined;
            widget.textClipped(
                area.x,
                area.y + area.height - 16,
                area.width,
                t.small_font,
                t.text_dim,
                widget.zBuf(&pb, "games are appended to {s}", .{m.pgn_path[0..m.pgn_path_len]}),
                &clip,
            );
        }
    }
};
