const std = @import("std");
const rl = @import("raylib");
const App = @import("../app.zig").App;

pub const max_panels = 32;

pub const Panel = struct {
    title: [:0]const u8,
    ptr: *anyopaque,
    vtable: *const VTable,
    draws_own_background: bool = false,

    pub const VTable = struct {
        draw: *const fn (ctx: *anyopaque, app: *App, bounds: rl.Rectangle) void,
        update: ?*const fn (ctx: *anyopaque, app: *App, dt: f32) void = null,
        onClose: ?*const fn (ctx: *anyopaque, app: *App) void = null,
    };

    pub fn draw(self: Panel, app: *App, bounds: rl.Rectangle) void {
        self.vtable.draw(self.ptr, app, bounds);
    }

    pub fn update(self: Panel, app: *App, dt: f32) void {
        if (self.vtable.update) |f| f(self.ptr, app, dt);
    }

    pub fn close(self: Panel, app: *App) void {
        if (self.vtable.onClose) |f| f(self.ptr, app);
    }

    pub fn from(instance: anytype, title: [:0]const u8) Panel {
        const Ptr = @TypeOf(instance);
        const T = @typeInfo(Ptr).pointer.child;

        const glue = struct {
            fn drawImpl(ctx: *anyopaque, app: *App, bounds: rl.Rectangle) void {
                T.draw(@ptrCast(@alignCast(ctx)), app, bounds);
            }
            fn updateImpl(ctx: *anyopaque, app: *App, dt: f32) void {
                T.update(@ptrCast(@alignCast(ctx)), app, dt);
            }
            fn closeImpl(ctx: *anyopaque, app: *App) void {
                T.onClose(@ptrCast(@alignCast(ctx)), app);
            }

            const vtable = VTable{
                .draw = drawImpl,
                .update = if (@hasDecl(T, "update")) updateImpl else null,
                .onClose = if (@hasDecl(T, "onClose")) closeImpl else null,
            };
        };

        const owns_bg = comptime if (@hasDecl(T, "draws_own_background")) T.draws_own_background else false;

        return .{
            .title = title,
            .ptr = @ptrCast(instance),
            .vtable = &glue.vtable,
            .draws_own_background = owns_bg,
        };
    }
};

pub const Registry = struct {
    items: [max_panels]Panel = undefined,
    count: usize = 0,

    pub fn add(self: *Registry, p: Panel) usize {
        if (self.count >= max_panels) return 0;
        const idx = self.count;
        self.items[idx] = p;
        self.count += 1;
        return idx;
    }

    pub fn get(self: *Registry, index: usize) ?*Panel {
        if (index >= self.count) return null;
        return &self.items[index];
    }

    pub fn slice(self: *Registry) []Panel {
        return self.items[0..self.count];
    }
};
