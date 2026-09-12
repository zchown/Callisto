const std = @import("std");
const rl = @import("raylib");
const widget = @import("widget.zig");

pub const Icon = enum {
    home,
    board,
    analysis,
    engine,
    moves,
    log,
    settings,
    plus,
    close,
    chevron_left,
    chevron_right,
    none,

    pub fn parse(s: []const u8) Icon {
        inline for (@typeInfo(Icon).@"enum".fields) |f| {
            if (std.mem.eql(u8, f.name, s)) return @enumFromInt(f.value);
        }
        return .none;
    }
};

pub fn draw(icon: Icon, r: rl.Rectangle, color: rl.Color) void {
    const s = @min(r.width, r.height);
    if (s < 6) return;

    const cx = r.x + r.width / 2;
    const cy = r.y + r.height / 2;
    const h = s / 2;
    const w = @max(s * 0.09, 1.4);

    switch (icon) {
        .home => {
            // roof
            line(cx - h * 0.85, cy - h * 0.05, cx, cy - h * 0.8, w, color);
            line(cx, cy - h * 0.8, cx + h * 0.85, cy - h * 0.05, w, color);
            // walls
            line(cx - h * 0.6, cy, cx - h * 0.6, cy + h * 0.75, w, color);
            line(cx + h * 0.6, cy, cx + h * 0.6, cy + h * 0.75, w, color);
            line(cx - h * 0.6, cy + h * 0.75, cx + h * 0.6, cy + h * 0.75, w, color);
        },
        .board => {
            const cell = s * 0.32;
            const ox = cx - cell;
            const oy = cy - cell;
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                const col: f32 = @floatFromInt(i % 2);
                const row: f32 = @floatFromInt(i / 2);
                if ((i % 2) == (i / 2) % 2) continue;
                rl.drawRectangleRec(.{
                    .x = ox + col * cell,
                    .y = oy + row * cell,
                    .width = cell,
                    .height = cell,
                }, color);
            }
            rl.drawRectangleLinesEx(.{
                .x = ox,
                .y = oy,
                .width = cell * 2,
                .height = cell * 2,
            }, w, color);
        },
        .analysis => {
            // rising bars
            const bw = s * 0.18;
            const base = cy + h * 0.7;
            bar(cx - bw * 1.6, base, bw, s * 0.3, color);
            bar(cx - bw * 0.3, base, bw, s * 0.6, color);
            bar(cx + bw * 1.0, base, bw, s * 0.95, color);
        },
        .engine => {
            const box = s * 0.5;
            rl.drawRectangleLinesEx(.{
                .x = cx - box / 2,
                .y = cy - box / 2,
                .width = box,
                .height = box,
            }, w, color);
            // pins
            var i: f32 = -1;
            while (i <= 1) : (i += 1) {
                line(cx + i * box * 0.3, cy - box / 2, cx + i * box * 0.3, cy - box * 0.85, w, color);
                line(cx + i * box * 0.3, cy + box / 2, cx + i * box * 0.3, cy + box * 0.85, w, color);
                line(cx - box / 2, cy + i * box * 0.3, cx - box * 0.85, cy + i * box * 0.3, w, color);
                line(cx + box / 2, cy + i * box * 0.3, cx + box * 0.85, cy + i * box * 0.3, w, color);
            }
        },
        .moves => {
            var i: f32 = -1;
            while (i <= 1) : (i += 1) {
                const y = cy + i * h * 0.55;
                rl.drawCircleV(.{ .x = cx - h * 0.7, .y = y }, w * 0.9, color);
                line(cx - h * 0.35, y, cx + h * 0.8, y, w, color);
            }
        },
        .log => {
            rl.drawRectangleLinesEx(.{
                .x = cx - h * 0.85,
                .y = cy - h * 0.7,
                .width = h * 1.7,
                .height = h * 1.4,
            }, w, color);
            line(cx - h * 0.5, cy - h * 0.1, cx - h * 0.2, cy + h * 0.15, w, color);
            line(cx - h * 0.2, cy + h * 0.15, cx - h * 0.5, cy + h * 0.4, w, color);
            line(cx + h * 0.0, cy + h * 0.4, cx + h * 0.5, cy + h * 0.4, w, color);
        },
        .settings => {
            rl.drawCircleLinesV(.{ .x = cx, .y = cy }, h * 0.38, color);
            var i: usize = 0;
            while (i < 6) : (i += 1) {
                const a = @as(f32, @floatFromInt(i)) * std.math.pi / 3.0;
                const c = @cos(a);
                const sn = @sin(a);
                line(cx + c * h * 0.55, cy + sn * h * 0.55, cx + c * h * 0.92, cy + sn * h * 0.92, w, color);
            }
        },
        .plus => {
            line(cx - h * 0.55, cy, cx + h * 0.55, cy, w, color);
            line(cx, cy - h * 0.55, cx, cy + h * 0.55, w, color);
        },
        .close => {
            line(cx - h * 0.45, cy - h * 0.45, cx + h * 0.45, cy + h * 0.45, w, color);
            line(cx + h * 0.45, cy - h * 0.45, cx - h * 0.45, cy + h * 0.45, w, color);
        },
        .chevron_left => {
            line(cx + h * 0.25, cy - h * 0.5, cx - h * 0.25, cy, w, color);
            line(cx - h * 0.25, cy, cx + h * 0.25, cy + h * 0.5, w, color);
        },
        .chevron_right => {
            line(cx - h * 0.25, cy - h * 0.5, cx + h * 0.25, cy, w, color);
            line(cx + h * 0.25, cy, cx - h * 0.25, cy + h * 0.5, w, color);
        },
        .none => {},
    }
}

fn line(x0: f32, y0: f32, x1: f32, y1: f32, w: f32, color: rl.Color) void {
    rl.drawLineEx(.{ .x = x0, .y = y0 }, .{ .x = x1, .y = y1 }, w, color);
}

fn bar(x: f32, base: f32, w: f32, height: f32, color: rl.Color) void {
    rl.drawRectangleRec(.{ .x = x, .y = base - height, .width = w, .height = height }, color);
}
