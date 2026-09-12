const std = @import("std");
const rl = @import("raylib");
const chess = @import("chess");

const Pieces = chess.Pieces;
const Color = chess.Color;

pub const max_sets = 16;
pub const max_name = 40;
pub const max_path = 512;

pub const texture_scale: f32 = 1.14;

pub const PieceSet = struct {
    name: [max_name]u8 = undefined,
    name_len: usize = 0,
    white: [6]rl.Texture2D = undefined,
    black: [6]rl.Texture2D = undefined,
    loaded: bool = false,

    pub fn nameSlice(self: *const PieceSet) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn load(self: *PieceSet, dir: []const u8, name: []const u8) !void {
        self.unload();

        const n = @min(name.len, max_name);
        @memcpy(self.name[0..n], name[0..n]);
        self.name_len = n;

        var done: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < done) : (i += 1) {
                rl.unloadTexture(self.white[i]);
                rl.unloadTexture(self.black[i]);
            }
            self.loaded = false;
        }

        const letters = [_]u8{ 'P', 'N', 'B', 'R', 'Q', 'K' };
        for (letters, 0..) |letter_code, i| {
            self.white[i] = try loadOne(dir, name, 'w', letter_code);
            self.black[i] = try loadOne(dir, name, 'b', letter_code);
            done = i + 1;
        }

        self.loaded = true;
    }

    fn loadOne(dir: []const u8, set: []const u8, side: u8, letter_code: u8) !rl.Texture2D {
        var buf: [max_path]u8 = undefined;

        const upper = try std.fmt.bufPrintZ(&buf, "{s}/{s}/{c}{c}.png", .{ dir, set, side, letter_code });
        if (rl.loadTexture(upper)) |tex| {
            return finish(tex);
        } else |_| {}

        const lower = try std.fmt.bufPrintZ(&buf, "{s}/{s}/{c}{c}.png", .{
            dir,
            set,
            side,
            std.ascii.toLower(letter_code),
        });
        const tex = try rl.loadTexture(lower);
        return finish(tex);
    }

    fn finish(tex: rl.Texture2D) rl.Texture2D {
        var t = tex;
        rl.genTextureMipmaps(&t);
        rl.setTextureFilter(t, .trilinear);
        return t;
    }

    pub fn unload(self: *PieceSet) void {
        if (!self.loaded) return;
        for (self.white) |tex| rl.unloadTexture(tex);
        for (self.black) |tex| rl.unloadTexture(tex);
        self.loaded = false;
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

    pub fn discover(self: *Library, allocator: std.mem.Allocator) void {
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
        if (self.dir_len == 0) return error.NoPiecesDirectory;
        if (!self.has(name)) return error.NoSuchPieceSet;
        if (std.mem.eql(u8, self.currentName(), name)) return;

        try self.set.load(self.dirSlice(), name);
    }

    pub fn unload(self: *Library) void {
        self.set.unload();
    }
};
