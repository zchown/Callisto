const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");
const svg = @import("svg.zig");

const Pieces = chess.Pieces;
const Color = chess.Color;

pub const max_sets = 16;
pub const max_name = 40;
pub const max_path = 512;

pub const texture_scale: f32 = 1.14;

pub const min_render_px: i32 = 32;
pub const max_render_px: i32 = 512;
pub const render_step: i32 = 16;

pub const Source = enum { none, svg, png };

var requested_px: i32 = 0;

pub fn request(size: f32) void {
    if (size <= 0) return;
    const scaled = size * texture_scale * dpiScale();
    const px: i32 = @intFromFloat(@ceil(scaled));
    if (px > requested_px) requested_px = px;
}

fn dpiScale() f32 {
    const s = rl.getWindowScaleDPI();
    return if (s.x > 0.1) s.x else 1.0;
}

fn quantize(px: i32) i32 {
    const stepped = @divTrunc(px + render_step - 1, render_step) * render_step;
    return std.math.clamp(stepped, min_render_px, max_render_px);
}

pub const PieceSet = struct {
    name: [max_name]u8 = undefined,
    name_len: usize = 0,
    dir: [max_path]u8 = undefined,
    dir_len: usize = 0,

    source: Source = .none,
    white: [6]rl.Texture2D = undefined,
    black: [6]rl.Texture2D = undefined,
    loaded: bool = false,
    render_px: i32 = 0,

    pub fn nameSlice(self: *const PieceSet) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn dirSlice(self: *const PieceSet) []const u8 {
        return self.dir[0..self.dir_len];
    }

    pub fn load(
        self: *PieceSet,
        allocator: std.mem.Allocator,
        dir: []const u8,
        name: []const u8,
        px: i32,
    ) !void {
        const source = detect(dir, name) orelse return error.NoPieceFiles;

        var white: [6]rl.Texture2D = undefined;
        var black: [6]rl.Texture2D = undefined;
        var done: usize = 0;

        errdefer {
            var i: usize = 0;
            while (i < done) : (i += 1) {
                rl.unloadTexture(white[i]);
                rl.unloadTexture(black[i]);
            }
        }

        const letters = [_]u8{ 'P', 'N', 'B', 'R', 'Q', 'K' };
        for (letters, 0..) |letter_code, i| {
            white[i] = try loadOne(allocator, dir, name, 'w', letter_code, source, px);
            black[i] = try loadOne(allocator, dir, name, 'b', letter_code, source, px);
            done = i + 1;
        }

        self.unload();

        self.white = white;
        self.black = black;
        self.source = source;
        self.render_px = px;
        self.loaded = true;

        const n = @min(name.len, max_name);
        @memcpy(self.name[0..n], name[0..n]);
        self.name_len = n;

        const d = @min(dir.len, max_path);
        @memcpy(self.dir[0..d], dir[0..d]);
        self.dir_len = d;
    }

    pub fn resize(self: *PieceSet, allocator: std.mem.Allocator, px: i32) !void {
        if (!self.loaded or self.source != .svg) return;
        if (px == self.render_px) return;

        var name_buf: [max_name]u8 = undefined;
        var dir_buf: [max_path]u8 = undefined;
        @memcpy(name_buf[0..self.name_len], self.nameSlice());
        @memcpy(dir_buf[0..self.dir_len], self.dirSlice());

        try self.load(allocator, dir_buf[0..self.dir_len], name_buf[0..self.name_len], px);
    }

    fn detect(dir: []const u8, name: []const u8) ?Source {
        var buf: [max_path]u8 = undefined;
        const probes = [_]struct { ext: []const u8, source: Source }{
            .{ .ext = "svg", .source = .svg },
            .{ .ext = "png", .source = .png },
        };

        for (probes) |probe| {
            for ([_]u8{ 'P', 'p' }) |letter_code| {
                const path = std.fmt.bufPrintZ(&buf, "{s}/{s}/w{c}.{s}", .{
                    dir,
                    name,
                    letter_code,
                    probe.ext,
                }) catch continue;
                std.fs.cwd().access(path, .{}) catch continue;
                return probe.source;
            }
        }
        return null;
    }

    fn loadOne(
        allocator: std.mem.Allocator,
        dir: []const u8,
        set: []const u8,
        side: u8,
        letter_code: u8,
        source: Source,
        px: i32,
    ) !rl.Texture2D {
        const ext = switch (source) {
            .svg => "svg",
            .png => "png",
            .none => return error.NoPieceFiles,
        };

        var buf: [max_path]u8 = undefined;
        const cases = [_]u8{ letter_code, std.ascii.toLower(letter_code) };

        for (cases) |c| {
            const path = std.fmt.bufPrintZ(&buf, "{s}/{s}/{c}{c}.{s}", .{ dir, set, side, c, ext }) catch continue;
            std.fs.cwd().access(path, .{}) catch continue;

            if (source == .svg) {
                return svg.renderTexture(allocator, path, px) catch continue;
            }

            const tex = rl.loadTexture(path) catch continue;
            var t = tex;
            rl.genTextureMipmaps(&t);
            rl.setTextureFilter(t, .trilinear);
            return t;
        }

        return error.MissingPieceFile;
    }

    pub fn unload(self: *PieceSet) void {
        if (!self.loaded) return;
        for (self.white) |tex| rl.unloadTexture(tex);
        for (self.black) |tex| rl.unloadTexture(tex);
        self.loaded = false;
        self.source = .none;
        self.render_px = 0;
        self.name_len = 0;
    }

    fn texture(self: *const PieceSet, kind: Pieces, color: Color) ?rl.Texture2D {
        if (!self.loaded) return null;
        const index: usize = switch (kind) {
            .Pawn => 0,
            .Knight => 1,
            .Bishop => 2,
            .Rook => 3,
            .Queen => 4,
            .King => 5,
            .None => return null,
        };
        return if (color == .White) self.white[index] else self.black[index];
    }

    pub fn draw(
        self: *const PieceSet,
        kind: Pieces,
        color: Color,
        cx: f32,
        cy: f32,
        size: f32,
        tint: rl.Color,
    ) bool {
        const tex = self.texture(kind, color) orelse return false;
        if (tex.width <= 0 or tex.height <= 0) return false;

        request(size);

        const box = size * texture_scale;
        rl.drawTexturePro(
            tex,
            .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(tex.width),
                .height = @floatFromInt(tex.height),
            },
            .{ .x = cx - box / 2, .y = cy - box / 2, .width = box, .height = box },
            .{ .x = 0, .y = 0 },
            0,
            tint,
        );
        return true;
    }
};

pub const Library = struct {
    allocator: std.mem.Allocator = undefined,
    has_allocator: bool = false,

    dir: [max_path]u8 = undefined,
    dir_len: usize = 0,

    names: [max_sets][max_name]u8 = undefined,
    name_lens: [max_sets]usize = @splat(0),
    count: usize = 0,

    set: PieceSet = .{},

    pub fn dirSlice(self: *const Library) []const u8 {
        return self.dir[0..self.dir_len];
    }

    pub fn nameAt(self: *const Library, index: usize) []const u8 {
        if (index >= self.count) return "";
        return self.names[index][0..self.name_lens[index]];
    }

    pub fn has(self: *const Library, name: []const u8) bool {
        for (0..self.count) |i| {
            if (std.mem.eql(u8, self.nameAt(i), name)) return true;
        }
        return false;
    }

    pub fn current(self: *const Library) ?*const PieceSet {
        if (!self.set.loaded) return null;
        return &self.set;
    }

    pub fn currentName(self: *const Library) []const u8 {
        if (!self.set.loaded) return "";
        return self.set.nameSlice();
    }

    pub fn isVector(self: *const Library) bool {
        return self.set.loaded and self.set.source == .svg;
    }

    pub fn renderSize(self: *const Library) i32 {
        return self.set.render_px;
    }

    pub fn discover(self: *Library, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.has_allocator = true;
        self.count = 0;
        self.dir_len = 0;

        if (std.process.getEnvVarOwned(allocator, "CALLISTO_PIECES_DIR")) |env| {
            defer allocator.free(env);
            if (self.scan(env)) return;
        } else |_| {}

        if (self.scan("pieces")) return;

        const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch return;
        defer allocator.free(exe_dir);

        var buf: [max_path]u8 = undefined;
        const joined = std.fmt.bufPrint(&buf, "{s}/pieces", .{exe_dir}) catch return;
        _ = self.scan(joined);
    }

    fn scan(self: *Library, path: []const u8) bool {
        if (path.len == 0 or path.len >= max_path) return false;

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return false;
        defer dir.close();

        @memcpy(self.dir[0..path.len], path);
        self.dir_len = path.len;

        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            if (entry.kind != .directory) continue;
            if (entry.name.len == 0 or entry.name[0] == '.') continue;
            if (self.count >= max_sets) break;

            self.names[self.count] = @splat(0);
            const n = @min(entry.name.len, max_name);
            @memcpy(self.names[self.count][0..n], entry.name[0..n]);
            self.name_lens[self.count] = n;
            self.count += 1;
        }

        std.mem.sort([max_name]u8, self.names[0..self.count], {}, lessThanName);
        for (0..self.count) |i| {
            self.name_lens[i] = std.mem.indexOfScalar(u8, &self.names[i], 0) orelse max_name;
        }
        return self.count > 0;
    }

    fn lessThanName(_: void, a: [max_name]u8, b: [max_name]u8) bool {
        return std.mem.order(u8, &a, &b) == .lt;
    }

    pub fn select(self: *Library, name: []const u8) !void {
        if (name.len == 0) {
            self.set.unload();
            return;
        }
        if (!self.has_allocator) return error.NotReady;
        if (self.dir_len == 0) return error.NoPiecesDirectory;
        if (!self.has(name)) return error.NoSuchPieceSet;
        if (std.mem.eql(u8, self.currentName(), name)) return;

        const px = quantize(if (requested_px > 0) requested_px else 128);
        try self.set.load(self.allocator, self.dirSlice(), name, px);
    }

    pub fn applyPending(self: *Library) bool {
        const wanted = quantize(requested_px);
        requested_px = 0;

        if (!self.set.loaded or self.set.source != .svg) return false;
        if (wanted <= 0) return false;

        const current_px = self.set.render_px;
        const grew = wanted > current_px;
        const shrank_a_lot = wanted * 2 <= current_px;
        if (!grew and !shrank_a_lot) return false;

        self.set.resize(self.allocator, wanted) catch return false;
        return true;
    }

    pub fn unload(self: *Library) void {
        self.set.unload();
        svg.shutdown();
    }
};
