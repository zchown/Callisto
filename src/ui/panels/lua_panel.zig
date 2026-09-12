const std = @import("std");
const rl = @import("raylib");

const App = @import("../../app.zig").App;
const widget = @import("../widget.zig");
const ui_mod = @import("../ui.zig");
const vm_mod = @import("../../lua/vm.zig");

pub const LuaPanel = struct {
    vm: *vm_mod.Vm,
    index: usize,

    pub fn draw(self: *LuaPanel, app: *App, bounds: rl.Rectangle) void {
        const t = app.theme;
        const panel = self.vm.panelAt(self.index) orelse {
            widget.text(bounds.x + 8, bounds.y + 8, t.small_font, t.text_dim, "panel is no longer registered");
            return;
        };

        const area = widget.inset(bounds, 8);
        if (area.width <= 0 or area.height <= 0) return;

        panel.scroll.handle(area, panel.last_content_h);

        rl.beginScissorMode(
            @intFromFloat(area.x),
            @intFromFloat(area.y),
            @intFromFloat(@max(area.width, 0)),
            @intFromFloat(@max(area.height, 0)),
        );

        var ui = ui_mod.Ui.init(app, area, panel.scroll.offset);
        self.vm.drawPanel(panel, &ui);
        panel.last_content_h = ui.contentHeight();

        rl.endScissorMode();

        panel.scroll.drawBar(t, area, panel.last_content_h);
    }
};

pub const Slots = struct {
    items: [vm_mod.max_panels]LuaPanel = undefined,
    count: usize = 0,

    pub fn make(self: *Slots, vm: *vm_mod.Vm, index: usize) ?*LuaPanel {
        if (self.count >= self.items.len) return null;
        const slot = &self.items[self.count];
        slot.* = .{ .vm = vm, .index = index };
        self.count += 1;
        return slot;
    }
};
