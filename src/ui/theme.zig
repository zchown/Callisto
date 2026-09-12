const rl = @import("raylib");
const piece_set = @import("piece_set.zig");

pub fn rgb(hex: u24) rl.Color {
    return .{
        .r = @truncate(hex >> 16),
        .g = @truncate(hex >> 8),
        .b = @truncate(hex),
        .a = 255,
    };
}

pub fn rgba(hex: u24, a: u8) rl.Color {
    var c = rgb(hex);
    c.a = a;
    return c;
}

pub fn roundness(r: rl.Rectangle, px: f32) f32 {
    const short = @min(r.width, r.height);
    if (short <= 0) return 0;
    return @min(px * 2.0 / short, 1.0);
}

pub const Theme = struct {
    bg: rl.Color = rgb(0x101216),
    sidebar: rl.Color = rgb(0x0C0E12),
    panel: rl.Color = rgb(0x171A21),
    panel_alt: rl.Color = rgb(0x1E222B),
    elevated: rl.Color = rgb(0x252A35),
    row_alt: rl.Color = rgb(0x1A1E26),

    border: rl.Color = rgb(0x272C36),
    border_soft: rl.Color = rgb(0x1F242C),
    divider: rl.Color = rgb(0x39414F),
    separator: rl.Color = rgb(0x222730),
    overlay: rl.Color = rgba(0x08090C, 220),

    text: rl.Color = rgb(0xC8CEDA),
    text_dim: rl.Color = rgb(0x7B8598),
    text_bright: rl.Color = rgb(0xEDF1F7),

    accent: rl.Color = rgb(0x4DABF7),
    accent_dim: rl.Color = rgb(0x1D3B57),
    accent_soft: rl.Color = rgba(0x4DABF7, 38),

    good: rl.Color = rgb(0x51CF8F),
    bad: rl.Color = rgb(0xE5646B),
    warn: rl.Color = rgb(0xE0A94A),

    pieces: ?*const piece_set.PieceSet = null,
    piece_tint: bool = false,

    // Board
    sq_light: rl.Color = rgb(0xD8D3C7),
    sq_dark: rl.Color = rgb(0x6E7E8C),
    coord_light: rl.Color = rgb(0x6E7E8C),
    coord_dark: rl.Color = rgb(0xD8D3C7),

    piece_white: rl.Color = rgb(0xF6F4EF),
    piece_black: rl.Color = rgb(0x23272E),
    piece_white_edge: rl.Color = rgb(0x6A6862),
    piece_black_edge: rl.Color = rgb(0xB9BFC7),

    hl_last: rl.Color = rgb(0xE0A94A),
    hl_select: rl.Color = rgb(0x4DABF7),
    hl_check: rl.Color = rgb(0xE5646B),
    hl_legal: rl.Color = rgb(0x1E2530),
    hl_hover: rl.Color = rgb(0xEDF2F7),

    arrow_user: rl.Color = rgb(0xE0A94A),
    arrow_pv: rl.Color = rgb(0x4DABF7),
    arrow_pv_alt: rl.Color = rgb(0x9B87D6),

    row_h: f32 = 26,
    pad: f32 = 12,
    card_pad: f32 = 16,
    gap: f32 = 10,
    radius: f32 = 0.25,
    radius_px: f32 = 7,
    card_radius_px: f32 = 10,

    font_size: i32 = 15,
    small_font: i32 = 13,
    big_font: i32 = 19,
    title_font: i32 = 26,

    sidebar_w: f32 = 188,
    sidebar_w_collapsed: f32 = 56,
    tabbar_h: f32 = 38,
    statusbar_h: f32 = 26,

    pub fn evalColor(self: Theme, cp: i32) rl.Color {
        if (cp > 30) return self.good;
        if (cp < -30) return self.bad;
        return self.text_dim;
    }

    pub fn fontF(self: Theme) f32 {
        return @floatFromInt(self.font_size);
    }

    pub fn smallF(self: Theme) f32 {
        return @floatFromInt(self.small_font);
    }

    pub fn bigF(self: Theme) f32 {
        return @floatFromInt(self.big_font);
    }
};

pub const default = Theme{};
