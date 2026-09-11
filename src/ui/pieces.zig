const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");
const widget = @import("widget.zig");
const theme_mod = @import("theme.zig");

const Theme = theme_mod.Theme;
const Pieces = chess.Pieces;
const Color = chess.Color;

const outline_scale: f32 = 1.06;

const Ctx = struct {
    cx: f32,
    cy: f32,
    s: f32,
    color: rl.Color,

    fn p(self: Ctx, x: f32, y: f32) rl.Vector2 {
        return .{ .x = self.cx + x * self.s, .y = self.cy + y * self.s };
    }

    fn quad(self: Ctx, ax: f32, ay: f32, bx: f32, by: f32, cx2: f32, cy2: f32, dx: f32, dy: f32) void {
        widget.quad(self.p(ax, ay), self.p(bx, by), self.p(cx2, cy2), self.p(dx, dy), self.color);
    }

    fn tri(self: Ctx, ax: f32, ay: f32, bx: f32, by: f32, cx2: f32, cy2: f32) void {
        widget.tri(self.p(ax, ay), self.p(bx, by), self.p(cx2, cy2), self.color);
    }

    fn rect(self: Ctx, x0: f32, y0: f32, x1: f32, y1: f32) void {
        self.quad(x0, y0, x1, y0, x1, y1, x0, y1);
    }

    fn disc(self: Ctx, x: f32, y: f32, r: f32) void {
        rl.drawCircleV(self.p(x, y), r * self.s, self.color);
    }
};

pub fn draw(kind: Pieces, color: Color, cx: f32, cy: f32, size: f32, t: Theme) void {
    drawTinted(kind, cx, cy, size, fillColor(color, t), edgeColor(color, t));
}

pub fn drawTinted(kind: Pieces, cx: f32, cy: f32, size: f32, fill: rl.Color, edge: rl.Color) void {
    if (kind == .None) return;
    silhouette(kind, .{ .cx = cx, .cy = cy, .s = size * outline_scale, .color = edge });
    silhouette(kind, .{ .cx = cx, .cy = cy, .s = size, .color = fill });
    details(kind, .{ .cx = cx, .cy = cy, .s = size, .color = edge });
}

pub fn drawGhost(kind: Pieces, color: Color, cx: f32, cy: f32, size: f32, t: Theme) void {
    drawTinted(
        kind,
        cx,
        cy,
        size,
        rl.fade(fillColor(color, t), 0.32),
        rl.fade(edgeColor(color, t), 0.32),
    );
}

pub fn fillColor(color: Color, t: Theme) rl.Color {
    return if (color == .White) t.piece_white else t.piece_black;
}

pub fn edgeColor(color: Color, t: Theme) rl.Color {
    return if (color == .White) t.piece_white_edge else t.piece_black_edge;
}

fn base(c: Ctx, half: f32) void {
    c.quad(-half, 0.36, half, 0.36, half * 0.72, 0.25, -half * 0.72, 0.25);
    c.rect(-half, 0.30, half, 0.36);
}

fn silhouette(kind: Pieces, c: Ctx) void {
    switch (kind) {
        .Pawn => {
            base(c, 0.24);
            c.quad(-0.11, 0.25, 0.11, 0.25, 0.075, 0.02, -0.075, 0.02);
            c.rect(-0.155, 0.00, 0.155, 0.07);
            c.disc(0.0, -0.14, 0.145);
        },
        .Rook => {
            base(c, 0.30);
            c.quad(-0.19, 0.25, 0.19, 0.25, 0.155, -0.10, -0.155, -0.10);
            c.rect(-0.26, -0.22, 0.26, -0.09);
            // battlements
            c.rect(-0.26, -0.34, -0.13, -0.21);
            c.rect(-0.065, -0.34, 0.065, -0.21);
            c.rect(0.13, -0.34, 0.26, -0.21);
        },
        .Knight => {
            base(c, 0.28);
            // neck / chest
            c.quad(-0.16, 0.25, 0.20, 0.25, 0.16, -0.04, -0.09, 0.05);
            // head
            c.quad(-0.09, 0.05, 0.16, -0.04, 0.09, -0.28, -0.16, -0.15);
            // muzzle
            c.tri(-0.16, -0.15, -0.30, 0.01, -0.10, 0.06);
            c.tri(-0.30, 0.01, -0.22, 0.09, -0.10, 0.06);
            // ear
            c.tri(0.09, -0.28, 0.05, -0.40, -0.02, -0.24);
            c.tri(0.09, -0.28, 0.16, -0.22, 0.03, -0.20);
        },
        .Bishop => {
            base(c, 0.26);
            c.quad(-0.15, 0.25, 0.15, 0.25, 0.11, 0.10, -0.11, 0.10);
            c.rect(-0.18, 0.09, 0.18, 0.16);
            c.disc(0.0, -0.08, 0.155);
            c.tri(0.0, -0.36, -0.10, -0.12, 0.10, -0.12);
            c.disc(0.0, -0.36, 0.05);
        },
        .Queen => {
            base(c, 0.30);
            c.quad(-0.19, 0.25, 0.19, 0.25, 0.145, -0.02, -0.145, -0.02);
            c.rect(-0.24, -0.09, 0.24, -0.01);
            c.quad(-0.25, -0.09, 0.25, -0.09, 0.19, -0.24, -0.19, -0.24);
            const tips = [_]f32{ -0.27, -0.135, 0.0, 0.135, 0.27 };
            for (tips) |tx| {
                c.tri(tx, -0.40, tx - 0.085, -0.13, tx + 0.085, -0.13);
                c.disc(tx, -0.40, 0.05);
            }
        },
        .King => {
            base(c, 0.30);
            c.quad(-0.19, 0.25, 0.19, 0.25, 0.145, -0.02, -0.145, -0.02);
            c.rect(-0.24, -0.09, 0.24, -0.01);
            c.quad(-0.22, -0.09, 0.22, -0.09, 0.16, -0.26, -0.16, -0.26);
            c.tri(-0.22, -0.09, -0.16, -0.26, -0.26, -0.20);
            c.tri(0.22, -0.09, 0.16, -0.26, 0.26, -0.20);
            // cross
            c.rect(-0.048, -0.46, 0.048, -0.24);
            c.rect(-0.145, -0.40, 0.145, -0.32);
        },
        .None => {},
    }
}

fn details(kind: Pieces, c: Ctx) void {
    switch (kind) {
        .Knight => {
            // eye
            rl.drawCircleV(c.p(-0.015, -0.13), 0.032 * c.s, c.color);
            // mane
            rl.drawLineEx(c.p(0.13, -0.20), c.p(0.19, 0.05), 0.035 * c.s, c.color);
        },
        .Bishop => {
            rl.drawLineEx(c.p(0.04, -0.19), c.p(-0.05, -0.02), 0.035 * c.s, c.color);
        },
        .Rook => {
            rl.drawLineEx(c.p(-0.20, -0.09), c.p(0.20, -0.09), 0.028 * c.s, c.color);
        },
        else => {},
    }
}

pub fn letter(kind: Pieces) [:0]const u8 {
    return switch (kind) {
        .Pawn => "P",
        .Knight => "N",
        .Bishop => "B",
        .Rook => "R",
        .Queen => "Q",
        .King => "K",
        .None => "",
    };
}
