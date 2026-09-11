const rl = @import("raylib");

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

pub const Theme = struct {
    bg: rl.Color = rgb(0x0F1319),
    panel: rl.Color = rgb(0x171C24),
    panel_alt: rl.Color = rgb(0x1E2530),
    row_alt: rl.Color = rgb(0x1A212B),
    border: rl.Color = rgb(0x2B3543),
    divider: rl.Color = rgb(0x39465A),
    separator: rl.Color = rgb(0x232C38),
    overlay: rl.Color = rgba(0x0F1319, 210),

    text: rl.Color = rgb(0xC6D0DC),
    text_dim: rl.Color = rgb(0x76838F),
    text_bright: rl.Color = rgb(0xEDF2F7),

    accent: rl.Color = rgb(0x5FA8D3),
    accent_dim: rl.Color = rgb(0x35617C),

    good: rl.Color = rgb(0x7FB069),
    bad: rl.Color = rgb(0xD1655B),
    warn: rl.Color = rgb(0xE0A94A),

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
    hl_select: rl.Color = rgb(0x5FA8D3),
    hl_check: rl.Color = rgb(0xD1655B),
    hl_legal: rl.Color = rgb(0x1E2530),
    hl_hover: rl.Color = rgb(0xEDF2F7),

    arrow_user: rl.Color = rgb(0xE0A94A),
    arrow_pv: rl.Color = rgb(0x5FA8D3),
    arrow_pv_alt: rl.Color = rgb(0x8E7CC3),

    row_h: f32 = 22,
    pad: f32 = 8,
    radius: f32 = 0.25,
    font_size: i32 = 16,
    small_font: i32 = 13,
    big_font: i32 = 22,

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
};

pub const default = Theme{};
