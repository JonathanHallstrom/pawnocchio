// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const root = @import("root.zig");

const Board = root.Board;
const Bitboard = root.Bitboard;
const CastlingRights = root.CastlingRights;
const Colour = root.Colour;
const ColouredPieceType = root.ColouredPieceType;
const Move = root.Move;
const PieceType = root.PieceType;
const Square = root.Square;
const LeanBoard = @This();

bbs: [8]u64 = @splat(0),
mailbox: [64]u8 = @splat(Board.MAILBOX_EMPTY),
halfmove: u8 = 0,
fullmove: u32 = 1,
plies: u32 = 0,
ep_target: ?Square = null,
stm: Colour = .white,
hash: u64 = 0,
castling_rights: CastlingRights = CastlingRights.init(),
frc: bool = false,

pub fn fromBoard(board: *const Board) LeanBoard {
    return .{
        .bbs = board.bbs,
        .mailbox = board.mailbox,
        .halfmove = board.halfmove,
        .fullmove = board.fullmove,
        .plies = board.plies,
        .ep_target = board.ep_target,
        .stm = board.stm,
        .hash = board.hash,
        .castling_rights = board.castling_rights,
        .frc = board.frc,
    };
}

pub fn toBoard(self: *const LeanBoard) Board {
    var res: Board = .{
        .bbs = self.bbs,
        .mailbox = self.mailbox,
        .halfmove = self.halfmove,
        .fullmove = self.fullmove,
        .plies = self.plies,
        .ep_target = self.ep_target,
        .stm = self.stm,
        .hash = self.hash,
        .castling_rights = self.castling_rights,
        .frc = self.frc,
    };
    res.recomputeAll();
    return res;
}

pub inline fn white(self: *const LeanBoard) u64 {
    return self.bbs[6];
}

pub inline fn black(self: *const LeanBoard) u64 {
    return self.bbs[7];
}

pub inline fn occupancy(self: *const LeanBoard) u64 {
    return self.white() | self.black();
}

pub inline fn occupancyFor(self: *const LeanBoard, col: Colour) u64 {
    return self.bbs[6 + col.toInt()];
}

pub inline fn pieceFor(self: *const LeanBoard, col: Colour, pt: PieceType) u64 {
    return self.bbs[pt.toInt()] & self.occupancyFor(col);
}

pub inline fn kingFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .king);
}

pub inline fn pawnsFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .pawn);
}

pub inline fn knightsFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .knight);
}

pub inline fn bishopsFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .bishop);
}

pub inline fn rooksFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .rook);
}

pub inline fn queensFor(self: *const LeanBoard, col: Colour) u64 {
    return self.pieceFor(col, .queen);
}

pub inline fn pawns(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.pawn.toInt()];
}

pub inline fn knights(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.knight.toInt()];
}

pub inline fn bishops(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.bishop.toInt()];
}

pub inline fn rooks(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.rook.toInt()];
}

pub inline fn queens(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.queen.toInt()];
}

pub inline fn kings(self: *const LeanBoard) u64 {
    return self.bbs[PieceType.king.toInt()];
}

pub inline fn pieceBB(self: *const LeanBoard, piece: PieceType) u64 {
    return self.bbs[piece.toInt()];
}

pub inline fn pieceBBs(self: *const LeanBoard) *const [6]u64 {
    return @ptrCast(&self.bbs);
}

pub inline fn colouredPieceOnUnchecked(self: *const LeanBoard, sq: Square) ColouredPieceType {
    return ColouredPieceType.fromInt(self.mailbox[sq.toInt()]);
}

pub inline fn colouredPieceOn(self: *const LeanBoard, sq: Square) ?ColouredPieceType {
    const raw = self.mailbox[sq.toInt()];
    return if (raw == Board.MAILBOX_EMPTY) null else ColouredPieceType.fromInt(raw);
}

pub inline fn pieceOn(self: *const LeanBoard, sq: Square) ?PieceType {
    const raw = self.mailbox[sq.toInt()];
    return if (raw == Board.MAILBOX_EMPTY) null else PieceType.fromInt(raw >> 1);
}

pub fn classicalMaterial(self: *const LeanBoard) u8 {
    return self.sumPieces([_]u8{ 1, 3, 3, 5, 9, 0 });
}

pub fn sumPieces(self: *const LeanBoard, weights: [6]u8) u8 {
    var res: u8 = 0;
    for (PieceType.all) |pt| {
        res += @as(u8, @intCast(@popCount(self.bbs[pt.toInt()]))) * weights[pt.toInt()];
    }
    return res;
}

pub inline fn addPiece(self: *LeanBoard, col: Colour, pt: PieceType, sq: Square) void {
    const bb = sq.toBitboard();
    self.bbs[6 + col.toInt()] |= bb;
    self.bbs[pt.toInt()] |= bb;
    self.hash ^= root.zobrist.piece(col, pt, sq);
    self.mailbox[sq.toInt()] = ColouredPieceType.fromPieceType(pt, col).toInt();
}

pub inline fn removePiece(self: *LeanBoard, col: Colour, pt: PieceType, sq: Square) void {
    const bb = sq.toBitboard();
    self.bbs[6 + col.toInt()] ^= bb;
    self.bbs[pt.toInt()] ^= bb;
    self.hash ^= root.zobrist.piece(col, pt, sq);
    self.mailbox[sq.toInt()] = Board.MAILBOX_EMPTY;
}

pub inline fn isCapture(self: *const LeanBoard, move: Move) bool {
    if (move.tp() == .ep) {
        return true;
    }
    return move.tp() != .castling and self.pieceOn(move.to()) != null;
}

pub inline fn isPromo(_: *const LeanBoard, move: Move) bool {
    return move.tp() == .promotion;
}

pub inline fn isNoisy(self: *const LeanBoard, move: Move) bool {
    if (self.isCapture(move)) {
        return true;
    }
    return move.promoTypeEquals(.queen);
}

pub fn isInCheck(self: *const LeanBoard) bool {
    return Board.computeAuxMasks(self).checkers != 0;
}

pub fn givesCheck(self: *const LeanBoard, move: Move) bool {
    const masks = Board.computeAuxMasks(self);
    return Board.computeGivesCheck(self, &masks, move);
}

pub fn toFen(self: *const LeanBoard) root.BoundedArray(u8, 128) {
    return Board.computeFen(self);
}

pub fn parseSANMove(self: *const LeanBoard, san_move: []const u8) ?Move {
    return Board.parseSANMove(self, san_move);
}

pub fn parseFen(fen: []const u8, permissive: bool) !LeanBoard {
    return Board.parseFenAs(LeanBoard, fen, permissive);
}

pub fn makeMove(self: *LeanBoard, move: Move) void {
    switch (self.stm) {
        inline else => |stm| Board.makeMoveCommon(self, stm, move, root.evaluation.noHandle()),
    }
}

pub fn recomputeAll(self: *LeanBoard) void {
    self.resetHash();
}

pub fn resetHash(self: *LeanBoard) void {
    self.hash = 0;
    self.updateEPHash();
    self.updateCastlingHash();
    if (self.stm == .black) {
        self.updateTurnHash();
    }
    for (PieceType.all) |pt| {
        inline for (.{ Colour.white, Colour.black }) |col| {
            var iter = Bitboard.iterator(self.pieceFor(col, pt));
            while (iter.next()) |sq| {
                self.hash ^= root.zobrist.piece(col, pt, sq);
            }
        }
    }
}

pub inline fn updateCastlingHash(self: *LeanBoard) void {
    self.hash ^= root.zobrist.castling(self.castling_rights.rawCastlingAvailability());
}

pub inline fn updateEPHash(self: *LeanBoard) void {
    if (self.ep_target) |target|
        self.hash ^= root.zobrist.ep(target);
}

pub inline fn updateTurnHash(self: *LeanBoard) void {
    self.hash ^= root.zobrist.turn();
}
