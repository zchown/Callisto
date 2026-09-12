const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const pieces = @import("pieces.zig");
const theme_mod = @import("theme.zig");
const widget = @import("widget.zig");

const Theme = theme_mod.Theme;

pub const Options = struct {
    flipped: bool = false,
    last: ?chess.Move = null,
    frame: bool = true,
    coords: bool = false,
};

pub fn draw(
    t: Theme,
    area: rl.Rectangle,
    position: *const chess.Position,
    opts: Options,
) rl.Rectangle {
    const empty = rl.Rectangle{ .x = area.x, .y = area.y, .width = 0, .height = 0 };
    if (area.width <= 8 or area.height <= 8) return empty;

    var inner = area;
    if (opts.frame) {
        widget.frame(area, 6, t.panel_alt, t.border_soft);
        inner = widget.inset(area, 4);
    }

    const sq: u6 = @intCast(@divFloor(@as(usize, @intFromFloat(@min(inner.width, inner.height))), 8));
    if (sq < 3) return empty;

    const size: f32 = @as(f32, @floatFromInt(sq)) * 8;
    const board = rl.Rectangle{
        .x = @round(inner.x + (inner.width - size) / 2),
        .y = @round(inner.y + (inner.height - size) / 2),
        .width = size,
        .height = size,
    };

    for (0..64) |i| {
        const square: chess.Square = @intCast(i);
        const file: f32 = @floatFromInt(chess.utils.fileOf(square));
        const rank: f32 = @floatFromInt(chess.utils.rankOf(square));

        const col = if (opts.flipped) 7 - file else file;
        const row = if (opts.flipped) rank else 7 - rank;

        const sq_f: f32 = @floatFromInt(sq);
        const r = rl.Rectangle{
            .x = board.x + col * sq_f,
            .y = board.y + row * sq_f,
            .width = sq_f,
            .height = sq_f,
        };


        const j: u6 = @as(u6, @intCast(i));
        const light = (@as(usize, @intCast(chess.utils.fileOf(j))) + @as(usize, @intCast(chess.utils.rankOf(j)))) % 2 == 1;
        rl.drawRectangleRec(r, if (light) t.sq_light else t.sq_dark);

        if (opts.last) |m| {
            if (m.from == square or m.to == square) {
                rl.drawRectangleRec(r, rl.fade(t.hl_last, 0.42));
            }
        }

        const piece = position.getFromSquare(square);
        if (piece.isNone()) continue;
        pieces.draw(
            piece.piece,
            piece.color,
            r.x + sq_f / 2,
            r.y + sq_f / 2,
            sq_f * 0.88,
            t,
        );
    }

    return board;
}
