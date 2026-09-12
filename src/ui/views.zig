const std = @import("std");
const layout_mod = @import("layout.zig");
const icons = @import("icons.zig");

const Layout = layout_mod.Layout;

pub const max_views = 10;
pub const max_id = 24;
pub const max_label = 28;

pub const View = struct {
    id: [max_id]u8 = undefined,
    id_len: usize = 0,
    label: [max_label]u8 = undefined,
    label_len: usize = 0,
    icon: icons.Icon = .none,
    layout: Layout = .{},
    ready: bool = false,
    in_sidebar: bool = true,

    pub fn idSlice(self: *const View) []const u8 {
        return self.id[0..self.id_len];
    }

    pub fn labelSlice(self: *const View) []const u8 {
        return self.label[0..self.label_len];
    }
};

pub const Ids = struct {
    home: usize,
    board: usize,
    moves: usize,
    analysis: usize,
    engines: usize,
    match: usize,
    log: usize,
};

pub const ViewSet = struct {
    items: [max_views]View = @splat(.{}),
    count: usize = 0,

    pub fn find(self: *ViewSet, id: []const u8) ?*View {
        for (self.items[0..self.count]) |*v| {
            if (std.mem.eql(u8, v.idSlice(), id)) return v;
        }
        return null;
    }

    pub fn indexOf(self: *ViewSet, id: []const u8) ?usize {
        for (self.items[0..self.count], 0..) |*v, i| {
            if (std.mem.eql(u8, v.idSlice(), id)) return i;
        }
        return null;
    }

    pub fn at(self: *ViewSet, index: usize) ?*View {
        if (index >= self.count) return null;
        return &self.items[index];
    }

    pub fn ensure(self: *ViewSet, id: []const u8) ?*View {
        if (self.find(id)) |v| return v;
        if (self.count >= max_views) return null;

        const v = &self.items[self.count];
        v.* = .{};

        const n = @min(id.len, max_id);
        @memcpy(v.id[0..n], id[0..n]);
        v.id_len = n;
        setLabel(v, id);

        self.count += 1;
        return v;
    }

    pub fn setLabel(v: *View, label: []const u8) void {
        const n = @min(label.len, max_label);
        @memcpy(v.label[0..n], label[0..n]);
        v.label_len = n;
    }

    pub fn resolve(self: *ViewSet, id: []const u8) ?*View {
        if (self.find(id)) |v| {
            if (v.ready) return v;
        }
        for (self.items[0..self.count]) |*v| {
            if (v.ready) return v;
        }
        return null;
    }

    pub fn buildDefaults(self: *ViewSet, ids: Ids) !void {
        {
            const v = self.ensure("home") orelse return;
            ViewSet.setLabel(v, "Home");
            v.icon = .home;
            v.layout = .{};
            v.layout.root = try v.layout.leaf(ids.home);
            v.ready = true;
        }
        {
            const v = self.ensure("game") orelse return;
            ViewSet.setLabel(v, "Board");
            v.icon = .board;
            v.layout = .{};
            const board = try v.layout.leaf(ids.board);
            const top = try v.layout.tabs(&.{ ids.moves, ids.match });
            const bottom = try v.layout.tabs(&.{ ids.engines, ids.log });
            const right = try v.layout.split(.vertical, 0.55, top, bottom);
            v.layout.root = try v.layout.split(.horizontal, 0.62, board, right);
            v.layout.nodes[v.layout.root].split.min_first = 300;
            v.layout.nodes[v.layout.root].split.min_second = 260;
            v.ready = true;
        }
        {
            const v = self.ensure("analysis") orelse return;
            ViewSet.setLabel(v, "Analysis");
            v.icon = .analysis;
            v.layout = .{};
            const board = try v.layout.leaf(ids.board);
            const top = try v.layout.tabs(&.{ ids.analysis, ids.engines });
            const bottom = try v.layout.tabs(&.{ ids.moves, ids.log });
            const right = try v.layout.split(.vertical, 0.55, top, bottom);
            v.layout.root = try v.layout.split(.horizontal, 0.58, board, right);
            v.layout.nodes[v.layout.root].split.min_first = 300;
            v.layout.nodes[v.layout.root].split.min_second = 300;
            v.ready = true;
        }
    }
};
