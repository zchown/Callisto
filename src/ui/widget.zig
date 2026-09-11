const std = @import("std");
const rl = @import("raylib");
const theme_mod = @import("theme.zig");

const Theme = theme_mod.Theme;

pub var font: ?rl.Font = null;

pub threadlocal var scratch: [1024]u8 = undefined;

pub fn z(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(&scratch, fmt, args) catch "...";
}

pub fn zBuf(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, args) catch "...";
}

pub fn zSlice(buf: []u8, s: []const u8) [:0]const u8 {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
    return buf[0..n :0];
}

pub fn measure(s: [:0]const u8, size: i32) f32 {
    if (font) |f| {
        return rl.measureTextEx(f, s, @floatFromInt(size), 1.0).x;
    }
    return @floatFromInt(rl.measureText(s, size));
}

pub fn text(x: f32, y: f32, size: i32, color: rl.Color, s: [:0]const u8) void {
    if (font) |f| {
        rl.drawTextEx(f, s, .{ .x = @round(x), .y = @round(y) }, @floatFromInt(size), 1.0, color);
    } else {
        rl.drawText(s, @intFromFloat(x), @intFromFloat(y), size, color);
    }
}

pub fn textRight(right_x: f32, y: f32, size: i32, color: rl.Color, s: [:0]const u8) void {
    text(right_x - measure(s, size), y, size, color, s);
}

pub fn textCentered(cx: f32, y: f32, size: i32, color: rl.Color, s: [:0]const u8) void {
    text(cx - measure(s, size) / 2, y, size, color, s);
}

pub fn textIn(r: rl.Rectangle, pad: f32, size: i32, color: rl.Color, s: [:0]const u8) void {
    text(r.x + pad, r.y + (r.height - @as(f32, @floatFromInt(size))) / 2, size, color, s);
}

pub fn textClipped(x: f32, y: f32, max_w: f32, size: i32, color: rl.Color, s: [:0]const u8, buf: []u8) void {
    if (measure(s, size) <= max_w) {
        text(x, y, size, color, s);
        return;
    }
    var n: usize = @min(s.len, buf.len - 5);
    while (n > 0) : (n -= 1) {
        const candidate = zBuf(buf, "{s}...", .{s[0..n]});
        if (measure(candidate, size) <= max_w) {
            text(x, y, size, color, candidate);
            return;
        }
    }
}

pub fn row(bounds: rl.Rectangle, index: usize, height: f32) rl.Rectangle {
    return .{
        .x = bounds.x,
        .y = bounds.y + @as(f32, @floatFromInt(index)) * height,
        .width = bounds.width,
        .height = height,
    };
}

pub fn inset(r: rl.Rectangle, by: f32) rl.Rectangle {
    return .{ .x = r.x + by, .y = r.y + by, .width = r.width - by * 2, .height = r.height - by * 2 };
}

pub fn cutTop(r: *rl.Rectangle, h: f32) rl.Rectangle {
    const out = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.width, .height = @min(h, r.height) };
    r.y += out.height;
    r.height -= out.height;
    return out;
}

pub fn cutBottom(r: *rl.Rectangle, h: f32) rl.Rectangle {
    const hh = @min(h, r.height);
    r.height -= hh;
    return .{ .x = r.x, .y = r.y + r.height, .width = r.width, .height = hh };
}

pub fn cutLeft(r: *rl.Rectangle, w: f32) rl.Rectangle {
    const ww = @min(w, r.width);
    const out = rl.Rectangle{ .x = r.x, .y = r.y, .width = ww, .height = r.height };
    r.x += ww;
    r.width -= ww;
    return out;
}

pub fn cutRight(r: *rl.Rectangle, w: f32) rl.Rectangle {
    const ww = @min(w, r.width);
    r.width -= ww;
    return .{ .x = r.x + r.width, .y = r.y, .width = ww, .height = r.height };
}

pub fn separator(t: Theme, x: f32, y: f32, w: f32) void {
    rl.drawLineEx(.{ .x = x, .y = y }, .{ .x = x + w, .y = y }, 1.0, t.separator);
}

pub fn frame(r: rl.Rectangle, roundness: f32, fill: rl.Color, border: rl.Color) void {
    if (r.width <= 0 or r.height <= 0) return;
    rl.drawRectangleRounded(r, roundness, 6, border);
    const inner = inset(r, 1);
    if (inner.width > 0 and inner.height > 0 and fill.a > 0) {
        rl.drawRectangleRounded(inner, roundness, 6, fill);
    }
}

pub fn hovered(r: rl.Rectangle) bool {
    return rl.checkCollisionPointRec(rl.getMousePosition(), r);
}

pub fn clicked(r: rl.Rectangle) bool {
    return hovered(r) and rl.isMouseButtonPressed(.left);
}

pub fn rightClicked(r: rl.Rectangle) bool {
    return hovered(r) and rl.isMouseButtonPressed(.right);
}

pub fn tri(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, color: rl.Color) void {
    rl.drawTriangle(a, b, c, color);
    rl.drawTriangle(a, c, b, color);
}

pub fn quad(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, d: rl.Vector2, color: rl.Color) void {
    tri(a, b, c, color);
    tri(a, c, d, color);
}

pub const Style = enum { normal, primary, danger, ghost };

pub fn button(t: Theme, r: rl.Rectangle, label: [:0]const u8, style: Style) bool {
    return buttonEx(t, r, label, style, true);
}

pub fn buttonEx(t: Theme, r: rl.Rectangle, label: [:0]const u8, style: Style, enabled: bool) bool {
    const over = enabled and hovered(r);
    const down = over and rl.isMouseButtonDown(.left);

    var fill = switch (style) {
        .normal => t.panel_alt,
        .primary => t.accent_dim,
        .danger => rl.Color{ .r = 90, .g = 40, .b = 40, .a = 255 },
        .ghost => rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };
    var line = switch (style) {
        .primary => t.accent,
        .danger => t.bad,
        else => t.border,
    };
    var fg = if (style == .primary) t.text_bright else t.text;

    if (!enabled) {
        fill = t.panel;
        line = t.border;
        fg = t.text_dim;
    } else if (down) {
        fill = t.accent;
        fg = t.bg;
        line = t.accent;
    } else if (over) {
        fill = if (style == .ghost) t.panel_alt else t.accent_dim;
        fg = t.text_bright;
        line = t.accent;
    }

    frame(r, t.radius, fill, line);

    const size = t.font_size;
    text(r.x + (r.width - measure(label, size)) / 2, r.y + (r.height - @as(f32, @floatFromInt(size))) / 2, size, fg, label);

    return enabled and over and rl.isMouseButtonReleased(.left);
}

pub fn toggle(t: Theme, r: rl.Rectangle, label: [:0]const u8, on: bool) bool {
    return button(t, r, label, if (on) .primary else .normal);
}

pub fn checkBox(t: Theme, r: rl.Rectangle, label: [:0]const u8, value: *bool) bool {
    const box_size = @min(r.height - 4, 16);
    const box = rl.Rectangle{
        .x = r.x,
        .y = r.y + (r.height - box_size) / 2,
        .width = box_size,
        .height = box_size,
    };
    const over = hovered(r);

    frame(box, 0.2, if (value.*) t.accent else t.panel_alt, if (over) t.accent else t.border);
    if (value.*) {
        rl.drawLineEx(
            .{ .x = box.x + 4, .y = box.y + box_size / 2 },
            .{ .x = box.x + box_size * 0.44, .y = box.y + box_size - 5 },
            2,
            t.bg,
        );
        rl.drawLineEx(
            .{ .x = box.x + box_size * 0.44, .y = box.y + box_size - 5 },
            .{ .x = box.x + box_size - 4, .y = box.y + 4 },
            2,
            t.bg,
        );
    }

    textIn(.{ .x = box.x + box_size + 6, .y = r.y, .width = r.width, .height = r.height }, 0, t.small_font, if (over) t.text_bright else t.text, label);

    if (over and rl.isMouseButtonReleased(.left)) {
        value.* = !value.*;
        return true;
    }
    return false;
}

pub fn selector(t: Theme, r: rl.Rectangle, label: [:0]const u8, index: *usize, count: usize) bool {
    if (count == 0) {
        frame(r, t.radius, t.panel, t.border);
        textIn(r, 8, t.small_font, t.text_dim, label);
        return false;
    }

    const arrow_w = @min(r.height, 22);
    var body = r;
    const left = cutLeft(&body, arrow_w);
    const right = cutRight(&body, arrow_w);

    frame(r, t.radius, t.panel_alt, if (hovered(r)) t.accent else t.border);

    var changed = false;
    const can_prev = count > 1;

    const lcol = if (hovered(left) and can_prev) t.accent else t.text_dim;
    const rcol = if (hovered(right) and can_prev) t.accent else t.text_dim;
    arrowGlyph(left, -1, lcol);
    arrowGlyph(right, 1, rcol);

    var buf: [96]u8 = undefined;
    textClipped(
        body.x + (body.width - @min(body.width, measure(label, t.small_font))) / 2,
        body.y + (body.height - t.smallF()) / 2,
        body.width,
        t.small_font,
        t.text,
        label,
        &buf,
    );

    if (can_prev and clicked(left)) {
        index.* = if (index.* == 0) count - 1 else index.* - 1;
        changed = true;
    }
    if (can_prev and clicked(right)) {
        index.* = (index.* + 1) % count;
        changed = true;
    }
    return changed;
}

fn arrowGlyph(r: rl.Rectangle, dir: f32, color: rl.Color) void {
    const cx = r.x + r.width / 2;
    const cy = r.y + r.height / 2;
    const w: f32 = 4;
    const h: f32 = 6;
    tri(
        .{ .x = cx + dir * w * 0.5, .y = cy },
        .{ .x = cx - dir * w * 0.5, .y = cy - h * 0.5 },
        .{ .x = cx - dir * w * 0.5, .y = cy + h * 0.5 },
        color,
    );
}

pub fn stepper(t: Theme, r: rl.Rectangle, value: *i32, min: i32, max: i32, step: i32, suffix: []const u8) bool {
    var body = r;
    const minus = cutLeft(&body, @min(r.height, 24));
    const plus = cutRight(&body, @min(r.height, 24));

    frame(r, t.radius, t.panel_alt, if (hovered(r)) t.accent else t.border);

    textCentered(minus.x + minus.width / 2, minus.y + (minus.height - t.smallF()) / 2, t.small_font, if (hovered(minus)) t.accent else t.text_dim, "-");
    textCentered(plus.x + plus.width / 2, plus.y + (plus.height - t.smallF()) / 2, t.small_font, if (hovered(plus)) t.accent else t.text_dim, "+");

    var buf: [48]u8 = undefined;
    const label = zBuf(&buf, "{d}{s}", .{ value.*, suffix });
    textCentered(body.x + body.width / 2, body.y + (body.height - t.smallF()) / 2, t.small_font, t.text, label);

    var changed = false;
    if (clicked(minus)) {
        value.* = @max(min, value.* - step);
        changed = true;
    }
    if (clicked(plus)) {
        value.* = @min(max, value.* + step);
        changed = true;
    }
    return changed;
}

pub fn stat(t: Theme, r: rl.Rectangle, key: [:0]const u8, value: [:0]const u8, value_color: rl.Color) void {
    const y = r.y + (r.height - t.smallF()) / 2;
    text(r.x, y, t.small_font, t.text_dim, key);
    textRight(r.x + r.width, y, t.small_font, value_color, value);
}

pub fn badge(t: Theme, x: f32, y: f32, label: [:0]const u8, fg: rl.Color, bg: rl.Color) f32 {
    const w = measure(label, t.small_font) + 12;
    const h = t.smallF() + 6;
    rl.drawRectangleRounded(.{ .x = x, .y = y, .width = w, .height = h }, 0.4, 6, bg);
    text(x + 6, y + 3, t.small_font, fg, label);
    return w + 5;
}

pub fn progress(t: Theme, r: rl.Rectangle, frac: f32, color: rl.Color) void {
    rl.drawRectangleRounded(r, 0.5, 4, t.panel_alt);
    const f = std.math.clamp(frac, 0, 1);
    if (f <= 0) return;
    rl.drawRectangleRounded(
        .{ .x = r.x, .y = r.y, .width = @max(r.height, r.width * f), .height = r.height },
        0.5,
        4,
        color,
    );
}

pub const Scroll = struct {
    offset: f32 = 0.0,
    speed: f32 = 40.0,

    pub fn handle(self: *Scroll, view: rl.Rectangle, content_height: f32) void {
        if (hovered(view)) {
            self.offset -= rl.getMouseWheelMove() * self.speed;
        }
        const max_offset = @max(0.0, content_height - view.height);
        self.offset = std.math.clamp(self.offset, 0.0, max_offset);
    }

    pub fn drawBar(self: *const Scroll, t: Theme, view: rl.Rectangle, content_height: f32) void {
        if (content_height <= view.height) return;

        const frac = view.height / content_height;
        const bar_h = @max(24, view.height * frac);
        const max_off = content_height - view.height;
        const p = if (max_off > 0) self.offset / max_off else 0.0;

        rl.drawRectangleRec(.{
            .x = view.x + view.width - 4,
            .y = view.y + p * (view.height - bar_h),
            .width = 3,
            .height = bar_h,
        }, t.border);
    }

    pub fn revealRow(self: *Scroll, view: rl.Rectangle, y_local: f32, row_h: f32) void {
        if (y_local < self.offset) {
            self.offset = y_local;
        } else if (y_local + row_h > self.offset + view.height) {
            self.offset = y_local + row_h - view.height;
        }
    }

    pub fn toBottom(self: *Scroll, view: rl.Rectangle, content_height: f32) void {
        self.offset = @max(0.0, content_height - view.height);
    }
};

pub const TextInput = struct {
    pub const capacity = 256;

    buf: [capacity + 1]u8 = undefined,
    len: usize = 0,
    cursor: usize = 0,
    focused: bool = false,
    scroll: f32 = 0,
    repeat_timer: f32 = 0,
    enabled: bool = true,

    pub fn init(initial: []const u8) TextInput {
        var t = TextInput{};
        t.set(initial);
        return t;
    }

    pub fn set(self: *TextInput, s: []const u8) void {
        const n = @min(s.len, capacity);
        @memcpy(self.buf[0..n], s[0..n]);
        self.buf[n] = 0;
        self.len = n;
        self.cursor = n;
    }

    pub fn slice(self: *const TextInput) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn zStr(self: *TextInput) [:0]const u8 {
        self.buf[self.len] = 0;
        return self.buf[0..self.len :0];
    }

    pub fn clear(self: *TextInput) void {
        self.len = 0;
        self.cursor = 0;
        self.buf[0] = 0;
    }

    fn insert(self: *TextInput, c: u8) void {
        if (self.len >= capacity) return;
        var i = self.len;
        while (i > self.cursor) : (i -= 1) self.buf[i] = self.buf[i - 1];
        self.buf[self.cursor] = c;
        self.len += 1;
        self.cursor += 1;
        self.buf[self.len] = 0;
    }

    fn backspace(self: *TextInput) void {
        if (self.cursor == 0) return;
        var i = self.cursor - 1;
        while (i + 1 < self.len) : (i += 1) self.buf[i] = self.buf[i + 1];
        self.len -= 1;
        self.cursor -= 1;
        self.buf[self.len] = 0;
    }

    fn del(self: *TextInput) void {
        if (self.cursor >= self.len) return;
        var i = self.cursor;
        while (i + 1 < self.len) : (i += 1) self.buf[i] = self.buf[i + 1];
        self.len -= 1;
        self.buf[self.len] = 0;
    }

    fn paste(self: *TextInput) void {
        const clip = rl.getClipboardText();
        for (clip) |c| {
            if (c < 32 or c > 126) continue;
            self.insert(c);
        }
    }

    pub fn draw(self: *TextInput, t: Theme, r: rl.Rectangle, placeholder: [:0]const u8) bool {
        const over = hovered(r);

        if (self.enabled) {
            if (rl.isMouseButtonPressed(.left)) self.focused = over;
        } else {
            self.focused = false;
        }

        var submitted = false;
        if (self.focused) {
            while (true) {
                const c = rl.getCharPressed();
                if (c == 0) break;
                if (c >= 32 and c < 127) self.insert(@intCast(c));
            }

            const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control) or
                rl.isKeyDown(.left_super) or rl.isKeyDown(.right_super);

            if (ctrl and rl.isKeyPressed(.v)) self.paste();
            if (ctrl and rl.isKeyPressed(.a)) self.cursor = self.len;
            if (ctrl and rl.isKeyPressed(.c)) rl.setClipboardText(self.zStr());

            if (repeatKey(.backspace, &self.repeat_timer)) self.backspace();
            if (rl.isKeyPressed(.delete)) self.del();
            if (rl.isKeyPressed(.left) and self.cursor > 0) self.cursor -= 1;
            if (rl.isKeyPressed(.right) and self.cursor < self.len) self.cursor += 1;
            if (rl.isKeyPressed(.home)) self.cursor = 0;
            if (rl.isKeyPressed(.end)) self.cursor = self.len;
            if (rl.isKeyPressed(.escape)) self.focused = false;
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter)) {
                submitted = true;
                self.focused = false;
            }
        }

        frame(
            r,
            t.radius,
            if (self.enabled) t.panel_alt else t.panel,
            if (self.focused) t.accent else if (over) t.divider else t.border,
        );

        const pad: f32 = 7;
        const inner_w = r.width - pad * 2;
        const y = r.y + (r.height - t.smallF()) / 2;

        self.buf[self.len] = 0;
        const value: [:0]const u8 = self.buf[0..self.len :0];

        if (self.len == 0 and !self.focused) {
            text(r.x + pad, y, t.small_font, t.text_dim, placeholder);
            return submitted;
        }

        var head_buf: [capacity + 1]u8 = undefined;
        const head = zSlice(&head_buf, self.buf[0..self.cursor]);
        const caret_x = measure(head, t.small_font);
        if (caret_x - self.scroll > inner_w - 6) self.scroll = caret_x - inner_w + 6;
        if (caret_x - self.scroll < 0) self.scroll = caret_x;
        const total = measure(value, t.small_font);
        if (total - self.scroll < inner_w and self.scroll > 0) self.scroll = @max(0, total - inner_w);

        rl.beginScissorMode(
            @intFromFloat(r.x + pad - 1),
            @intFromFloat(r.y),
            @intFromFloat(@max(inner_w + 2, 0)),
            @intFromFloat(r.height),
        );
        text(r.x + pad - self.scroll, y, t.small_font, t.text, value);
        if (self.focused and @mod(@as(f32, @floatCast(rl.getTime())), 1.0) < 0.6) {
            const cx = r.x + pad + caret_x - self.scroll;
            rl.drawLineEx(.{ .x = cx, .y = r.y + 4 }, .{ .x = cx, .y = r.y + r.height - 4 }, 1, t.accent);
        }
        rl.endScissorMode();

        return submitted;
    }
};

fn repeatKey(key: rl.KeyboardKey, timer: *f32) bool {
    if (rl.isKeyPressed(key)) {
        timer.* = 0.45;
        return true;
    }
    if (rl.isKeyDown(key)) {
        timer.* -= rl.getFrameTime();
        if (timer.* <= 0) {
            timer.* = 0.04;
            return true;
        }
    }
    return false;
}

pub var keyboard_captured: bool = false;
