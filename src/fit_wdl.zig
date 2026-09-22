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

const std = @import("std");
const root = @import("root.zig");
const dataformat = root.dataformat;
const FileFormat = dataformat.FileFormat;
const fastmath = root.fastmath;

const FIT_INPUTS: root.wdl.Inputs = .material;
const FIT_DEGREE = 3;

const FitModel = root.wdl.Model(FIT_INPUTS, FIT_DEGREE);
const PARAMETER_COUNT = 2 * FitModel.COEFFICIENT_COUNT;
const INITIAL_STEP = 16.0;
const MIN_STEP = 1e-3;
const MAX_EVALUATIONS = 5_000;
const RELATIVE_TOLERANCE = 1e-9;

const EVAL_BIN_WIDTH = 8;
const REGULARIZATION = 1e-6;
const PROBABILITY_FLOOR = 1e-6;
const UNROLL = root.simd.vecSize(f32);

const MATERIAL_MIN: u8 = if (FIT_INPUTS == .eval_only) 0 else 17;
const MATERIAL_MAX: u8 = if (FIT_INPUTS == .eval_only) 0 else 78;
const FULLMOVE_MIN: u32 = if (FIT_INPUTS == .material_fullmove) 1 else 0;
const FULLMOVE_MAX: u32 = if (FIT_INPUTS == .material_fullmove) 120 else 0;
const MATERIAL_COUNT = MATERIAL_MAX - MATERIAL_MIN + 1;
const FULLMOVE_COUNT = FULLMOVE_MAX - FULLMOVE_MIN + 1;
const GROUP_COUNT = MATERIAL_COUNT * FULLMOVE_COUNT;
const OUTCOME_COUNT = 3;

pub const Options = struct {
    inputs: []const []const u8,
    format: ?FileFormat,
    max_eval: u16,
};

const Group = struct {
    material: f32,
    fullmove: f32,
    start: usize,
    end: usize,
};

const Histogram = struct {
    groups: []Group,
    evals: []f32,
    counts: [OUTCOME_COUNT][]f32,
    occupied_cells: usize,

    fn deinit(self: *const Histogram, allocator: std.mem.Allocator) void {
        allocator.free(self.groups);
        allocator.free(self.evals);
        for (self.counts) |counts| allocator.free(counts);
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, options: Options) !void {
    const eval_count: usize = 2 * @as(usize, options.max_eval) + 1;
    const dense = try allocator.alloc([OUTCOME_COUNT]u32, GROUP_COUNT * eval_count);
    defer allocator.free(dense);
    @memset(dense, @splat(0));

    const positions = try parseInputs(io, allocator, options, dense, eval_count);
    if (positions == 0) {
        std.debug.print("fit-wdl: no positions with usable evaluations within --max-eval {}\n", .{options.max_eval});
        return error.NoUsablePositions;
    }

    const histogram = try packHistogram(allocator, dense, eval_count, options.max_eval);
    defer histogram.deinit(allocator);

    var fitted = initialParameters();
    const baseline = objective(&histogram, &fitted, positions);
    std.debug.assert(std.math.isFinite(baseline));
    const fitted_objective = minimize(&histogram, positions, &fitted, baseline);

    std.debug.print("fit-wdl: {} positions, {} cells, inputs={s}, degree={}, params={}\n", .{
        positions, histogram.occupied_cells, @tagName(FIT_INPUTS), FIT_DEGREE, PARAMETER_COUNT,
    });
    std.debug.print("baseline nll/position = {d:.8}\nfitted nll/position = {d:.8}\n", .{ baseline, fitted_objective });
    const a = fitted[0..FitModel.COEFFICIENT_COUNT];
    const b = fitted[FitModel.COEFFICIENT_COUNT..];
    std.debug.print("const INPUTS: Inputs = .{s};\nconst DEGREE = {};\n", .{ @tagName(FIT_INPUTS), FIT_DEGREE });
    printZigCoefficients("A_COEFFICIENTS", a);
    printZigCoefficients("B_COEFFICIENTS", b);
    if (FIT_INPUTS != .eval_only)
        std.debug.print("const double m = std::clamp(double(material), 17.0, 78.0) / 58.0;\n", .{});
    if (FIT_INPUTS == .material_fullmove)
        std.debug.print("const double f = std::clamp(double(fullmove), 1.0, 120.0) / 32.0;\n", .{});
    printCppCoefficients("a", a);
    printCppCoefficients("b", b);
}

const ParseContext = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    options: Options,
    dense: [][OUTCOME_COUNT]u32,
    eval_count: usize,
};

fn parseInputs(
    io: std.Io,
    allocator: std.mem.Allocator,
    options: Options,
    dense: [][OUTCOME_COUNT]u32,
    eval_count: usize,
) !u64 {
    const context: ParseContext = .{
        .io = io,
        .allocator = allocator,
        .options = options,
        .dense = dense,
        .eval_count = eval_count,
    };
    const results = try allocator.alloc(anyerror!u64, options.inputs.len);
    defer allocator.free(results);

    var group: std.Io.Group = .init;
    for (options.inputs, results) |path, *result| group.async(io, readFileTask, .{ &context, path, result });
    try group.await(io);

    var positions: u64 = 0;
    for (options.inputs, results) |path, result| {
        positions += result catch |e| {
            std.debug.print("reading file '{s}' gave: '{}'\n", .{ path, e });
            return e;
        };
    }
    return positions;
}

fn readFileTask(context: *const ParseContext, path: []const u8, result: *anyerror!u64) void {
    result.* = readFile(context, path);
}

fn readFile(context: *const ParseContext, path: []const u8) !u64 {
    const io = context.io;
    const format = context.options.format orelse FileFormat.fromPath(path) orelse return error.UnknownFileFormat;
    const buffer = try context.allocator.alloc(u8, 1 << 20);
    defer context.allocator.free(buffer);
    const file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.openFileAbsolute(io, path, .{})
    else
        try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var file_reader = file.readerStreaming(io, buffer);
    const max_eval: i32 = context.options.max_eval;
    var positions: u64 = 0;
    switch (format) {
        inline else => |comptime_format| {
            var reader = dataformat.readerFor(comptime_format, &file_reader.interface, context.allocator);
            defer reader.deinit();
            while (try reader.next()) |game| {
                const outcome: usize = @intFromEnum(game.outcome);
                var iterator = game.iter();
                while (try iterator.next()) |ply| {
                    const eval: i32 = ply.whiteEval() orelse continue;
                    if (root.evaluation.isMateScore(eval) or root.evaluation.isTBScore(eval)) continue;
                    if (@abs(eval) > max_eval) continue;
                    const binned = std.math.clamp(
                        @divFloor(2 * eval + EVAL_BIN_WIDTH, 2 * EVAL_BIN_WIDTH) * EVAL_BIN_WIDTH,
                        -max_eval,
                        max_eval,
                    );
                    const material = std.math.clamp(ply.board.classicalMaterial(), MATERIAL_MIN, MATERIAL_MAX);
                    const fullmove = std.math.clamp(ply.board.fullmove, FULLMOVE_MIN, FULLMOVE_MAX);
                    const group_index = (material - MATERIAL_MIN) * FULLMOVE_COUNT + (fullmove - FULLMOVE_MIN);
                    const eval_index: usize = @intCast(binned + max_eval);
                    const cell_index = group_index * context.eval_count + eval_index;
                    _ = @atomicRmw(u32, &context.dense[cell_index][outcome], .Add, 1, .monotonic);
                    positions += 1;
                }
            }
        },
    }
    return positions;
}

fn packHistogram(
    allocator: std.mem.Allocator,
    dense: []const [OUTCOME_COUNT]u32,
    eval_count: usize,
    max_eval: u16,
) !Histogram {
    var groups: std.ArrayListUnmanaged(Group) = .empty;
    defer groups.deinit(allocator);
    var evals: std.ArrayListUnmanaged(f32) = .empty;
    defer evals.deinit(allocator);
    var counts: [OUTCOME_COUNT]std.ArrayListUnmanaged(f32) = @splat(.empty);
    defer for (&counts) |*list| list.deinit(allocator);

    var occupied_cells: usize = 0;
    for (0..GROUP_COUNT) |group_index| {
        const start = evals.items.len;
        for (0..eval_count) |eval_index| {
            const cell = dense[group_index * eval_count + eval_index];
            if (cell[0] | cell[1] | cell[2] == 0) continue;
            const eval = @as(i32, @intCast(eval_index)) - @as(i32, max_eval);
            try evals.append(allocator, @floatFromInt(eval));
            for (&counts, cell) |*list, count| try list.append(allocator, @floatFromInt(count));
        }
        if (evals.items.len == start) continue;
        occupied_cells += evals.items.len - start;
        while (evals.items.len % UNROLL != 0) {
            try evals.append(allocator, 0);
            for (&counts) |*list| try list.append(allocator, 0);
        }
        try groups.append(allocator, .{
            .material = @floatFromInt(group_index / FULLMOVE_COUNT + MATERIAL_MIN),
            .fullmove = @floatFromInt(group_index % FULLMOVE_COUNT + FULLMOVE_MIN),
            .start = start,
            .end = evals.items.len,
        });
    }

    var result: Histogram = .{
        .groups = try groups.toOwnedSlice(allocator),
        .evals = &.{},
        .counts = @splat(&.{}),
        .occupied_cells = occupied_cells,
    };
    errdefer result.deinit(allocator);
    result.evals = try evals.toOwnedSlice(allocator);
    for (&result.counts, &counts) |*owned, *list| owned.* = try list.toOwnedSlice(allocator);
    return result;
}

fn initialParameters() [PARAMETER_COUNT]f32 {
    var result: [PARAMETER_COUNT]f32 = @splat(0);
    result[0] = 300;
    result[FitModel.COEFFICIENT_COUNT] = 70;
    return result;
}

inline fn logLikelihood(
    eval: f32,
    loss_count: f32,
    draw_count: f32,
    win_count: f32,
    a: f32,
    b: f32,
) f32 {
    const u = (eval - a) / b;
    const v = (-eval - a) / b;
    const tu = fastmath.exp(-u);
    const tv = fastmath.exp(-v);
    const win = 1 / (1 + tu);
    const loss = 1 / (1 + tv);
    // avoid precision issues
    const draw = if (u >= v) tu * win - loss else tv * loss - win;
    const log_loss = fastmath.log(@max(loss, PROBABILITY_FLOOR));
    const log_draw = fastmath.log(@max(draw, PROBABILITY_FLOOR));
    const log_win = fastmath.log(@max(win, PROBABILITY_FLOOR));
    return loss_count * log_loss + draw_count * log_draw + win_count * log_win;
}

fn nll(histogram: *const Histogram, group: Group, a: f32, b: f32) f64 {
    // who cares if its a little bit off:p
    @setFloatMode(.optimized);
    const evals = histogram.evals[group.start..group.end];
    const losses = histogram.counts[0][group.start..group.end];
    const draws = histogram.counts[1][group.start..group.end];
    const wins = histogram.counts[2][group.start..group.end];
    var sum: f64 = 0;
    var i: usize = 0;

    while (i < evals.len) : (i += UNROLL) {
        var block: [UNROLL]f32 = undefined;
        inline for (0..UNROLL) |j| {
            block[j] = logLikelihood(evals[i + j], losses[i + j], draws[i + j], wins[i + j], a, b);
        }
        var block_sum: f32 = 0;
        for (block) |value| block_sum += value;
        sum += block_sum;
    }
    return -sum;
}

fn objective(
    histogram: *const Histogram,
    parameters: *const [PARAMETER_COUNT]f32,
    position_count: u64,
) f64 {
    const a_coefficients = parameters[0..FitModel.COEFFICIENT_COUNT];
    const b_coefficients = parameters[FitModel.COEFFICIENT_COUNT..];
    var sum: f64 = 0;
    for (histogram.groups) |group| {
        const a, const b = FitModel.params(a_coefficients, b_coefficients, group.material, group.fullmove);
        if (!std.math.isFinite(a) or !std.math.isFinite(b) or a <= 0 or b <= 0)
            return std.math.inf(f64);
        sum += nll(histogram, group, a, b);
    }

    var penalty: f64 = 0;
    for (a_coefficients[1..]) |a|
        penalty += a * a;
    for (b_coefficients[1..]) |b|
        penalty += b * b;
    return sum / @as(f64, @floatFromInt(position_count)) + penalty * REGULARIZATION;
}

fn minimize(
    histogram: *const Histogram,
    position_count: u64,
    parameters: *[PARAMETER_COUNT]f32,
    baseline: f64,
) f64 {
    var best = baseline;
    var step: f32 = INITIAL_STEP;
    var evaluations: usize = 0;
    while (step >= MIN_STEP and evaluations < MAX_EVALUATIONS) {
        const previous_best = best;
        for (0..PARAMETER_COUNT) |index| {
            const previous = parameters[index];
            for ([_]f32{ step, -step }) |delta| {
                evaluations += 1;
                parameters[index] = previous + delta;
                const candidate = objective(histogram, parameters, position_count);
                if (candidate < best) {
                    best = candidate;
                    break;
                }
                parameters[index] = previous;
            }
        }
        if (previous_best - best < RELATIVE_TOLERANCE * (@abs(best) + 1)) step *= 0.5;
    }
    return best;
}

fn printZigCoefficients(name: []const u8, coefficients: []const f32) void {
    std.debug.print("const {s}: EngineModel.Coefficients = .{{\n", .{name});
    for (coefficients) |coefficient| std.debug.print("    {d:.8},\n", .{coefficient});
    std.debug.print("}};\n", .{});
}

fn printCppCoefficients(name: []const u8, coefficients: []const f32) void {
    std.debug.print("constexpr double {s}s[] = {{", .{name});
    switch (FIT_INPUTS) {
        .eval_only, .material => {
            var remaining = coefficients.len;
            while (remaining > 0) {
                remaining -= 1;
                std.debug.print(" {d:.8}{s}", .{ coefficients[remaining], if (remaining == 0) "" else "," });
            }
            std.debug.print(" }};\nconst double {s} = ", .{name});
            for (0..coefficients.len -| 2) |_| std.debug.print("(", .{});
            std.debug.print("{s}s[0]", .{name});
            for (1..coefficients.len) |i| std.debug.print("{s} * m + {s}s[{}]", .{ if (i == 1) "" else ")", name, i });
        },
        .material_fullmove => {
            for (coefficients, 0..) |coefficient, i| {
                std.debug.print(" {d:.8}{s}", .{ coefficient, if (i + 1 == coefficients.len) "" else "," });
            }
            std.debug.print(" }};\nconst double {s} =", .{name});
            var term_index: usize = 0;
            for (0..FIT_DEGREE + 1) |total_degree| {
                for (0..total_degree + 1) |m_degree| {
                    std.debug.print("{s} {s}s[{}]", .{ if (term_index == 0) "" else " +", name, term_index });
                    for (0..m_degree) |_| std.debug.print(" * m", .{});
                    for (0..total_degree - m_degree) |_| std.debug.print(" * f", .{});
                    term_index += 1;
                }
            }
        },
    }
    std.debug.print(";\n", .{});
}
