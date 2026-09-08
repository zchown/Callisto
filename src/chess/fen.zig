const std = @import("std");
const root = @import("root.zig");
const utils = root.utils;
const pos = root.pos;

pub fn parseFEN(fen: []const u8) !pos.GameState {
    var it = std.mem.tokenizeAny(u8, fen, " ");
    var gs = pos.GameState.init();

    const piece_placement = it.next() orelse return error.MissingPiecePlacement;
    try parsePiecePlacement(&gs, piece_placement);

    const side_to_move = it.next() orelse return error.MissingSideToMove;
    if (side_to_move.len != 1) return error.InvalidSideToMove;
    gs.to_move = switch (side_to_move[0]) {
        'w' => pos.Color.White,
        'b' => pos.Color.Black,
        else => return error.InvalidSideToMove,
    };

    const castling_rights = it.next() orelse return error.MissingCastlingRights;
    try parseCastlingRights(&gs, castling_rights);

    const en_passant_square = it.next() orelse return error.MissingEnPassantSquare;
    try parseEnPassant(&gs, en_passant_square);

    const halfmove_clock = it.next() orelse "0";
    gs.cur_position.halfmove = std.fmt.parseInt(u8, halfmove_clock, 10) catch
        return error.InvalidHalfmoveClock;

    const fullmove_number = it.next() orelse "1";
    const fullmove = std.fmt.parseInt(usize, fullmove_number, 10) catch
        return error.InvalidFullmoveNumber;
    if (fullmove == 0) return error.InvalidFullmoveNumber;

    gs.ply = fullmove * 2;
    if (gs.to_move == .White) gs.ply -= 1;

    gs.cur_position.reinintZobrist(gs.to_move);
    return gs;
}

pub fn toFen(a: std.mem.Allocator, gs: pos.GameState) ![]u8 {
    var fen = try std.ArrayList(u8).initCapacity(a, 96);
    errdefer fen.deinit(a);

    var rank_idx: usize = utils.num_ranks;
    while (rank_idx > 0) {
        rank_idx -= 1;
        var empty_count: u8 = 0;

        for (0..utils.num_files) |file| {
            const square = pos.squareFromFileRank(@intCast(file), @intCast(rank_idx));
            const piece = gs.cur_position.getFromSquare(square);

            if (piece.isNone()) {
                empty_count += 1;
                continue;
            }
            if (empty_count > 0) {
                try fen.append(a, '0' + empty_count);
                empty_count = 0;
            }
            try fen.append(a, piece.toChar());
        }

        if (empty_count > 0) try fen.append(a, '0' + empty_count);
        if (rank_idx > 0) try fen.append(a, '/');
    }

    try fen.append(a, ' ');
    try fen.append(a, if (gs.to_move == .White) 'w' else 'b');
    try fen.append(a, ' ');

    const castle = gs.cur_position.castle;
    var has_castling_rights = false;
    if (pos.hasCastleRight(castle, .WhiteKingside)) {
        try fen.append(a, 'K');
        has_castling_rights = true;
    }
    if (pos.hasCastleRight(castle, .WhiteQueenside)) {
        try fen.append(a, 'Q');
        has_castling_rights = true;
    }
    if (pos.hasCastleRight(castle, .BlackKingside)) {
        try fen.append(a, 'k');
        has_castling_rights = true;
    }
    if (pos.hasCastleRight(castle, .BlackQueenside)) {
        try fen.append(a, 'q');
        has_castling_rights = true;
    }
    if (!has_castling_rights) try fen.append(a, '-');
    try fen.append(a, ' ');

    if (gs.cur_position.ep_sq) |ep_square| {
        var buf: [2]u8 = undefined;
        try fen.appendSlice(a, utils.squareToString(ep_square, &buf));
    } else {
        try fen.append(a, '-');
    }
    try fen.append(a, ' ');

    var num_buf: [24]u8 = undefined;
    const halfmove_str = try std.fmt.bufPrint(&num_buf, "{d}", .{gs.cur_position.halfmove});
    try fen.appendSlice(a, halfmove_str);
    try fen.append(a, ' ');

    const fullmove_number = (gs.ply + @intFromBool(gs.to_move == .White)) / 2;
    var num_buf2: [24]u8 = undefined;
    const fullmove_str = try std.fmt.bufPrint(&num_buf2, "{d}", .{fullmove_number});
    try fen.appendSlice(a, fullmove_str);

    return try fen.toOwnedSlice(a);
}

fn parsePiecePlacement(gs: *pos.GameState, piece_placement: []const u8) !void {
    var rank: usize = 7;
    var file: usize = 0;

    for (piece_placement) |c| {
        switch (c) {
            '/' => {
                if (file != 8) return error.IncompleteRank;
                if (rank == 0) return error.TooManyRanks;
                rank -= 1;
                file = 0;
            },
            '1'...'8' => {
                file += c - '0';
                if (file > 8) return error.TooManyFiles;
            },
            'P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k' => {
                if (file >= 8) return error.TooManyFiles;
                const piece = pos.Piece.fromChar(c) orelse return error.InvalidPiece;
                const square = pos.squareFromFileRank(@intCast(file), @intCast(rank));
                gs.cur_position.addPiece(piece.color, piece.piece, square);
                file += 1;
            },
            else => return error.InvalidCharacter,
        }
    }
    if (rank != 0 or file != 8) return error.IncompleteBoard;
}

fn parseCastlingRights(gs: *pos.GameState, castling_rights: []const u8) !void {
    gs.cur_position.castle = 0;
    if (std.mem.eql(u8, castling_rights, "-")) return;

    for (castling_rights) |c| {
        switch (c) {
            'K' => {
                gs.white_ks_rook_file = try findOuterRookFile(gs.cur_position, .White, true);
                gs.cur_position.castle |= @intFromEnum(pos.CastleValues.WhiteKingside);
            },
            'Q' => {
                gs.white_qs_rook_file = try findOuterRookFile(gs.cur_position, .White, false);
                gs.cur_position.castle |= @intFromEnum(pos.CastleValues.WhiteQueenside);
            },
            'k' => {
                gs.black_ks_rook_file = try findOuterRookFile(gs.cur_position, .Black, true);
                gs.cur_position.castle |= @intFromEnum(pos.CastleValues.BlackKingside);
            },
            'q' => {
                gs.black_qs_rook_file = try findOuterRookFile(gs.cur_position, .Black, false);
                gs.cur_position.castle |= @intFromEnum(pos.CastleValues.BlackQueenside);
            },
            'A'...'H' => {
                const rook_file: u3 = @intCast(c - 'A');
                const king_file = try getKingFile(gs.cur_position, .White);
                if (rook_file > king_file) {
                    gs.white_ks_rook_file = rook_file;
                    gs.cur_position.castle |= @intFromEnum(pos.CastleValues.WhiteKingside);
                } else {
                    gs.white_qs_rook_file = rook_file;
                    gs.cur_position.castle |= @intFromEnum(pos.CastleValues.WhiteQueenside);
                }
            },
            'a'...'h' => {
                const rook_file: u3 = @intCast(c - 'a');
                const king_file = try getKingFile(gs.cur_position, .Black);
                if (rook_file > king_file) {
                    gs.black_ks_rook_file = rook_file;
                    gs.cur_position.castle |= @intFromEnum(pos.CastleValues.BlackKingside);
                } else {
                    gs.black_qs_rook_file = rook_file;
                    gs.cur_position.castle |= @intFromEnum(pos.CastleValues.BlackQueenside);
                }
            },
            else => return error.InvalidCastlingCharacter,
        }
    }
}

fn getKingFile(position: pos.Position, color: pos.Color) !u3 {
    const king_bb = position.getPieceColorBoard(.King, color);
    if (king_bb == 0) return error.MissingKing;
    return utils.fileOf(utils.lsb(king_bb));
}

fn findOuterRookFile(position: pos.Position, color: pos.Color, kingside: bool) !u3 {
    const king_file = try getKingFile(position, color);
    const rooks = position.getPieceColorBoard(.Rook, color) & utils.backRankBB(color);
    if (rooks == 0) return error.MissingRookForCastling;

    if (kingside) {
        const file = utils.fileOf(utils.msb(rooks));
        if (file <= king_file) return error.MissingRookForCastling;
        return file;
    } else {
        const file = utils.fileOf(utils.lsb(rooks));
        if (file >= king_file) return error.MissingRookForCastling;
        return file;
    }
}

fn parseEnPassant(gs: *pos.GameState, en_passant_square: []const u8) !void {
    if (std.mem.eql(u8, en_passant_square, "-")) {
        gs.cur_position.setEpSquare(null);
        return;
    }

    if (en_passant_square.len != 2) return error.InvalidEnPassantSquare;

    const expected_rank: u8 = if (gs.to_move == .White) '6' else '3';
    if (en_passant_square[1] != expected_rank) return error.InvalidEnPassantSquare;

    const square = utils.squareFromString(en_passant_square) orelse
        return error.InvalidEnPassantSquare;
    gs.cur_position.setEpSquare(square);
}
