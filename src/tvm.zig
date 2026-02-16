const std = @import("std");
const cell = @import("cell.zig");
const ops = @import("ops.zig");

pub const Int257 = cell.Int257;
pub const Cell = cell.Cell;
pub const Slice = cell.Slice;
pub const Builder = cell.Builder;
pub const CellArena = cell.CellArena;

pub const MAX_STACK: u32 = 256;
const MAX_TUPLES: u32 = 256;
const MAX_CONTS: u32 = 1024;

// ── Error set ──────────────────────────────────────────────────────────

pub const TvmError = error{
    StackUnderflow,
    StackOverflow,
    IntegerOverflow,
    IntegerOutOfRange,
    InvalidOpcode,
    TypeMismatch,
    CellOverflow,
    CellUnderflow,
    OutOfGas,
    InvalidArg,
    DivisionByZero,
    TupleOverflow,
    TupleIndexOutOfRange,
    InvalidContinuation,
    OutOfMemory,
    Halted,
};

// ── Forward declare Continuation ───────────────────────────────────────

pub const Continuation = struct {
    code: Slice = Slice.empty(),
    savelist: [8]SavedReg = [_]SavedReg{.none} ** 8,
    nargs: i16 = -1,

    pub fn fromSlice(s: Slice) Continuation {
        return .{ .code = s };
    }
};

/// SavedReg avoids circular dependency: stores saved register values
/// without referencing Value (which would create the cycle).
pub const SavedReg = union(enum) {
    none: void,
    int_val: Int257,
    cont_idx: u32, // index into cont arena
};

// ── Value ──────────────────────────────────────────────────────────────

pub const Value = union(enum) {
    int: Int257,
    cell: *Cell,
    slice: Slice,
    builder: Builder,
    cont: Continuation,
    tuple: *Tuple,
    null: void,

    pub fn asInt(self: Value) TvmError!Int257 {
        return switch (self) {
            .int => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asCell(self: Value) TvmError!*Cell {
        return switch (self) {
            .cell => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asSlice(self: Value) TvmError!Slice {
        return switch (self) {
            .slice => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asBuilder(self: Value) TvmError!Builder {
        return switch (self) {
            .builder => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asCont(self: Value) TvmError!Continuation {
        return switch (self) {
            .cont => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asTuple(self: Value) TvmError!*Tuple {
        return switch (self) {
            .tuple => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn isNull(self: Value) bool {
        return switch (self) {
            .null => true,
            else => false,
        };
    }
};

// ── Stack ──────────────────────────────────────────────────────────────

pub const Stack = struct {
    items: [MAX_STACK]Value = [_]Value{.null} ** MAX_STACK,
    depth: u32 = 0,

    pub fn push(self: *Stack, val: Value) TvmError!void {
        if (self.depth >= MAX_STACK) return error.StackOverflow;
        self.items[self.depth] = val;
        self.depth += 1;
    }

    pub fn pop(self: *Stack) TvmError!Value {
        if (self.depth == 0) return error.StackUnderflow;
        self.depth -= 1;
        const val = self.items[self.depth];
        self.items[self.depth] = .null;
        return val;
    }

    pub fn peek(self: *Stack, i: u32) TvmError!Value {
        if (i >= self.depth) return error.StackUnderflow;
        return self.items[self.depth - 1 - i];
    }

    pub fn xchg(self: *Stack, i: u32, j: u32) TvmError!void {
        if (i >= self.depth or j >= self.depth) return error.StackUnderflow;
        const ai = self.depth - 1 - i;
        const aj = self.depth - 1 - j;
        const tmp = self.items[ai];
        self.items[ai] = self.items[aj];
        self.items[aj] = tmp;
    }

    pub fn roll(self: *Stack, n: u32) TvmError!void {
        if (n == 0) return;
        if (n >= self.depth) return error.StackUnderflow;
        const base = self.depth - 1 - n;
        const saved = self.items[base];
        var k: u32 = base;
        while (k < self.depth - 1) : (k += 1) {
            self.items[k] = self.items[k + 1];
        }
        self.items[self.depth - 1] = saved;
    }

    pub fn rollRev(self: *Stack, n: u32) TvmError!void {
        if (n == 0) return;
        if (n >= self.depth) return error.StackUnderflow;
        const top = self.items[self.depth - 1];
        var k: u32 = self.depth - 1;
        while (k > self.depth - 1 - n) : (k -= 1) {
            self.items[k] = self.items[k - 1];
        }
        self.items[self.depth - 1 - n] = top;
    }

    pub fn blkswap(self: *Stack, i: u32, j: u32) TvmError!void {
        if (i == 0 or j == 0) return;
        if (i + j > self.depth) return error.StackUnderflow;
        self.reverseRange(self.depth - i, self.depth);
        self.reverseRange(self.depth - i - j, self.depth - i);
        self.reverseRange(self.depth - i - j, self.depth);
    }

    pub fn reverseRange(self: *Stack, start: u32, end: u32) void {
        var lo = start;
        var hi = end - 1;
        while (lo < hi) {
            const tmp = self.items[lo];
            self.items[lo] = self.items[hi];
            self.items[hi] = tmp;
            lo += 1;
            hi -= 1;
        }
    }

    pub fn blkpush(self: *Stack, count: u32, from: u32) TvmError!void {
        if (from + count > self.depth) return error.StackUnderflow;
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            const val = self.items[self.depth - 1 - from - k];
            try self.push(val);
        }
    }

    pub fn blkdrop(self: *Stack, n: u32) TvmError!void {
        if (n > self.depth) return error.StackUnderflow;
        var k: u32 = 0;
        while (k < n) : (k += 1) {
            self.depth -= 1;
            self.items[self.depth] = .null;
        }
    }
};

// ── Tuple ──────────────────────────────────────────────────────────────

pub const Tuple = struct {
    len: u8 = 0,
    items: [255]Value = [_]Value{.null} ** 255,

    pub fn get(self: *const Tuple, idx: u8) TvmError!Value {
        if (idx >= self.len) return error.TupleIndexOutOfRange;
        return self.items[idx];
    }

    pub fn set(self: *Tuple, idx: u8, val: Value) TvmError!void {
        if (idx >= self.len) return error.TupleIndexOutOfRange;
        self.items[idx] = val;
    }

    pub fn tpush(self: *Tuple, val: Value) TvmError!void {
        if (self.len >= 255) return error.TupleOverflow;
        self.items[self.len] = val;
        self.len += 1;
    }

    pub fn tpop(self: *Tuple) TvmError!Value {
        if (self.len == 0) return error.StackUnderflow;
        self.len -= 1;
        const val = self.items[self.len];
        self.items[self.len] = .null;
        return val;
    }
};

// ── Tuple Arena ────────────────────────────────────────────────────────

pub const TupleArena = struct {
    pool: [MAX_TUPLES]Tuple = undefined,
    free_list: [MAX_TUPLES]u32 = undefined,
    free_count: u32 = MAX_TUPLES,

    pub fn init() TupleArena {
        var arena: TupleArena = .{};
        for (0..MAX_TUPLES) |i| {
            arena.free_list[i] = @intCast(MAX_TUPLES - 1 - i);
            arena.pool[i] = .{};
        }
        return arena;
    }

    pub fn alloc(self: *TupleArena) TvmError!*Tuple {
        if (self.free_count == 0) return error.OutOfMemory;
        self.free_count -= 1;
        const idx = self.free_list[self.free_count];
        self.pool[idx] = .{};
        return &self.pool[idx];
    }

    pub fn free(self: *TupleArena, t: *Tuple) void {
        const idx: u32 = @intCast((@intFromPtr(t) - @intFromPtr(&self.pool[0])) / @sizeOf(Tuple));
        if (idx < MAX_TUPLES) {
            self.free_list[self.free_count] = idx;
            self.free_count += 1;
        }
    }
};

// ── TVM ────────────────────────────────────────────────────────────────

pub const TVM = struct {
    stack: Stack = .{},
    cr: [8]?Value = [_]?Value{null} ** 8,
    gas_remaining: i64 = 1_000_000,
    gas_limit: i64 = 1_000_000,
    cc: Continuation = .{},
    cp: u16 = 0,
    cell_arena: *CellArena,
    tuple_arena: *TupleArena = undefined,
    exit_code: i32 = 0,
    running: bool = false,

    pub fn init(arena: *CellArena) TVM {
        return .{
            .cell_arena = arena,
        };
    }

    pub fn setGas(self: *TVM, limit: i64) void {
        self.gas_limit = limit;
        self.gas_remaining = limit;
    }

    pub fn setCode(self: *TVM, code_cell: *Cell) void {
        self.cc = Continuation.fromSlice(Slice.fromCell(code_cell));
    }

    pub inline fn charge(self: *TVM, cost: i64) TvmError!void {
        self.gas_remaining -= cost;
        if (self.gas_remaining < 0) return error.OutOfGas;
    }

    pub fn run(self: *TVM) void {
        self.running = true;
        while (self.running) {
            if (self.cc.code.remainingBits() == 0) {
                self.doRet() catch |e| {
                    self.handleError(e);
                    continue;
                };
                continue;
            }
            const byte0 = self.cc.code.loadUint(8) catch {
                self.handleError(error.InvalidOpcode);
                continue;
            };
            ops.dispatch(self, @intCast(byte0)) catch |e| {
                self.handleError(e);
            };
        }
    }

    pub fn doRet(self: *TVM) TvmError!void {
        const c0_val = self.cr[0] orelse {
            self.exit_code = 0;
            self.running = false;
            return;
        };
        const c0 = try c0_val.asCont();
        self.cr[0] = null;
        self.switchToCont(c0);
    }

    pub fn doRetAlt(self: *TVM) TvmError!void {
        const c1_val = self.cr[1] orelse {
            self.exit_code = 0;
            self.running = false;
            return;
        };
        const c1 = try c1_val.asCont();
        self.cr[1] = null;
        self.switchToCont(c1);
    }

    pub fn switchToCont(self: *TVM, cont: Continuation) void {
        // Restore saved registers
        for (0..8) |i| {
            switch (cont.savelist[i]) {
                .none => {},
                .int_val => |v| self.cr[i] = .{ .int = v },
                .cont_idx => {},
            }
        }
        self.cc = cont;
    }

    pub fn callCont(self: *TVM, cont: Continuation) void {
        var ret_cont = self.cc;
        // Save c0 into the return continuation's savelist
        if (self.cr[0]) |c0| {
            switch (c0) {
                .int => |v| ret_cont.savelist[0] = .{ .int_val = v },
                else => ret_cont.savelist[0] = .none,
            }
        }
        self.cr[0] = .{ .cont = ret_cont };
        self.switchToCont(cont);
    }

    pub fn jumpToCont(self: *TVM, cont: Continuation) void {
        self.switchToCont(cont);
    }

    pub fn handleError(self: *TVM, err: TvmError) void {
        const code: i32 = switch (err) {
            error.StackUnderflow => 2,
            error.StackOverflow => 3,
            error.IntegerOverflow => 4,
            error.IntegerOutOfRange => 5,
            error.InvalidOpcode => 6,
            error.TypeMismatch => 7,
            error.CellOverflow => 8,
            error.CellUnderflow => 9,
            error.DivisionByZero => 10,
            error.OutOfGas => -14,
            else => 0,
        };

        // Check if c2 (exception handler) is set
        if (self.cr[2]) |c2_val| {
            if (c2_val.asCont()) |c2| {
                self.cr[2] = null;
                self.stack.push(.{ .int = Int257.fromI64(code) }) catch {
                    self.exit_code = code;
                    self.running = false;
                    return;
                };
                self.switchToCont(c2);
                return;
            } else |_| {}
        }

        self.exit_code = code;
        self.running = false;
    }

    pub fn fetchUint(self: *TVM, bits: u16) TvmError!u64 {
        return self.cc.code.loadUint(bits) catch error.InvalidOpcode;
    }

    pub fn fetchInt(self: *TVM, bits: u16) TvmError!i64 {
        return self.cc.code.loadInt(bits) catch error.InvalidOpcode;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "stack push pop" {
    var s = Stack{};
    try s.push(.{ .int = Int257.fromI64(42) });
    try s.push(.{ .int = Int257.fromI64(100) });
    const v1 = try (try s.pop()).asInt();
    const v2 = try (try s.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 100), v1.toI64());
    try std.testing.expectEqual(@as(i64, 42), v2.toI64());
}

test "stack xchg" {
    var s = Stack{};
    try s.push(.{ .int = Int257.fromI64(1) });
    try s.push(.{ .int = Int257.fromI64(2) });
    try s.push(.{ .int = Int257.fromI64(3) });
    try s.xchg(0, 2);
    const top = try (try s.peek(0)).asInt();
    const bot = try (try s.peek(2)).asInt();
    try std.testing.expectEqual(@as(i64, 1), top.toI64());
    try std.testing.expectEqual(@as(i64, 3), bot.toI64());
}

test "stack roll" {
    var s = Stack{};
    try s.push(.{ .int = Int257.fromI64(1) });
    try s.push(.{ .int = Int257.fromI64(2) });
    try s.push(.{ .int = Int257.fromI64(3) });
    try s.roll(2);
    const v0 = try (try s.peek(0)).asInt();
    const v1 = try (try s.peek(1)).asInt();
    const v2 = try (try s.peek(2)).asInt();
    try std.testing.expectEqual(@as(i64, 1), v0.toI64());
    try std.testing.expectEqual(@as(i64, 3), v1.toI64());
    try std.testing.expectEqual(@as(i64, 2), v2.toI64());
}

test "stack blkswap" {
    var s = Stack{};
    try s.push(.{ .int = Int257.fromI64(1) });
    try s.push(.{ .int = Int257.fromI64(2) });
    try s.push(.{ .int = Int257.fromI64(3) });
    try s.push(.{ .int = Int257.fromI64(4) });
    try s.blkswap(2, 2);
    const v0 = try (try s.peek(0)).asInt();
    const v1 = try (try s.peek(1)).asInt();
    const v2 = try (try s.peek(2)).asInt();
    const v3 = try (try s.peek(3)).asInt();
    try std.testing.expectEqual(@as(i64, 2), v0.toI64());
    try std.testing.expectEqual(@as(i64, 1), v1.toI64());
    try std.testing.expectEqual(@as(i64, 4), v2.toI64());
    try std.testing.expectEqual(@as(i64, 3), v3.toI64());
}

test "stack underflow" {
    var s = Stack{};
    try std.testing.expectError(error.StackUnderflow, s.pop());
}

test "stack blkdrop" {
    var s = Stack{};
    try s.push(.{ .int = Int257.fromI64(1) });
    try s.push(.{ .int = Int257.fromI64(2) });
    try s.push(.{ .int = Int257.fromI64(3) });
    try s.blkdrop(2);
    try std.testing.expectEqual(@as(u32, 1), s.depth);
    const v = try (try s.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 1), v.toI64());
}
