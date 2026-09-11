const std = @import("std");
const layout_mod = @import("layout.zig");
const app_mod = @import("../app.zig");

const Layout = layout_mod.Layout;
const View = app_mod.View;

pub const Ids = struct {
    home: usize,
    board: usize,
    moves: usize,
    analysis: usize,
    engines: usize,
    match: usize,
    log: usize,
};

pub const Views = struct {
    home: Layout = .{},
    game: Layout = .{},
    analysis: Layout = .{},

    pub fn build(ids: Ids) !Views {
        var v = Views{};

        v.home.root = try v.home.leaf(ids.home);

        {
            const board = try v.game.leaf(ids.board);
            const top = try v.game.tabs(&.{ ids.moves, ids.match });
            const bottom = try v.game.tabs(&.{ ids.engines, ids.log });
            const right = try v.game.split(.vertical, 0.55, top, bottom);
            v.game.root = try v.game.split(.horizontal, 0.62, board, right);
            v.game.nodes[v.game.root].split.min_first = 280;
            v.game.nodes[v.game.root].split.min_second = 240;
        }

        {
            const board = try v.analysis.leaf(ids.board);
            const top = try v.analysis.tabs(&.{ ids.analysis, ids.engines });
            const bottom = try v.analysis.tabs(&.{ ids.moves, ids.log });
            const right = try v.analysis.split(.vertical, 0.55, top, bottom);
            v.analysis.root = try v.analysis.split(.horizontal, 0.58, board, right);
            v.analysis.nodes[v.analysis.root].split.min_first = 280;
            v.analysis.nodes[v.analysis.root].split.min_second = 280;
        }

        return v;
    }

    pub fn current(self: *Views, view: View) *Layout {
        return switch (view) {
            .home => &self.home,
            .game => &self.game,
            .analysis => &self.analysis,
        };
    }
};
