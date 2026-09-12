const std = @import("std");
const rl = @import("raylib");

const App = @import("../app.zig").App;
const panel_mod = @import("panel.zig");
const widget = @import("widget.zig");

const Registry = panel_mod.Registry;

const max_nodes = 32;
const max_tabs = 6;

pub const Dir = enum { horizontal, vertical };

pub const NodeId = u16;

pub const Leaf = struct {
    panels: [max_tabs]usize = @splat(0),
    count: usize = 0,
    active: i32 = 0,
};

pub const Split = struct {
    dir: Dir,
    ratio: f32,
    first: NodeId,
    second: NodeId,
    min_first: f32 = 160,
    min_second: f32 = 160,
};

pub const Node = union(enum) {
    leaf: Leaf,
    split: Split,
};

pub const divider_thickness: f32 = 5;
const grab_slop: f32 = 3;

pub const Layout = struct {
    nodes: [max_nodes]Node = undefined,
    count: usize = 0,
    root: NodeId = 0,

    dragging: ?NodeId = null,
    hovered_divider: ?NodeId = null,
    tab_height: f32 = 26,
    header_height: f32 = 22,

    pub fn leaf(self: *Layout, panel_index: usize) !NodeId {
        return self.tabs(&.{panel_index});
    }

    pub fn tabs(self: *Layout, panel_indices: []const usize) !NodeId {
        if (self.count >= max_nodes) return error.LayoutFull;
        var l = Leaf{};
        for (panel_indices) |p| {
            if (l.count >= max_tabs) break;
            l.panels[l.count] = p;
            l.count += 1;
        }
        const id: NodeId = @intCast(self.count);
        self.nodes[self.count] = .{ .leaf = l };
        self.count += 1;
        return id;
    }

    pub fn split(self: *Layout, dir: Dir, ratio: f32, first: NodeId, second: NodeId) !NodeId {
        if (self.count >= max_nodes) return error.LayoutFull;
        const id: NodeId = @intCast(self.count);
        self.nodes[self.count] = .{ .split = .{
            .dir = dir,
            .ratio = ratio,
            .first = first,
            .second = second,
        } };
        self.count += 1;
        return id;
    }

    pub fn containsPanel(self: *const Layout, panel_index: usize) bool {
        for (self.nodes[0..self.count]) |node| {
            switch (node) {
                .leaf => |l| {
                    for (l.panels[0..l.count]) |p| {
                        if (p == panel_index) return true;
                    }
                },
                .split => {},
            }
        }
        return false;
    }

    pub fn draw(self: *Layout, app: *App, reg: *Registry, bounds: rl.Rectangle) void {
        if (self.count == 0) return;

        if (self.dragging != null and !rl.isMouseButtonDown(.left)) self.dragging = null;
        self.hovered_divider = null;

        self.drawNode(app, reg, self.root, bounds);

        if (self.hovered_divider) |id| {
            const dir = self.nodes[id].split.dir;
            rl.setMouseCursor(if (dir == .horizontal) .resize_ew else .resize_ns);
        } else if (self.dragging) |id| {
            const dir = self.nodes[id].split.dir;
            rl.setMouseCursor(if (dir == .horizontal) .resize_ew else .resize_ns);
        }
    }

    fn drawNode(self: *Layout, app: *App, reg: *Registry, id: NodeId, bounds: rl.Rectangle) void {
        if (id >= self.count) return;
        if (bounds.width <= 1 or bounds.height <= 1) return;

        switch (self.nodes[id]) {
            .leaf => |*l| self.drawLeaf(app, reg, l, bounds),
            .split => |*s| {
                const t = app.theme;
                const horizontal = s.dir == .horizontal;
                const total = if (horizontal) bounds.width else bounds.height;
                if (total <= divider_thickness) return;

                const usable = total - divider_thickness;
                var first_size = usable * s.ratio;
                first_size = std.math.clamp(
                    first_size,
                    @min(s.min_first, usable),
                    @max(usable - s.min_second, 0),
                );
                const second_size = usable - first_size;

                var rect_a = bounds;
                var rect_b = bounds;
                var divider = bounds;

                if (horizontal) {
                    rect_a.width = first_size;
                    divider.x = bounds.x + first_size;
                    divider.width = divider_thickness;
                    rect_b.x = divider.x + divider_thickness;
                    rect_b.width = second_size;
                } else {
                    rect_a.height = first_size;
                    divider.y = bounds.y + first_size;
                    divider.height = divider_thickness;
                    rect_b.y = divider.y + divider_thickness;
                    rect_b.height = second_size;
                }

                self.drawNode(app, reg, s.first, rect_a);
                self.drawNode(app, reg, s.second, rect_b);

                var hit = divider;
                if (horizontal) {
                    hit.x -= grab_slop;
                    hit.width += grab_slop * 2;
                } else {
                    hit.y -= grab_slop;
                    hit.height += grab_slop * 2;
                }

                const mouse = rl.getMousePosition();
                const hovering = rl.checkCollisionPointRec(mouse, hit);
                if (hovering and self.dragging == null) self.hovered_divider = id;
                if (hovering and rl.isMouseButtonPressed(.left)) self.dragging = id;

                if (self.dragging == id) {
                    const local = if (horizontal) mouse.x - bounds.x else mouse.y - bounds.y;
                    s.ratio = std.math.clamp(local / total, 0.08, 0.92);
                }

                const active = self.dragging == id or self.hovered_divider == id;
                rl.drawRectangleRec(divider, if (active) t.divider else t.bg);
            },
        }
    }

    fn drawLeaf(self: *Layout, app: *App, reg: *Registry, l: *Leaf, bounds: rl.Rectangle) void {
        const t = app.theme;
        if (l.count == 0) return;

        if (l.active < 0) l.active = 0;
        if (l.active >= @as(i32, @intCast(l.count))) l.active = @intCast(l.count - 1);

        var content = bounds;

        if (l.count > 1) {
            const bar = widget.cutTop(&content, self.tab_height);
            rl.drawRectangleRec(bar, t.bg);
            self.drawTabs(app, reg, l, bar);
        }

        const p = reg.get(l.panels[@intCast(l.active)]) orelse return;

        if (p.draws_own_background) {
            p.draw(app, content);
            return;
        }

        rl.drawRectangleRec(content, t.panel);
        rl.drawRectangleLinesEx(content, 1, t.border);

        if (l.count == 1) {
            const header = widget.cutTop(&content, self.header_height);
            rl.drawRectangleRec(header, t.panel_alt);
            widget.text(header.x + 8, header.y + 4, t.small_font, t.text_dim, p.title);
            rl.drawRectangleRec(
                .{ .x = header.x, .y = header.y + header.height - 1, .width = header.width, .height = 1 },
                t.border,
            );
        }

        const inner = rl.Rectangle{
            .x = content.x + 1,
            .y = content.y + 1,
            .width = content.width - 2,
            .height = content.height - 2,
        };
        if (inner.width <= 0 or inner.height <= 0) return;

        rl.beginScissorMode(
            @intFromFloat(inner.x),
            @intFromFloat(inner.y),
            @intFromFloat(inner.width),
            @intFromFloat(inner.height),
        );
        p.draw(app, inner);
        rl.endScissorMode();
    }

    fn drawTabs(self: *Layout, app: *App, reg: *Registry, l: *Leaf, bar: rl.Rectangle) void {
        _ = self;
        const t = app.theme;
        var x = bar.x;

        for (0..l.count) |i| {
            const p = reg.get(l.panels[i]) orelse continue;
            const w = widget.measure(p.title, t.small_font) + 22;
            const r = rl.Rectangle{ .x = x, .y = bar.y + 3, .width = w, .height = bar.height - 3 };
            const is_active = @as(usize, @intCast(l.active)) == i;
            const over = widget.hovered(r);

            rl.drawRectangleRec(r, if (is_active) t.panel else if (over) t.panel_alt else t.bg);
            if (is_active) {
                rl.drawRectangleRec(
                    .{ .x = r.x, .y = r.y, .width = r.width, .height = 2 },
                    t.accent,
                );
            }
            widget.text(
                r.x + 11,
                r.y + (r.height - t.smallF()) / 2,
                t.small_font,
                if (is_active) t.text_bright else t.text_dim,
                p.title,
            );

            if (widget.clicked(r)) l.active = @intCast(i);
            x += w;
        }
    }
};
