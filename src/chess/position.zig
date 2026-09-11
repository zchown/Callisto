const std = @import("std");
const root = @import("root.zig");
const utils = root.utils;
const zob = root.zobrist;

pub const GameResult = enum {
    WhiteWin,
    BlackWin,
    Draw,
    Ongoing,
};

pub const CastleValues = enum(u4) {
    NoCastling = 0,
    WhiteKingside = 1,
    WhiteQueenside = 2,
    AllWhite = 3,
    BlackKingside = 4,
    BlackQueenside = 8,
    AllBlack = 12,
    AllCastling = 15,
};

pub const CastleRights = u4;

pub inline fn removeCastleRights(cr: CastleRights, cv: CastleValues) CastleRights {
    return cr & ~@intFromEnum(cv);
}

pub inline fn hasCastleRight(cr: CastleRights, cv: CastleValues) bool {
    return (cr & @intFromEnum(cv)) != 0;
}

pub inline fn colorCastleRights(c: Color) CastleValues {
    return if (c == .White) .AllWhite else .AllBlack;
}

pub const Square = u6;

pub inline fn squareFromFileRank(file: u3, rank: u3) Square {
    return (@as(Square, rank) * 8) + @as(Square, file);
}

pub const Bitboard = u64;

pub const Pieces = enum(u3) {
    Pawn = 0,
    Knight = 1,
    Bishop = 2,
    Rook = 3,
    Queen = 4,
    King = 5,
    None = 6,

    pub inline fn isNone(self: Pieces) bool {
        return self == .None;
    }

    pub inline fn idx(self: Pieces) usize {
        return @intFromEnum(self);
    }
};

pub const Color = enum(u1) {
    White = 0,
    Black = 1,

    pub inline fn oposite(self: Color) Color {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }

    pub inline fn idx(self: Color) usize {
        return @intFromEnum(self);
    }
};

pub const Piece = packed struct(u4) {
    piece: Pieces,
    color: Color,

    pub const none: Piece = .{ .piece = .None, .color = .White };

    pub fn fromChar(c: u8) ?Piece {
        const color: Color = if (c >= 'A' and c <= 'Z') .White else .Black;
        const piece: Pieces = switch (std.ascii.toLower(c)) {
            'p' => .Pawn,
            'n' => .Knight,
            'b' => .Bishop,
            'r' => .Rook,
            'q' => .Queen,
            'k' => .King,
            else => return null,
        };
        return .{ .piece = piece, .color = color };
    }

    pub fn toChar(self: Piece) u8 {
        const c: u8 = switch (self.piece) {
            .Pawn => 'p',
            .Knight => 'n',
            .Bishop => 'b',
            .Rook => 'r',
            .Queen => 'q',
            .King => 'k',
            .None => return '.',
        };
        return if (self.color == .White) std.ascii.toUpper(c) else c;
    }

    pub inline fn isNone(self: Piece) bool {
        return self.piece == .None;
    }
};

pub const Move = packed struct(u16) {
    pub const PFlags = enum(u2) {
        Knight = 0,
        Bishop = 1,
        Rook = 2,
        Queen = 3,
    };
    pub const QNFlags = enum(u2) {
        NQM = 0, // normal quiet move
        DPP = 1, // double pawn push
        QSC = 2, // queen side castle
        KSC = 3, // king side castle
    };
    pub const CNFlags = enum(u2) {
        NCM = 0, // normal capture move
        EP = 1, // en passant
    };

    from: Square,
    to: Square,

    cap: u1,
    promo: u1,
    flags: u2,


    pub inline fn quiet(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(QNFlags.NQM) };
    }

    pub inline fn doublePush(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(QNFlags.DPP) };
    }

    pub inline fn castle(from: Square, to: Square, kingside: bool) Move {
        const f: QNFlags = if (kingside) .KSC else .QSC;
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(f) };
    }

    pub inline fn capture(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 0, .flags = @intFromEnum(CNFlags.NCM) };
    }

    pub inline fn enPassant(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 0, .flags = @intFromEnum(CNFlags.EP) };
    }

    pub inline fn promotion(from: Square, to: Square, p: PFlags) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 1, .flags = @intFromEnum(p) };
    }

    pub inline fn promoCapture(from: Square, to: Square, p: PFlags) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 1, .flags = @intFromEnum(p) };
    }

    pub inline fn isCapture(self: Move) bool {
        return self.cap != 0;
    }

    pub inline fn isPromo(self: Move) bool {
        return self.promo != 0;
    }

    pub inline fn isCastle(self: Move) bool {
        return self.cap == 0 and self.promo == 0 and (self.flags >> 1) == 1;
    }

    pub inline fn isKingsideCastle(self: Move) bool {
        return self.isCastle() and self.flags == @intFromEnum(QNFlags.KSC);
    }

    pub inline fn isEP(self: Move) bool {
        return self.cap == 1 and self.promo == 0 and self.flags == @intFromEnum(CNFlags.EP);
    }

    pub inline fn isDoublePP(self: Move) bool {
        return self.cap == 0 and self.promo == 0 and self.flags == @intFromEnum(QNFlags.DPP);
    }

    pub inline fn isQuiet(self: Move) bool {
        return self.cap == 0 and self.promo == 0;
    }

    pub inline fn promoPiece(self: Move) Pieces {
        return @enumFromInt(@as(u3, self.flags) + 1);
    }

    pub fn toUci(self: Move, buf: []u8) []const u8 {
        _ = utils.squareToString(self.from, buf[0..2]);
        _ = utils.squareToString(self.to, buf[2..4]);
        if (self.isPromo()) {
            buf[4] = switch (self.promoPiece()) {
                .Knight => 'n',
                .Bishop => 'b',
                .Rook => 'r',
                else => 'q',
            };
            return buf[0..5];
        }
        return buf[0..4];
    }

    pub fn toSAN(self: Move, buf: []u8) []const u8 {
        _ = utils.squareToString(self.from, buf[0..2]);
        _ = utils.squareToString(self.to, buf[2..4]);
        if (self.isPromo()) {
            buf[4] = switch (self.promoPiece()) {
                .Knight => 'n',
                .Bishop => 'b',
                .Rook => 'r',
                else => 'q',
            };
            return buf[0..5];
        }
        return buf[0..4];
    }

    pub fn fromSAN(san: []const u8) ?Move {
        if (san.len < 4) return null;
        const from = utils.squareFromString(san[0..2]) orelse return null;
        const to = utils.squareFromString(san[2..4]) orelse return null;
        if (san.len == 4) {
            return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(QNFlags.NQM) };
        } else if (san.len == 5) {
            const promo_piece = switch (san[4]) {
                'n' => PFlags.Knight,
                'b' => PFlags.Bishop,
                'r' => PFlags.Rook,
                'q' => PFlags.Queen,
                else => return null,
            };
            return .{ .from = from, .to = to, .cap = 0, .promo = 1, .flags = @intFromEnum(promo_piece) };
        }
        return null;
    }

    pub inline fn eql(self: Move, other: Move) bool {
        return @as(u16, @bitCast(self)) == @as(u16, @bitCast(other));
    }
};

pub const UndoInfo = struct {
    captured: Piece,
    castle: CastleRights,
    ep_sq: ?Square,
    halfmove: u8,
};

pub const GameState = struct {
    history: [256]UndoInfo,
    cur_position: Position,
    ply: usize,
    to_move: Color,

    // Starting rook files, so castling works for both standard chess and 960.
    white_ks_rook_file: u3,
    white_qs_rook_file: u3,
    black_ks_rook_file: u3,
    black_qs_rook_file: u3,

    pub fn init() GameState {
        return .{
            .history = std.mem.zeroes([256]UndoInfo),
            .cur_position = Position.init(),
            .ply = 0,
            .to_move = .White,
            .white_ks_rook_file = 7,
            .white_qs_rook_file = 0,
            .black_ks_rook_file = 7,
            .black_qs_rook_file = 0,
        };
    }

    pub fn copyFrom(self: *GameState, other: *const GameState) void {
        self.cur_position = other.cur_position;
        self.ply = other.ply;
        self.to_move = other.to_move;
        self.white_ks_rook_file = other.white_ks_rook_file;
        self.white_qs_rook_file = other.white_qs_rook_file;
        self.black_ks_rook_file = other.black_ks_rook_file;
        self.black_qs_rook_file = other.black_qs_rook_file;

        for (0..self.ply) |i| {
            self.history[i] = other.history[i];
        }
    }

    pub inline fn halfmoveClock(self: GameState) u8 {
        return self.cur_position.halfmove;
    }

    pub inline fn rookSquare(self: GameState, color: Color, kingside: bool) Square {
        const rank_base: Square = if (color == .White) 0 else 56;
        const file: u3 = if (color == .White)
            (if (kingside) self.white_ks_rook_file else self.white_qs_rook_file)
        else
            (if (kingside) self.black_ks_rook_file else self.black_qs_rook_file);
        return rank_base + @as(Square, file);
    }

    pub inline fn rookCastleDest(color: Color, kingside: bool) Square {
        const rank_base: Square = if (color == .White) 0 else 56;
        return rank_base + 3 + (2 * @as(Square, @intFromBool(kingside)));
    }

    pub inline fn kingCastleDest(color: Color, kingside: bool) Square {
        const rank_base: Square = if (color == .White) 0 else 56;
        return rank_base + (if (kingside) @as(Square, 6) else @as(Square, 2));
    }

    pub fn makeMove(self: *GameState, m: Move) !void {
        const p = &self.cur_position;

        self.history[self.ply] = .{
            .captured = if (m.isEP()) Piece{ .piece = .Pawn, .color = self.to_move.oposite() } else p.getFromSquare(m.to),
            .castle = p.castle,
            .ep_sq = p.ep_sq,
            .halfmove = p.halfmove,
        };

        self.ply += 1;

        const us = self.to_move;
        const them = us.oposite();
        defer self.to_move = them;

        const moved = p.getFromSquare(m.from);
        const captured = p.getFromSquare(m.to);

        if (moved.piece == .Pawn or m.isCapture()) {
            p.halfmove = 0;
        } else {
            p.halfmove +|= 1;
        }

        var cr = p.castle;
        if (moved.piece == .King) {
            cr = removeCastleRights(cr, colorCastleRights(us));
        } else if (moved.piece == .Rook) {
            cr = self.clearRookRight(cr, us, m.from);
        }
        if (captured.piece == .Rook and !m.isEP()) {
            cr = self.clearRookRight(cr, them, m.to);
        }

        if (m.isCastle()) {
            const kingside = m.isKingsideCastle();
            const rook_from = self.rookSquare(us, kingside);
            const rook_to = rookCastleDest(us, kingside);

            p.removePiece(m.from);
            p.removePiece(rook_from);
            p.addPiece(us, .King, m.to);
            p.addPiece(us, .Rook, rook_to);

            cr = removeCastleRights(cr, colorCastleRights(us));
            p.setEpSquare(null);
        } else if (m.isEP()) {
            const cap_square: Square = if (us == .White) m.to - 8 else m.to + 8;
            p.removePiece(m.from);
            p.removePiece(cap_square);
            p.addPiece(us, .Pawn, m.to);
            p.setEpSquare(null);
        } else if (m.isPromo()) {
            p.removePiece(m.from);
            p.addPiece(us, m.promoPiece(), m.to);
            p.setEpSquare(null);
        } else if (m.isDoublePP()) {
            p.removePiece(m.from);
            p.addPiece(us, .Pawn, m.to);

            const enemy_pawns = p.getPieceColorBoard(.Pawn, them);
            const adjacent = utils.getSquareBB(m.to);
            const enemy_adjacent =
                ((adjacent & utils.not_a_file) >> 1 | (adjacent & utils.not_h_file) << 1) & enemy_pawns;

            if (enemy_adjacent != 0) {
                p.setEpSquare(if (us == .White) m.to - 8 else m.to + 8);
            } else {
                p.setEpSquare(null);
            }
        } else {
            p.removePiece(m.from);
            p.addPiece(us, moved.piece, m.to);
            p.setEpSquare(null);
        }

        if (cr != p.castle) p.setCastleRights(cr);
        p.hash ^= zob.zobrist.sideKeys(us) ^ zob.zobrist.sideKeys(them);
    }

    pub fn unmakeMove(self: *GameState, m: Move) void {
        self.ply -= 1;
        self.to_move = self.to_move.oposite();
        const us = self.to_move;
        const undo = self.history[self.ply];
        const p = &self.cur_position;

        if (m.isCastle()) {
        const kingside = m.isKingsideCastle();
        const rook_from = self.rookSquare(us, kingside); 

        const king_to = kingCastleDest(us, kingside);
        const rook_to = rookCastleDest(us, kingside);

        p.removePiece(king_to);
        p.removePiece(rook_to);

        p.addPiece(us, .King, m.from);
        p.addPiece(us, .Rook, rook_from);
        } else if (m.isEP()) {
            const cap_square: Square = if (us == .White) m.to - 8 else m.to + 8;
            p.removePiece(m.to);
            p.addPiece(us, .Pawn, m.from);
            p.addPiece(us.oposite(), .Pawn, cap_square);
        } else if (m.isPromo()) {
            p.removePiece(m.to);

            p.addPiece(us, .Pawn, m.from);
            if (undo.captured.piece != .None) {
                p.addPiece(us.oposite(), undo.captured.piece, m.to);
            }
        } else {
            const piece_moved = p.getPieceFromSquare(m.to);
            p.removePiece(m.to);
            p.addPiece(us, piece_moved, m.from);
            if (undo.captured.piece != .None) {
                p.addPiece(us.oposite(), undo.captured.piece, m.to);
            }
        }

        p.setCastleRights(undo.castle);
        p.setEpSquare(undo.ep_sq);
        p.halfmove = undo.halfmove;
        p.hash ^= zob.zobrist.sideKeys(us) ^ zob.zobrist.sideKeys(us.oposite());
    }

    fn clearRookRight(self: GameState, cr: CastleRights, c: Color, sq: Square) CastleRights {
        if (sq == self.rookSquare(c, true)) {
            return removeCastleRights(cr, if (c == .White) .WhiteKingside else .BlackKingside);
        } else if (sq == self.rookSquare(c, false)) {
            return removeCastleRights(cr, if (c == .White) .WhiteQueenside else .BlackQueenside);
        }
        return cr;
    }
};

pub const Position = struct {
    mailbox: [utils.num_squares]Piece,
    piece_bb: [utils.num_pieces]Bitboard,
    color_bb: [utils.num_colors]Bitboard,
    castle: CastleRights,
    hash: zob.ZobristKey,
    ep_sq: ?Square,
    halfmove: u8,

    pub fn init() Position {
        return .{
            .mailbox = [_]Piece{Piece.none} ** utils.num_squares,
            .piece_bb = [_]Bitboard{0} ** utils.num_pieces,
            .color_bb = [_]Bitboard{0} ** utils.num_colors,
            .hash = 0,
            .castle = 0,
            .ep_sq = null,
            .halfmove = 0,
        };
    }

    pub inline fn getOccupancy(self: Position) Bitboard {
        return self.color_bb[0] | self.color_bb[1];
    }

    pub inline fn getColorBoard(self: Position, c: Color) Bitboard {
        return self.color_bb[c.idx()];
    }

    pub inline fn getPieceBoard(self: Position, p: Pieces) Bitboard {
        if (p != .None) return self.piece_bb[p.idx()];
        return ~self.getOccupancy();
    }

    pub inline fn getPieceColorBoard(self: Position, p: Pieces, c: Color) Bitboard {
        if (p != .None) return self.piece_bb[p.idx()] & self.color_bb[c.idx()];
        return ~self.getOccupancy();
    }

    pub inline fn diagonalSliders(self: Position, c: Color) Bitboard {
        return (self.piece_bb[Pieces.Bishop.idx()] | self.piece_bb[Pieces.Queen.idx()]) &
            self.color_bb[c.idx()];
    }

    pub inline fn straightSliders(self: Position, c: Color) Bitboard {
        return (self.piece_bb[Pieces.Rook.idx()] | self.piece_bb[Pieces.Queen.idx()]) &
            self.color_bb[c.idx()];
    }

    pub inline fn kingSquare(self: Position, c: Color) Square {
        return utils.lsb(self.getPieceColorBoard(.King, c));
    }

    pub inline fn getFromSquare(self: Position, sq: Square) Piece {
        return self.mailbox[sq];
    }

    pub inline fn getPieceFromSquare(self: Position, sq: Square) Pieces {
        return self.mailbox[sq].piece;
    }

    pub inline fn getColorFromSquare(self: Position, sq: Square) Color {
        return self.mailbox[sq].color;
    }

    inline fn setBB(self: *Position, c: Color, p: Pieces, sq_bb: Bitboard) void {
        self.piece_bb[p.idx()] |= sq_bb;
        self.color_bb[c.idx()] |= sq_bb;
    }

    inline fn clearBB(self: *Position, c: Color, p: Pieces, sq_bb: Bitboard) void {
        self.piece_bb[p.idx()] &= ~sq_bb;
        self.color_bb[c.idx()] &= ~sq_bb;
    }

    pub fn addPiece(self: *Position, c: Color, p: Pieces, sq: Square) void {
        const cur_piece = self.mailbox[sq];
        const sq_bb = utils.getSquareBB(sq);

        if (!cur_piece.isNone()) {
            self.hash ^= zob.zobrist.pieceKeys(cur_piece.color, cur_piece.piece, sq);
            self.clearBB(cur_piece.color, cur_piece.piece, sq_bb);
        }

        self.setBB(c, p, sq_bb);
        self.mailbox[sq] = .{ .piece = p, .color = c };
        self.hash ^= zob.zobrist.pieceKeys(c, p, sq);
    }

    pub fn removePiece(self: *Position, sq: Square) void {
        const cur_piece = self.mailbox[sq];
        if (!cur_piece.isNone()) {
            self.hash ^= zob.zobrist.pieceKeys(cur_piece.color, cur_piece.piece, sq);
            self.clearBB(cur_piece.color, cur_piece.piece, utils.getSquareBB(sq));
        }
        self.mailbox[sq] = Piece.none;
    }

    pub fn setCastleRights(self: *Position, c: CastleRights) void {
        self.hash ^= zob.zobrist.castleKeys(self.castle);
        self.castle = c;
        self.hash ^= zob.zobrist.castleKeys(c);
    }

    pub fn setEpSquare(self: *Position, ep: ?Square) void {
        // zobrist handles the null case for us
        self.hash ^= zob.zobrist.enPassantKeys(self.ep_sq);
        self.ep_sq = ep;
        self.hash ^= zob.zobrist.enPassantKeys(ep);
    }

    pub fn getPieceList(self: *const Position, allocator: std.mem.Allocator) !std.ArrayList(Piece) {
        var list = try std.ArrayList(Piece).initCapacity(allocator, 32);
        for (0..utils.num_squares) |i| {
            if (!self.mailbox[i].isNone()) {
                try list.append(allocator, self.mailbox[i]);
            }
        }
        return list;
    }

    pub fn reinintZobrist(self: *Position, to_move: Color) void {
        var hash: zob.ZobristKey = 0;
        hash ^= zob.zobrist.castleKeys(self.castle);
        hash ^= zob.zobrist.enPassantKeys(self.ep_sq);
        hash ^= zob.zobrist.sideKeys(to_move);

        for (0..utils.num_squares) |i| {
            if (!self.mailbox[i].isNone()) {
                const p = self.mailbox[i];
                hash ^= zob.zobrist.pieceKeys(p.color, p.piece, @intCast(i));
            }
        }

        self.hash = hash;
    }

    pub fn isConsistent(self: Position) bool {
        var occ: Bitboard = 0;
        for (0..utils.num_squares) |i| {
            const sq: Square = @intCast(i);
            const pc = self.mailbox[i];
            if (pc.isNone()) {
                if (utils.getBit(self.getOccupancy(), sq)) return false;
                continue;
            }
            occ |= utils.getSquareBB(sq);
            if (!utils.getBit(self.piece_bb[pc.piece.idx()], sq)) return false;
            if (!utils.getBit(self.color_bb[pc.color.idx()], sq)) return false;
        }
        if (occ != self.getOccupancy()) return false;
        if ((self.color_bb[0] & self.color_bb[1]) != 0) return false;
        return true;
    }
};
