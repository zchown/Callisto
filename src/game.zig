const std = @import("std");
const chess = @import("chess");

const Move = chess.Move;
const GameState = chess.GameState;
const Position = chess.Position;
const Color = chess.Color;
const MoveList = chess.MoveList;

pub const max_plies = 1000;
pub const max_name = 48;

pub const Status = enum {
    ongoing,
    checkmate,
    stalemate,
    fifty_move,
    repetition,
    insufficient,
    too_long,

    pub fn isOver(self: Status) bool {
        return self != .ongoing;
    }

    pub fn label(self: Status) [:0]const u8 {
        return switch (self) {
            .ongoing => "in progress",
            .checkmate => "checkmate",
            .stalemate => "stalemate",
            .fifty_move => "draw by the fifty move rule",
            .repetition => "draw by repetition",
            .insufficient => "draw by insufficient material",
            .too_long => "draw (ply limit)",
        };
    }
};

pub const Ply = struct {
    move: Move = Move.quiet(0, 0),
    san: [chess.san.max_len]u8 = undefined,
    san_len: u8 = 0,
    hash: u64 = 0,
    halfmove: u8 = 0,
    eval_cp: i32 = 0,
    eval_mate: i32 = 0,
    has_eval: bool = false,
    eval_is_mate: bool = false,
    time_ms: u32 = 0,

    pub fn sanSlice(self: *const Ply) []const u8 {
        return self.san[0..self.san_len];
    }
};

pub const Game = struct {
    root: GameState = undefined,
    live: GameState = undefined,

    root_fen: [128]u8 = undefined,
    root_fen_len: usize = 0,

    plies: [max_plies]Ply = undefined,
    moves: [max_plies]Move = undefined,
    count: usize = 0,
    cursor: usize = 0,

    white_name: [max_name]u8 = undefined,
    white_name_len: usize = 0,
    black_name: [max_name]u8 = undefined,
    black_name_len: usize = 0,

    result: chess.GameResult = .Ongoing,
    termination: [64]u8 = undefined,
    termination_len: usize = 0,

    preview: Position = undefined,
    preview_active: bool = false,
    preview_move: ?Move = null,

    revision: u64 = 0,

    pub fn init(self: *Game) void {
        self.* = .{};
        self.setStart() catch {};
        self.setNames("White", "Black");
    }

    pub fn setStart(self: *Game) !void {
        try self.setFen(chess.start_position);
    }

    pub fn setFen(self: *Game, fen_text: []const u8) !void {
        const trimmed = std.mem.trim(u8, fen_text, " \t\r\n");
        const gs = try chess.fen.parseFEN(trimmed);

        self.root = gs;
        self.live = gs;
        self.count = 0;
        self.cursor = 0;
        self.result = .Ongoing;
        self.termination_len = 0;
        self.preview_active = false;
        self.preview_move = null;
        self.revision +%= 1;

        const n = @min(trimmed.len, self.root_fen.len);
        @memcpy(self.root_fen[0..n], trimmed[0..n]);
        self.root_fen_len = n;
    }

    pub fn setNames(self: *Game, white: []const u8, black: []const u8) void {
        const wn = @min(white.len, max_name);
        @memcpy(self.white_name[0..wn], white[0..wn]);
        self.white_name_len = wn;
        const bn = @min(black.len, max_name);
        @memcpy(self.black_name[0..bn], black[0..bn]);
        self.black_name_len = bn;
    }

    pub fn whiteName(self: *const Game) []const u8 {
        return self.white_name[0..self.white_name_len];
    }
    pub fn blackName(self: *const Game) []const u8 {
        return self.black_name[0..self.black_name_len];
    }

    pub fn setTermination(self: *Game, text: []const u8) void {
        const n = @min(text.len, self.termination.len);
        @memcpy(self.termination[0..n], text[0..n]);
        self.termination_len = n;
    }

    pub fn terminationSlice(self: *const Game) []const u8 {
        return self.termination[0..self.termination_len];
    }

    pub fn rootFen(self: *const Game) ?[]const u8 {
        if (self.root_fen_len == 0) return null;
        return self.root_fen[0..self.root_fen_len];
    }

    pub fn state(self: *Game) *GameState {
        return &self.live;
    }

    pub fn displayState(self: *Game) *const GameState {
        return &self.live;
    }

    pub fn position(self: *const Game) *const Position {
        return &self.live.cur_position;
    }

    pub fn boardPosition(self: *const Game) *const Position {
        if (self.preview_active) return &self.preview;
        return &self.live.cur_position;
    }

    pub fn sideToMove(self: *const Game) Color {
        return self.live.to_move;
    }

    pub fn movesToCursor(self: *const Game) []const Move {
        return self.moves[0..self.cursor];
    }

    pub fn atEnd(self: *const Game) bool {
        return self.cursor == self.count;
    }

    pub fn atStart(self: *const Game) bool {
        return self.cursor == 0;
    }

    pub fn lastMove(self: *const Game) ?Move {
        if (self.preview_active) return self.preview_move;
        if (self.cursor == 0) return null;
        return self.moves[self.cursor - 1];
    }

    pub fn plyAt(self: *const Game, i: usize) ?*const Ply {
        if (i >= self.count) return null;
        return &self.plies[i];
    }

    pub fn moveNumber(self: *const Game, i: usize) usize {
        const base = self.root.ply + i;
        return (base + 1) / 2;
    }

    pub fn firstIsBlack(self: *const Game) bool {
        return self.root.to_move == .Black;
    }

    pub fn legal(self: *Game, list: *MoveList) void {
        chess.movegen.generateLegal(&self.live, list) catch {
            list.clear();
        };
    }

    pub fn findMove(self: *Game, from: chess.Square, to: chess.Square, promo: ?chess.Pieces) ?Move {
        var list = MoveList.empty;
        self.legal(&list);
        var fallback: ?Move = null;
        for (list.slice()) |m| {
            if (m.from != from or m.to != to) continue;
            if (m.isPromo()) {
                if (promo) |p| {
                    if (m.promoPiece() == p) return m;
                    continue;
                }
                fallback = m;
                continue;
            }
            return m;
        }
        return fallback;
    }

    pub fn needsPromotion(self: *Game, from: chess.Square, to: chess.Square) bool {
        var list = MoveList.empty;
        self.legal(&list);
        for (list.slice()) |m| {
            if (m.from == from and m.to == to and m.isPromo()) return true;
        }
        return false;
    }

    pub fn play(self: *Game, m: Move) !void {
        if (self.cursor >= max_plies - 1) return error.TooManyPlies;
        if (self.live.ply + 2 >= self.live.history.len) return error.HistoryFull;

        self.count = self.cursor;

        var ply = Ply{ .move = m };
        var buf: [chess.san.max_len]u8 = undefined;
        const san = chess.san.toSan(&self.live, m, &buf) catch "??";
        const n: u8 = @intCast(@min(san.len, ply.san.len));
        @memcpy(ply.san[0..n], san[0..n]);
        ply.san_len = n;

        try self.live.makeMove(m);

        ply.hash = self.live.cur_position.hash;
        ply.halfmove = self.live.cur_position.halfmove;

        self.plies[self.count] = ply;
        self.moves[self.count] = m;
        self.count += 1;
        self.cursor = self.count;
        self.clearPreview();
        self.revision +%= 1;
    }

    pub fn playUci(self: *Game, text: []const u8) !bool {
        const m = (chess.san.fromUci(&self.live, text) catch null) orelse return false;
        try self.play(m);
        return true;
    }

    pub fn goto(self: *Game, target: usize) void {
        const want = @min(target, self.count);
        while (self.cursor > want) {
            self.cursor -= 1;
            self.live.unmakeMove(self.moves[self.cursor]);
        }
        while (self.cursor < want) {
            self.live.makeMove(self.moves[self.cursor]) catch break;
            self.cursor += 1;
        }
        self.clearPreview();
        self.revision +%= 1;
    }

    pub fn back(self: *Game) void {
        if (self.preview_active) {
            self.clearPreview();
            return;
        }
        if (self.cursor > 0) self.goto(self.cursor - 1);
    }

    pub fn forward(self: *Game) void {
        if (self.cursor < self.count) self.goto(self.cursor + 1);
    }

    pub fn toStart(self: *Game) void {
        self.goto(0);
    }

    pub fn toEnd(self: *Game) void {
        self.goto(self.count);
    }

    pub fn truncate(self: *Game) void {
        self.count = self.cursor;
        self.revision +%= 1;
    }

    pub fn setPreview(self: *Game, pv: []const u8, max_moves: usize) void {
        var scratch = self.live;
        var it = std.mem.tokenizeAny(u8, pv, " \t");
        var n: usize = 0;
        var last: ?Move = null;

        while (it.next()) |tok| {
            if (n >= max_moves) break;
            if (scratch.ply + 2 >= scratch.history.len) break;
            const m = (chess.san.fromUci(&scratch, tok) catch null) orelse break;
            scratch.makeMove(m) catch break;
            last = m;
            n += 1;
        }

        if (n == 0) {
            self.clearPreview();
            return;
        }
        self.preview = scratch.cur_position;
        self.preview_move = last;
        self.preview_active = true;
    }

    pub fn clearPreview(self: *Game) void {
        self.preview_active = false;
        self.preview_move = null;
    }

    pub fn playLine(self: *Game, pv: []const u8, max_moves: usize) void {
        self.clearPreview();
        var it = std.mem.tokenizeAny(u8, pv, " \t");
        var n: usize = 0;
        while (it.next()) |tok| {
            if (n >= max_moves) break;
            const ok = self.playUci(tok) catch false;
            if (!ok) break;
            n += 1;
        }
    }

    pub fn repetitionCount(self: *const Game) usize {
        const hash = self.live.cur_position.hash;
        var n: usize = 0;
        if (self.root.cur_position.hash == hash) n += 1;
        for (self.plies[0..self.cursor]) |p| {
            if (p.hash == hash) n += 1;
        }
        return n;
    }

    pub fn inCheck(self: *const Game) bool {
        return chess.attacks.isInCheck(&self.live.cur_position, self.live.to_move);
    }

    pub fn status(self: *Game) Status {
        var list = MoveList.empty;
        self.legal(&list);

        if (list.len == 0) {
            return if (self.inCheck()) .checkmate else .stalemate;
        }
        if (self.live.cur_position.halfmove >= 100) return .fifty_move;
        if (self.repetitionCount() >= 3) return .repetition;
        if (insufficientMaterial(&self.live.cur_position)) return .insufficient;
        if (self.count >= max_plies - 2) return .too_long;
        return .ongoing;
    }

    pub fn resultFor(self: *Game, st: Status) chess.GameResult {
        return switch (st) {
            .checkmate => if (self.live.to_move == .White) .BlackWin else .WhiteWin,
            .ongoing => .Ongoing,
            else => .Draw,
        };
    }

    pub fn uciMoveText(self: *const Game, buf: []u8) []const u8 {
        var len: usize = 0;
        var mb: [8]u8 = undefined;
        for (self.moves[0..self.cursor]) |m| {
            const t = m.toUci(&mb);
            if (len + t.len + 1 > buf.len) break;
            if (len > 0) {
                buf[len] = ' ';
                len += 1;
            }
            @memcpy(buf[len..][0..t.len], t);
            len += t.len;
        }
        return buf[0..len];
    }

    pub fn currentFen(self: *const Game, allocator: std.mem.Allocator) ![]u8 {
        return chess.fen.toFen(allocator, self.live);
    }
};

pub fn insufficientMaterial(p: *const Position) bool {
    const occ = p.getOccupancy();
    if (@popCount(occ) > 4) return false;

    if (p.getPieceBoard(.Pawn) != 0) return false;
    if (p.getPieceBoard(.Rook) != 0) return false;
    if (p.getPieceBoard(.Queen) != 0) return false;

    const knights = p.getPieceBoard(.Knight);
    const bishops = p.getPieceBoard(.Bishop);
    const minors = @popCount(knights) + @popCount(bishops);

    if (minors == 0) return true; // bare kings
    if (minors == 1) return true; // K+minor vs K

    if (minors == 2 and knights == 0) {
        const light = bishops & chess.utils.light_squares;
        const dark = bishops & chess.utils.dark_squares;
        if (light == 0 or dark == 0) {
            const w = bishops & p.getColorBoard(.White);
            const b = bishops & p.getColorBoard(.Black);
            return w != 0 and b != 0;
        }
    }
    return false;
}
