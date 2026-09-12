const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;

const vm_mod = @import("vm.zig");
const Vm = vm_mod.Vm;
const panel_mod = @import("../ui/panel.zig");
const layout_mod = @import("../ui/layout.zig");
const views_mod = @import("../ui/views.zig");
const icons = @import("../ui/icons.zig");

const Registry = panel_mod.Registry;
const Layout = layout_mod.Layout;
const NodeId = layout_mod.NodeId;

pub const Error = error{
    BadSpec,
    UnknownPanel,
    LayoutFull,
};

pub fn apply(vm: *Vm, reg: *Registry, views: *views_mod.ViewSet) usize {
    const lua = vm.lua orelse return 0;
    if (vm.views_ref == vm_mod.no_ref) return 0;

    const before = lua.getTop();
    defer lua.setTop(before);

    _ = lua.rawGetIndex(zlua.registry_index, vm.views_ref);
    if (!lua.isTable(-1)) return 0;
    const table = lua.getTop();

    var applied: usize = 0;

    lua.pushNil();
    while (lua.next(table)) {
        const spec = lua.getTop();
        defer lua.setTop(spec - 1); 

        if (lua.typeOf(-2) != .string or !lua.isTable(spec)) continue;
        const id = lua.toString(-2) catch continue;

        var candidate = Layout{};
        const root = buildNode(lua, reg, &candidate, spec) catch |err| {
            vm.app.log.print("lua", .err, "view '{s}' ignored: {s}", .{ id, @errorName(err) });
            continue;
        };
        candidate.root = root;

        const view = views.ensure(id) orelse {
            vm.app.log.print("lua", .err, "too many views for '{s}'", .{id});
            continue;
        };
        view.layout = candidate;
        view.ready = true;
        applyChrome(lua, spec, view);
        applied += 1;
    }

    return applied;
}

fn applyChrome(lua: *Lua, spec: i32, view: *views_mod.View) void {
    {
        const top = lua.getTop();
        defer lua.setTop(top);
        if (lua.getField(spec, "label") == .string) {
            if (lua.toString(-1)) |label| {
                views_mod.ViewSet.setLabel(view, label);
            } else |_| {}
        }
    }
    {
        const top = lua.getTop();
        defer lua.setTop(top);
        if (lua.getField(spec, "icon") == .string) {
            if (lua.toString(-1)) |name| {
                view.icon = icons.Icon.parse(name);
            } else |_| {}
        }
    }
    {
        const top = lua.getTop();
        defer lua.setTop(top);
        const kind = lua.getField(spec, "sidebar");
        if (kind == .boolean) view.in_sidebar = lua.toBoolean(-1);
    }
}

fn buildNode(lua: *Lua, reg: *Registry, layout: *Layout, index: i32) Error!NodeId {
    if (!lua.isTable(index)) return error.BadSpec;

    // { panel = "board" }
    {
        const top = lua.getTop();
        defer lua.setTop(top);

        if (lua.getField(index, "panel") == .string) {
            const name = lua.toString(-1) catch return error.BadSpec;
            const idx = reg.indexOf(name) orelse return error.UnknownPanel;
            return layout.leaf(idx) catch error.LayoutFull;
        }
    }

    // { tabs = { "moves", "match" } }
    {
        const top = lua.getTop();
        defer lua.setTop(top);

        if (lua.getField(index, "tabs") == .table) {
            const tabs_index = lua.getTop();
            var ids: [8]usize = undefined;
            var n: usize = 0;

            const count = lua.rawLen(tabs_index);
            var i: usize = 1;
            while (i <= count and n < ids.len) : (i += 1) {
                const entry_top = lua.getTop();
                defer lua.setTop(entry_top);

                if (lua.rawGetIndex(tabs_index, @intCast(i)) != .string) continue;
                const name = lua.toString(-1) catch continue;
                const idx = reg.indexOf(name) orelse continue;
                ids[n] = idx;
                n += 1;
            }

            if (n == 0) return error.UnknownPanel;
            return layout.tabs(ids[0..n]) catch error.LayoutFull;
        }
    }

    // { split = "horizontal", ratio = .., first = .., second = .. }
    const top = lua.getTop();
    defer lua.setTop(top);

    if (lua.getField(index, "split") != .string) return error.BadSpec;
    const dir_name = lua.toString(-1) catch return error.BadSpec;
    const dir: layout_mod.Dir = if (std.mem.eql(u8, dir_name, "vertical")) .vertical else .horizontal;

    var ratio: f32 = 0.5;
    {
        const t2 = lua.getTop();
        defer lua.setTop(t2);
        if (lua.getField(index, "ratio") == .number) {
            ratio = @floatCast(lua.toNumber(-1) catch 0.5);
        }
    }

    var min_first: f32 = 160;
    var min_second: f32 = 160;
    {
        const t2 = lua.getTop();
        defer lua.setTop(t2);
        if (lua.getField(index, "min_first") == .number) {
            min_first = @floatCast(lua.toNumber(-1) catch 160);
        }
    }
    {
        const t2 = lua.getTop();
        defer lua.setTop(t2);
        if (lua.getField(index, "min_second") == .number) {
            min_second = @floatCast(lua.toNumber(-1) catch 160);
        }
    }

    if (lua.getField(index, "first") != .table) return error.BadSpec;
    const first = try buildNode(lua, reg, layout, lua.getTop());
    lua.pop(1);

    if (lua.getField(index, "second") != .table) return error.BadSpec;
    const second = try buildNode(lua, reg, layout, lua.getTop());
    lua.pop(1);

    const id = layout.split(dir, std.math.clamp(ratio, 0.05, 0.95), first, second) catch return error.LayoutFull;
    layout.nodes[id].split.min_first = min_first;
    layout.nodes[id].split.min_second = min_second;
    return id;
}
