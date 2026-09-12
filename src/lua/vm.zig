const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;

const App = @import("../app.zig").App;
const ui_mod = @import("../ui/ui.zig");
const widget = @import("../ui/widget.zig");
const api = @import("api.zig");

pub const no_ref: i32 = -2;

pub const max_panels = 16;
pub const max_keymaps = 24;

pub const Panel = struct {
    name: [32]u8 = undefined,
    name_len: usize = 0,
    title: [40]u8 = undefined,
    title_len: usize = 0,
    draw_ref: i32 = no_ref,
    registry_index: ?usize = null,
    live: bool = false,
    scroll: widget.Scroll = .{},
    last_content_h: f32 = 0,
    failed: bool = false,
    err: [200]u8 = undefined,
    err_len: usize = 0,

    pub fn nameSlice(self: *const Panel) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn titleZ(self: *Panel) [:0]const u8 {
        self.title[self.title_len] = 0;
        return self.title[0..self.title_len :0];
    }

    pub fn errSlice(self: *const Panel) []const u8 {
        return self.err[0..self.err_len];
    }
};

pub const KeyMap = struct {
    key: [16]u8 = undefined,
    key_len: usize = 0,
    ref: i32 = no_ref,
    live: bool = false,
};

pub const Event = enum { position, engine_info, game_over, frame };

const Embedded = struct {
    name: [:0]const u8,
    source: [:0]const u8,
};

const embedded_scripts = [_]Embedded{
    .{ .name = "init", .source = @embedFile("lua_init") },
    .{ .name = "panels.evaluation", .source = @embedFile("lua_panels_evaluation") },
    .{ .name = "panels.engine", .source = @embedFile("lua_panels_engine") },
    .{ .name = "panels.moves", .source = @embedFile("lua_panels_moves") },
    .{ .name = "panels.settings", .source = @embedFile("lua_panels_settings") },
};

pub const Vm = struct {
    allocator: std.mem.Allocator,
    app: *App,
    lua: ?*Lua = null,

    panels: [max_panels]Panel = @splat(.{}),
    panel_count: usize = 0,

    keymaps: [max_keymaps]KeyMap = @splat(.{}),
    keymap_count: usize = 0,

    on_position: i32 = no_ref,
    on_engine_info: i32 = no_ref,
    on_game_over: i32 = no_ref,
    on_frame: i32 = no_ref,

    views_ref: i32 = no_ref,
    views_dirty: bool = false,

    script_dir: [512]u8 = undefined,
    script_dir_len: usize = 0,
    from_disk: bool = false,

    ok: bool = false,
    err: [320]u8 = undefined,
    err_len: usize = 0,

    last_position: u64 = 0,

    pub fn init(self: *Vm, allocator: std.mem.Allocator, app: *App) void {
        self.* = .{ .allocator = allocator, .app = app };
        self.findScriptDir();
    }

    pub fn deinit(self: *Vm) void {
        self.teardown();
    }

    pub fn errSlice(self: *const Vm) []const u8 {
        return self.err[0..self.err_len];
    }

    pub fn scriptDir(self: *const Vm) []const u8 {
        return self.script_dir[0..self.script_dir_len];
    }

    fn setError(self: *Vm, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(&self.err, fmt, args) catch {
            self.err_len = 0;
            return;
        };
        self.err_len = w.len;
        self.app.log.add("lua", .err, self.errSlice());
    }

    fn findScriptDir(self: *Vm) void {
        self.script_dir_len = 0;
        self.from_disk = false;

        if (std.process.getEnvVarOwned(self.allocator, "CALLISTO_LUA_DIR")) |dir| {
            defer self.allocator.free(dir);
            if (self.tryScriptDir(dir)) return;
        } else |_| {}

        if (self.tryScriptDir("lua")) return;

        const exe_dir = std.fs.selfExeDirPathAlloc(self.allocator) catch return;
        defer self.allocator.free(exe_dir);

        var buf: [512]u8 = undefined;
        const joined = std.fmt.bufPrint(&buf, "{s}/lua", .{exe_dir}) catch return;
        _ = self.tryScriptDir(joined);
    }

    fn tryScriptDir(self: *Vm, dir: []const u8) bool {
        var handle = std.fs.cwd().openDir(dir, .{}) catch return false;
        handle.close();
        if (dir.len >= self.script_dir.len) return false;

        @memcpy(self.script_dir[0..dir.len], dir);
        self.script_dir_len = dir.len;
        self.from_disk = true;
        return true;
    }

    fn diskPath(self: *Vm, module: []const u8, buf: []u8) ?[]const u8 {
        if (!self.from_disk) return null;

        var rel: [128]u8 = undefined;
        if (module.len >= rel.len) return null;
        for (module, 0..) |c, i| rel[i] = if (c == '.') '/' else c;

        const path = std.fmt.bufPrintZ(buf, "{s}/{s}.lua", .{ self.scriptDir(), rel[0..module.len] }) catch return null;
        std.fs.cwd().access(path, .{}) catch return null;
        return path;
    }

    pub fn load(self: *Vm) void {
        self.teardown();
        self.err_len = 0;

        const lua = Lua.init(self.allocator) catch |e| {
            self.setError("could not create the Lua state: {s}", .{@errorName(e)});
            return;
        };
        self.lua = lua;

        lua.openLibs();
        _ = lua.gcSetGenerational(0, 0);

        api.install(self, lua);
        self.preloadEmbedded(lua);

        ui_mod.resetInputs();

        self.runInit(lua);
    }

    fn teardown(self: *Vm) void {
        if (self.lua) |lua| {
            lua.deinit();
            self.lua = null;
        }
        for (&self.panels) |*p| {
            p.draw_ref = no_ref;
            p.failed = false;
            p.err_len = 0;
        }
        for (&self.keymaps) |*k| {
            k.ref = no_ref;
            k.live = false;
        }
        self.keymap_count = 0;
        self.on_position = no_ref;
        self.on_engine_info = no_ref;
        self.on_game_over = no_ref;
        self.on_frame = no_ref;
        self.views_ref = no_ref;
        self.ok = false;
    }

    fn preloadEmbedded(self: *Vm, lua: *Lua) void {
        _ = lua.getGlobal("package") catch {
            lua.pop(1);
            return;
        };
        _ = lua.getField(-1, "preload");

        for (embedded_scripts) |script| {
            var path_buf: [640]u8 = undefined;
            if (self.diskPath(script.name, &path_buf) != null) continue;

            var chunk_buf: [96]u8 = undefined;
            const chunk = std.fmt.bufPrintZ(&chunk_buf, "@embedded:{s}", .{script.name}) catch "@embedded";

            lua.loadBuffer(script.source, chunk, .text) catch {
                self.setError("embedded script {s} failed to compile", .{script.name});
                continue;
            };
            lua.setField(-2, script.name);
        }

        lua.pop(2);
    }

    fn runInit(self: *Vm, lua: *Lua) void {
        if (self.from_disk) {
            var buf: [1200]u8 = undefined;
            const chunk = std.fmt.bufPrintZ(
                &buf,
                "package.path = '{s}/?.lua;{s}/?/init.lua;' .. package.path",
                .{ self.scriptDir(), self.scriptDir() },
            ) catch "";
            lua.doString(chunk) catch {};
        }

        const source = "local ok, err = pcall(require, 'init') if not ok then error(err, 0) end";
        lua.loadString(source) catch |e| {
            self.setError("could not compile the loader: {s}", .{@errorName(e)});
            return;
        };

        self.protected(lua, 0) catch return;

        self.ok = true;
        self.views_dirty = true;
        if (self.from_disk) {
            self.app.log.print("lua", .note, "UI loaded from {s}", .{self.scriptDir()});
        } else {
            self.app.log.add("lua", .note, "UI loaded from the embedded scripts");
        }
    }

    pub fn reload(self: *Vm) void {
        self.app.log.add("lua", .note, "reloading the UI");
        self.load();
    }

    fn tracebackHandler(lua: *Lua) i32 {
        const msg = lua.toString(1) catch "error";
        lua.traceback(lua, msg, 1);
        return 1;
    }

    fn protected(self: *Vm, lua: *Lua, nargs: i32) !void {
        const base = lua.getTop() - nargs; 
        lua.pushFunction(zlua.wrap(tracebackHandler));
        lua.insert(base);

        lua.protectedCall(.{ .args = nargs, .results = 0, .msg_handler = base }) catch |e| {
            const msg = lua.toString(-1) catch "unknown error";
            self.setError("{s}", .{msg});
            lua.pop(1);
            lua.remove(base);
            return e;
        };

        lua.remove(base);
    }

    pub fn hasPanels(self: *const Vm) bool {
        return self.panel_count > 0;
    }

    pub fn panelAt(self: *Vm, index: usize) ?*Panel {
        if (index >= self.panel_count) return null;
        if (!self.panels[index].live) return null;
        return &self.panels[index];
    }

    pub fn findPanel(self: *Vm, name: []const u8) ?*Panel {
        for (self.panels[0..self.panel_count]) |*p| {
            if (std.mem.eql(u8, p.nameSlice(), name)) return p;
        }
        return null;
    }

    pub fn registerPanel(self: *Vm, name: []const u8, title: []const u8, draw_ref: i32) ?*Panel {
        if (self.findPanel(name)) |existing| {
            if (self.lua) |lua| {
                if (existing.draw_ref != no_ref) lua.unref(zlua.registry_index, existing.draw_ref);
            }
            existing.draw_ref = draw_ref;
            existing.live = true;
            existing.failed = false;
            existing.err_len = 0;
            setTitle(existing, title);
            return existing;
        }

        if (self.panel_count >= max_panels) return null;
        const p = &self.panels[self.panel_count];
        p.* = .{};

        const n = @min(name.len, p.name.len);
        @memcpy(p.name[0..n], name[0..n]);
        p.name_len = n;
        setTitle(p, title);

        p.draw_ref = draw_ref;
        p.live = true;
        self.panel_count += 1;
        return p;
    }

    fn setTitle(p: *Panel, title: []const u8) void {
        const n = @min(title.len, p.title.len - 1);
        @memcpy(p.title[0..n], title[0..n]);
        p.title_len = n;
    }

    pub fn drawPanel(self: *Vm, panel: *Panel, ui: *ui_mod.Ui) void {
        if (panel.failed) {
            ui.dim("this panel raised an error:");
            ui.dim(panel.errSlice());
            if (ui.button("reload ui", .primary)) self.reload();
            return;
        }

        const lua = self.lua orelse {
            ui.dim("no Lua state");
            return;
        };
        if (panel.draw_ref == no_ref) {
            ui.dim("panel has no draw function");
            return;
        }

        const before = lua.getTop();
        _ = lua.rawGetIndex(zlua.registry_index, panel.draw_ref);

        api.beginPanelDraw(ui);
        defer api.endPanelDraw();

        self.protected(lua, 0) catch {
            panel.failed = true;
            const msg = self.errSlice();
            const n = @min(msg.len, panel.err.len);
            @memcpy(panel.err[0..n], msg[0..n]);
            panel.err_len = n;
        };

        lua.setTop(before);
        ui.finish();
    }

    fn refFor(self: *Vm, event: Event) *i32 {
        return switch (event) {
            .position => &self.on_position,
            .engine_info => &self.on_engine_info,
            .game_over => &self.on_game_over,
            .frame => &self.on_frame,
        };
    }

    pub fn setHandler(self: *Vm, event: Event, ref: i32) void {
        const slot = self.refFor(event);
        if (self.lua) |lua| {
            if (slot.* != no_ref) lua.unref(zlua.registry_index, slot.*);
        }
        slot.* = ref;
    }

    pub fn fire(self: *Vm, event: Event) void {
        const lua = self.lua orelse return;
        const ref = self.refFor(event).*;
        if (ref == no_ref) return;

        const before = lua.getTop();
        _ = lua.rawGetIndex(zlua.registry_index, ref);
        self.protected(lua, 0) catch {};
        lua.setTop(before);
    }

    pub fn addKeyMap(self: *Vm, key: []const u8, ref: i32) void {
        for (self.keymaps[0..self.keymap_count]) |*k| {
            if (!std.mem.eql(u8, k.key[0..k.key_len], key)) continue;
            if (self.lua) |lua| {
                if (k.ref != no_ref) lua.unref(zlua.registry_index, k.ref);
            }
            k.ref = ref;
            k.live = true;
            return;
        }
        if (self.keymap_count >= max_keymaps) return;

        const k = &self.keymaps[self.keymap_count];
        const n = @min(key.len, k.key.len);
        @memcpy(k.key[0..n], key[0..n]);
        k.key_len = n;
        k.ref = ref;
        k.live = true;
        self.keymap_count += 1;
    }

    pub fn fireKey(self: *Vm, key: []const u8) bool {
        const lua = self.lua orelse return false;
        for (self.keymaps[0..self.keymap_count]) |*k| {
            if (!k.live or k.ref == no_ref) continue;
            if (!std.mem.eql(u8, k.key[0..k.key_len], key)) continue;

            const before = lua.getTop();
            _ = lua.rawGetIndex(zlua.registry_index, k.ref);
            self.protected(lua, 0) catch {};
            lua.setTop(before);
            return true;
        }
        return false;
    }

    pub fn update(self: *Vm) void {
        if (!self.ok) return;

        const hash = self.app.game.displayState().cur_position.hash;
        if (hash != self.last_position) {
            self.last_position = hash;
            self.fire(.position);
        }
        self.fire(.frame);
    }
};
