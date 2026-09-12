const std = @import("std");
const rl = @import("raylib");

pub const Error = error{
    ParseFailed,
    RasterizerFailed,
    EmptyImage,
    OutOfMemory,
};

const NSVGimage = extern struct {
    width: f32,
    height: f32,
    shapes: ?*anyopaque,
};

const NSVGrasterizer = opaque {};

extern fn nsvgParseFromFile(filename: [*:0]const u8, units: [*:0]const u8, dpi: f32) ?*NSVGimage;
extern fn nsvgDelete(image: ?*NSVGimage) void;
extern fn nsvgCreateRasterizer() ?*NSVGrasterizer;
extern fn nsvgDeleteRasterizer(r: ?*NSVGrasterizer) void;
extern fn nsvgRasterize(
    r: ?*NSVGrasterizer,
    image: ?*NSVGimage,
    tx: f32,
    ty: f32,
    scale: f32,
    dst: [*]u8,
    w: c_int,
    h: c_int,
    stride: c_int,
) void;

var rasterizer: ?*NSVGrasterizer = null;

pub fn shutdown() void {
    if (rasterizer) |r| {
        nsvgDeleteRasterizer(r);
        rasterizer = null;
    }
}

fn getRasterizer() Error!*NSVGrasterizer {
    if (rasterizer) |r| return r;
    const r = nsvgCreateRasterizer() orelse return error.RasterizerFailed;
    rasterizer = r;
    return r;
}

pub fn renderTexture(allocator: std.mem.Allocator, path: [:0]const u8, px: i32) !rl.Texture2D {
    const size: usize = @intCast(@max(px, 1));

    const svg = nsvgParseFromFile(path.ptr, "px", 96) orelse return error.ParseFailed;
    defer nsvgDelete(svg);

    if (svg.width <= 0 or svg.height <= 0) return error.EmptyImage;

    const r = try getRasterizer();

    const pixels = try allocator.alloc(u8, size * size * 4);
    defer allocator.free(pixels);
    @memset(pixels, 0);

    const target: f32 = @floatFromInt(size);
    const scale = @min(target / svg.width, target / svg.height);
    const tx = (target - svg.width * scale) / 2;
    const ty = (target - svg.height * scale) / 2;

    nsvgRasterize(
        r,
        svg,
        tx,
        ty,
        scale,
        pixels.ptr,
        @intCast(size),
        @intCast(size),
        @intCast(size * 4),
    );

    const image = rl.Image{
        .data = @ptrCast(pixels.ptr),
        .width = @intCast(size),
        .height = @intCast(size),
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };

    var tex = try rl.loadTextureFromImage(image);
    rl.genTextureMipmaps(&tex);
    rl.setTextureFilter(tex, .trilinear);
    return tex;
}
