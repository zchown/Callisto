const std = @import("std");

pub const max_entries = 400;
pub const max_text = 200;
pub const max_tag = 20;

pub const Dir = enum {
    in,
    out,
    note,
    err,
};

pub const Entry = struct {
    tag: [max_tag]u8 = undefined,
    tag_len: u8 = 0,
    text: [max_text]u8 = undefined,
    text_len: u8 = 0,
    dir: Dir = .note,
    ms: i64 = 0,

    pub fn tagSlice(self: *const Entry) []const u8 {
        return self.tag[0..self.tag_len];
    }
    pub fn textSlice(self: *const Entry) []const u8 {
        return self.text[0..self.text_len];
    }
};

pub const Log = struct {
    entries: [max_entries]Entry = undefined,
    head: usize = 0,
    count: usize = 0,
    revision: u64 = 0,
    paused: bool = false,

    pub fn init(self: *Log) void {
        self.* = .{};
    }

    pub fn clear(self: *Log) void {
        self.head = 0;
        self.count = 0;
        self.revision +%= 1;
    }

    pub fn add(self: *Log, tag: []const u8, dir: Dir, text: []const u8) void {
        if (self.paused and dir != .err) return;

        const e = &self.entries[self.head];
        e.* = .{ .dir = dir, .ms = std.time.milliTimestamp() };

        const tn = @min(tag.len, max_tag);
        @memcpy(e.tag[0..tn], tag[0..tn]);
        e.tag_len = @intCast(tn);

        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        const xn = @min(trimmed.len, max_text);
        @memcpy(e.text[0..xn], trimmed[0..xn]);
        e.text_len = @intCast(xn);

        self.head = (self.head + 1) % max_entries;
        if (self.count < max_entries) self.count += 1;
        self.revision +%= 1;
    }

    pub fn print(self: *Log, tag: []const u8, dir: Dir, comptime fmt: []const u8, args: anytype) void {
        var buf: [max_text]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
        self.add(tag, dir, text);
    }

    pub fn at(self: *const Log, i: usize) ?*const Entry {
        if (i >= self.count) return null;
        const start = if (self.count < max_entries) 0 else self.head;
        return &self.entries[(start + i) % max_entries];
    }
};

test "log wraps and keeps order" {
    var log: Log = .{};
    var buf: [8]u8 = undefined;
    for (0..max_entries + 10) |i| {
        log.add("t", .note, std.fmt.bufPrint(&buf, "{d}", .{i}) catch "x");
    }
    try std.testing.expectEqual(max_entries, log.count);
    try std.testing.expectEqualStrings("10", log.at(0).?.textSlice());
}
