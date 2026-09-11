const std = @import("std");

pub const max_lines = 512;
pub const max_line = 768;
pub const max_path = 1024;

pub const Process = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,

    path_buf: [max_path]u8 = undefined,
    path_len: usize = 0,
    argv_storage: [1][]const u8 = undefined,

    stdin_file: std.fs.File = undefined,
    stdout_file: std.fs.File = undefined,
    stdin_open: bool = false,
    stdout_open: bool = false,

    thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},

    lines: [max_lines][max_line]u8 = undefined,
    lens: [max_lines]u16 = undefined,
    head: usize = 0,
    tail: usize = 0,
    dropped: u64 = 0,

    eof: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    write_failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    reaped: bool = false,

    pub fn spawn(allocator: std.mem.Allocator, path: []const u8) !*Process {
        if (path.len == 0 or path.len >= max_path) return error.BadEnginePath;

        const self = try allocator.create(Process);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .child = undefined,
        };

        @memcpy(self.path_buf[0..path.len], path);
        self.path_len = path.len;
        const stored = self.path_buf[0..self.path_len];

        self.argv_storage[0] = stored;
        self.child = std.process.Child.init(self.argv_storage[0..1], allocator);
        self.child.stdin_behavior = .Pipe;
        self.child.stdout_behavior = .Pipe;
        self.child.stderr_behavior = .Ignore;

        if (std.fs.path.dirname(stored)) |dir| {
            if (dir.len > 0) self.child.cwd = dir;
        }

        try self.child.spawn();

        self.stdin_file = self.child.stdin.?;
        self.stdout_file = self.child.stdout.?;
        self.child.stdin = null;
        self.child.stdout = null;
        self.stdin_open = true;
        self.stdout_open = true;

        self.thread = std.Thread.spawn(.{}, readerMain, .{self}) catch |err| {
            self.hardStop();
            return err;
        };

        return self;
    }

    pub fn isAlive(self: *Process) bool {
        return !self.eof.load(.acquire);
    }

    pub fn writeFailed(self: *Process) bool {
        return self.write_failed.load(.acquire);
    }

    pub fn writeLine(self: *Process, line: []const u8) void {
        if (!self.stdin_open) return;
        var buf: [max_line + 2]u8 = undefined;
        const n = @min(line.len, max_line);
        @memcpy(buf[0..n], line[0..n]);
        buf[n] = '\n';
        self.stdin_file.writeAll(buf[0 .. n + 1]) catch {
            self.write_failed.store(true, .release);
        };
    }

    pub fn next(self: *Process, out: []u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tail == self.head) return null;
        const idx = self.tail;
        self.tail = (self.tail + 1) % max_lines;

        const len = @min(@as(usize, self.lens[idx]), out.len);
        @memcpy(out[0..len], self.lines[idx][0..len]);
        return out[0..len];
    }

    pub fn takeDropped(self: *Process) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        const d = self.dropped;
        self.dropped = 0;
        return d;
    }

    fn push(self: *Process, line: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next_head = (self.head + 1) % max_lines;
        if (next_head == self.tail) {
            self.tail = (self.tail + 1) % max_lines;
            self.dropped += 1;
        }

        const n = @min(line.len, max_line);
        @memcpy(self.lines[self.head][0..n], line[0..n]);
        self.lens[self.head] = @intCast(n);
        self.head = next_head;
    }

    fn readerMain(self: *Process) void {
        var chunk: [4096]u8 = undefined;
        var pending: [max_line]u8 = undefined;
        var pending_len: usize = 0;

        while (true) {
            const n = self.stdout_file.read(&chunk) catch break;
            if (n == 0) break;

            for (chunk[0..n]) |c| {
                switch (c) {
                    '\n' => {
                        self.push(pending[0..pending_len]);
                        pending_len = 0;
                    },
                    '\r' => {},
                    else => {
                        if (pending_len < max_line) {
                            pending[pending_len] = c;
                            pending_len += 1;
                        }
                    },
                }
            }
        }

        if (pending_len > 0) self.push(pending[0..pending_len]);
        self.eof.store(true, .release);
    }

    fn closeStdin(self: *Process) void {
        if (self.stdin_open) {
            self.stdin_file.close();
            self.stdin_open = false;
        }
    }

    fn hardStop(self: *Process) void {
        self.closeStdin();
        if (!self.reaped) {
            _ = self.child.kill() catch {};
            self.reaped = true;
        }
        if (self.stdout_open) {
            self.stdout_file.close();
            self.stdout_open = false;
        }
    }

    pub fn destroy(self: *Process) void {
        const allocator = self.allocator;

        if (self.stdin_open) {
            self.writeLine("quit");
            self.closeStdin();
        }

        var waited_ms: u32 = 0;
        while (waited_ms < 400 and !self.eof.load(.acquire)) : (waited_ms += 20) {
            std.Thread.sleep(20 * std.time.ns_per_ms);
        }

        if (!self.reaped) {
            if (self.eof.load(.acquire)) {
                _ = self.child.wait() catch {};
            } else {
                _ = self.child.kill() catch {};
            }
            self.reaped = true;
        }

        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }

        if (self.stdout_open) {
            self.stdout_file.close();
            self.stdout_open = false;
        }

        allocator.destroy(self);
    }
};
