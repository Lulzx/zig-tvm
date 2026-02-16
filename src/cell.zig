const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ── Error set (shared with TVM) ────────────────────────────────────────

pub const CellError = error{
    CellOverflow,
    CellUnderflow,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Int257 – 257-bit signed integer (sign-magnitude, 4x u64 little-endian limbs)
// Range: [-2^256, 2^256-1]
// ---------------------------------------------------------------------------

pub const Int257 = struct {
    limbs: [4]u64 = .{ 0, 0, 0, 0 },
    sign: bool = false, // true = negative

    pub fn zero() Int257 {
        return .{};
    }

    pub fn one() Int257 {
        return .{ .limbs = .{ 1, 0, 0, 0 } };
    }

    pub fn isZero(self: Int257) bool {
        return self.limbs[0] == 0 and self.limbs[1] == 0 and
            self.limbs[2] == 0 and self.limbs[3] == 0;
    }

    fn normalize(self: Int257) Int257 {
        var r = self;
        if (r.isZero()) r.sign = false;
        return r;
    }

    pub fn fromI64(v: i64) Int257 {
        if (v >= 0) {
            return .{ .limbs = .{ @intCast(v), 0, 0, 0 }, .sign = false };
        }
        const mag: u64 = if (v == std.math.minInt(i64))
            @as(u64, 1) << 63
        else
            @intCast(-v);
        return .{ .limbs = .{ mag, 0, 0, 0 }, .sign = true };
    }

    pub fn toI64(self: Int257) i64 {
        if (self.limbs[1] != 0 or self.limbs[2] != 0 or self.limbs[3] != 0) return 0;
        const v = self.limbs[0];
        if (!self.sign) {
            if (v > @as(u64, @intCast(std.math.maxInt(i64)))) return 0;
            return @intCast(v);
        }
        if (v > @as(u64, 1) << 63) return 0;
        if (v == @as(u64, 1) << 63) return std.math.minInt(i64);
        return -@as(i64, @intCast(v));
    }

    fn cmpMag(a: Int257, b: Int257) std.math.Order {
        var i: usize = 4;
        while (i > 0) {
            i -= 1;
            if (a.limbs[i] < b.limbs[i]) return .lt;
            if (a.limbs[i] > b.limbs[i]) return .gt;
        }
        return .eq;
    }

    pub fn cmp(a: Int257, b: Int257) std.math.Order {
        const an = a.normalize();
        const bn = b.normalize();
        if (an.sign != bn.sign) {
            if (an.isZero() and bn.isZero()) return .eq;
            return if (an.sign) .lt else .gt;
        }
        const mag = cmpMag(an, bn);
        return if (an.sign) mag.invert() else mag;
    }

    pub fn eql(a: Int257, b: Int257) bool {
        return a.cmp(b) == .eq;
    }

    fn addMag(a: [4]u64, b: [4]u64) struct { limbs: [4]u64, carry: u1 } {
        var result: [4]u64 = undefined;
        var carry: u1 = 0;
        for (0..4) |i| {
            const r1 = @addWithOverflow(a[i], b[i]);
            const r2 = @addWithOverflow(r1[0], @as(u64, carry));
            result[i] = r2[0];
            carry = r1[1] | r2[1];
        }
        return .{ .limbs = result, .carry = carry };
    }

    fn subMag(a: [4]u64, b: [4]u64) struct { limbs: [4]u64, borrow: u1 } {
        var result: [4]u64 = undefined;
        var borrow: u1 = 0;
        for (0..4) |i| {
            const r1 = @subWithOverflow(a[i], b[i]);
            const r2 = @subWithOverflow(r1[0], @as(u64, borrow));
            result[i] = r2[0];
            borrow = r1[1] | r2[1];
        }
        return .{ .limbs = result, .borrow = borrow };
    }

    /// Returns error.IntegerOverflow on overflow
    pub fn add(a: Int257, b: Int257) error{IntegerOverflow}!Int257 {
        if (a.sign == b.sign) {
            const r = addMag(a.limbs, b.limbs);
            if (r.carry != 0) return error.IntegerOverflow;
            return (Int257{ .limbs = r.limbs, .sign = a.sign }).normalize();
        }
        return switch (cmpMag(a, b)) {
            .eq => Int257.zero(),
            .gt => (Int257{ .limbs = subMag(a.limbs, b.limbs).limbs, .sign = a.sign }).normalize(),
            .lt => (Int257{ .limbs = subMag(b.limbs, a.limbs).limbs, .sign = b.sign }).normalize(),
        };
    }

    pub fn sub(a: Int257, b: Int257) error{IntegerOverflow}!Int257 {
        var nb = b;
        nb.sign = !nb.sign;
        return a.add(nb.normalize());
    }

    fn mulMagFull(a: [4]u64, b: [4]u64) [8]u64 {
        var result: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        for (0..4) |i| {
            var carry: u64 = 0;
            for (0..4) |j| {
                const wide: u128 = @as(u128, a[i]) * @as(u128, b[j]) +
                    @as(u128, result[i + j]) + @as(u128, carry);
                result[i + j] = @truncate(wide);
                carry = @truncate(wide >> 64);
            }
            result[i + 4] = carry;
        }
        return result;
    }

    pub fn mul(a: Int257, b: Int257) error{IntegerOverflow}!Int257 {
        const full = mulMagFull(a.limbs, b.limbs);
        if (full[4] != 0 or full[5] != 0 or full[6] != 0 or full[7] != 0) return error.IntegerOverflow;
        return (Int257{ .limbs = .{ full[0], full[1], full[2], full[3] }, .sign = a.sign != b.sign }).normalize();
    }

    fn shlOne(limbs: [4]u64) struct { limbs: [4]u64, overflow: u1 } {
        var r: [4]u64 = undefined;
        var carry: u1 = 0;
        for (0..4) |i| {
            const top: u1 = @truncate(limbs[i] >> 63);
            r[i] = (limbs[i] << 1) | @as(u64, carry);
            carry = top;
        }
        return .{ .limbs = r, .overflow = carry };
    }

    /// Returns [2]Int257 = {quotient, remainder}. error on division by zero.
    pub fn divmod(a: Int257, b: Int257) error{DivisionByZero}![2]Int257 {
        if (b.isZero()) return error.DivisionByZero;
        if (a.isZero()) return .{ Int257.zero(), Int257.zero() };

        const num = a.limbs;
        const den = b.limbs;

        var quot: [4]u64 = .{ 0, 0, 0, 0 };
        var rem: [4]u64 = .{ 0, 0, 0, 0 };

        var bit: u16 = 256;
        while (bit > 0) {
            bit -= 1;
            const sh = shlOne(rem);
            rem = sh.limbs;

            const limb_idx = bit / 64;
            const bit_idx: u6 = @truncate(bit % 64);
            const nbit: u1 = @truncate(num[limb_idx] >> bit_idx);
            rem[0] |= @as(u64, nbit);

            if (cmpMag(.{ .limbs = rem }, .{ .limbs = den }) != .lt) {
                rem = subMag(rem, den).limbs;
                const qi = bit / 64;
                const qb: u6 = @truncate(bit % 64);
                quot[qi] |= @as(u64, 1) << qb;
            }
        }

        var q = Int257{ .limbs = quot, .sign = a.sign != b.sign };
        var r = Int257{ .limbs = rem, .sign = a.sign };

        q = q.normalize();
        r = r.normalize();

        // Floor division: if remainder != 0 and signs differ, adjust
        if (!r.isZero() and (a.sign != b.sign)) {
            q = q.sub(Int257.one()) catch return .{ q, r };
            r = r.add(.{ .limbs = b.limbs, .sign = b.sign }) catch return .{ q, r };
        }

        return .{ q, r };
    }

    /// Shift left by n bits
    pub fn shl(self: Int257, n: u16) error{IntegerOverflow}!Int257 {
        if (n == 0) return self;
        if (n >= 256) {
            if (!self.isZero()) return error.IntegerOverflow;
            return self;
        }

        var result: [4]u64 = .{ 0, 0, 0, 0 };
        const word_shift = n / 64;
        const bit_shift: u6 = @truncate(n % 64);

        for (0..4) |i| {
            if (i + word_shift < 4) {
                result[i + word_shift] |= self.limbs[i] << bit_shift;
            } else if (self.limbs[i] != 0) {
                return error.IntegerOverflow;
            }
            if (bit_shift > 0 and i + word_shift + 1 < 4) {
                result[i + word_shift + 1] |= self.limbs[i] >> @intCast(64 - @as(u7, bit_shift));
            } else if (bit_shift > 0 and i + word_shift + 1 >= 4) {
                const high_bits = self.limbs[i] >> @intCast(64 - @as(u7, bit_shift));
                if (high_bits != 0) return error.IntegerOverflow;
            }
        }

        return (Int257{ .limbs = result, .sign = self.sign }).normalize();
    }

    /// Shift right by n bits (toward zero for magnitude)
    pub fn shr(self: Int257, n: u16) Int257 {
        if (n == 0) return self;
        if (n >= 256) return Int257.zero();

        var result: [4]u64 = .{ 0, 0, 0, 0 };
        const word_shift = n / 64;
        const bit_shift: u6 = @truncate(n % 64);

        for (0..4) |i| {
            if (i + word_shift < 4) {
                result[i] |= self.limbs[i + word_shift] >> bit_shift;
            }
            if (bit_shift > 0 and i + word_shift + 1 < 4) {
                result[i] |= self.limbs[i + word_shift + 1] << @intCast(64 - @as(u7, bit_shift));
            }
        }

        return (Int257{ .limbs = result, .sign = self.sign }).normalize();
    }

    /// Bitwise AND (on magnitudes)
    pub fn bitAnd(a: Int257, b: Int257) Int257 {
        return (Int257{
            .limbs = .{
                a.limbs[0] & b.limbs[0],
                a.limbs[1] & b.limbs[1],
                a.limbs[2] & b.limbs[2],
                a.limbs[3] & b.limbs[3],
            },
            .sign = a.sign and b.sign,
        }).normalize();
    }

    /// Bitwise OR (on magnitudes)
    pub fn bitOr(a: Int257, b: Int257) Int257 {
        return (Int257{
            .limbs = .{
                a.limbs[0] | b.limbs[0],
                a.limbs[1] | b.limbs[1],
                a.limbs[2] | b.limbs[2],
                a.limbs[3] | b.limbs[3],
            },
            .sign = a.sign or b.sign,
        }).normalize();
    }

    /// Bitwise XOR (on magnitudes)
    pub fn bitXor(a: Int257, b: Int257) Int257 {
        return (Int257{
            .limbs = .{
                a.limbs[0] ^ b.limbs[0],
                a.limbs[1] ^ b.limbs[1],
                a.limbs[2] ^ b.limbs[2],
                a.limbs[3] ^ b.limbs[3],
            },
            .sign = a.sign != b.sign,
        }).normalize();
    }

    /// Bitwise NOT (complement magnitude)
    pub fn bitNot(self: Int257) Int257 {
        return (Int257{
            .limbs = .{
                ~self.limbs[0],
                ~self.limbs[1],
                ~self.limbs[2],
                ~self.limbs[3],
            },
            .sign = !self.sign,
        }).normalize();
    }

    pub fn fitsInBits(self: Int257, n: u16) bool {
        if (n == 0) return self.isZero();
        if (n >= 257) return true;
        const shift = n - 1;
        if (shift >= 256) return true;
        var threshold: [4]u64 = .{ 0, 0, 0, 0 };
        const limb_idx = shift / 64;
        const bit_idx: u6 = @truncate(shift % 64);
        threshold[limb_idx] = @as(u64, 1) << bit_idx;
        const thr = Int257{ .limbs = threshold };
        const mag_cmp = cmpMag(self.normalize(), thr);
        if (self.sign) {
            return mag_cmp != .gt;
        } else {
            return mag_cmp == .lt;
        }
    }

    pub fn format(self: Int257, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.isZero()) {
            try writer.writeAll("0");
            return;
        }
        if (self.sign) try writer.writeByte('-');
        try writer.writeAll("0x");
        var started = false;
        var i: usize = 4;
        while (i > 0) {
            i -= 1;
            if (self.limbs[i] != 0 or started) {
                if (started) {
                    try std.fmt.format(writer, "{x:0>16}", .{self.limbs[i]});
                } else {
                    try std.fmt.format(writer, "{x}", .{self.limbs[i]});
                }
                started = true;
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Cell -- up to 1023 data bits + up to 4 references
// ---------------------------------------------------------------------------

pub const Cell = struct {
    data: [128]u8 = .{0} ** 128,
    bit_len: u16 = 0,
    refs: [4]*Cell = undefined,
    ref_count: u8 = 0,
    hash: [32]u8 = .{0} ** 32,
    hash_valid: bool = false,
    rc: u32 = 0,

    pub fn computeHash(self: *Cell) [32]u8 {
        if (self.hash_valid) return self.hash;

        var h = Sha256.init(.{});
        const d1: u8 = self.ref_count;
        const byte_len: u16 = (self.bit_len + 7) / 8;
        const d2: u8 = @truncate(byte_len);
        h.update(&.{ d1, d2 });
        h.update(self.data[0..byte_len]);

        for (0..self.ref_count) |i| {
            const ref_hash = self.refs[i].computeHash();
            h.update(&ref_hash);
        }

        h.final(&self.hash);
        self.hash_valid = true;
        return self.hash;
    }
};

// ---------------------------------------------------------------------------
// CellArena -- fixed-pool allocator for Cell structs
// ---------------------------------------------------------------------------

pub const pool_size: usize = 4096;

pub const CellArena = struct {
    pool: [pool_size]Cell = undefined,
    free_list: [pool_size]u32 = undefined,
    free_count: u32 = pool_size,
    allocated: u32 = 0,

    pub fn init() CellArena {
        var arena: CellArena = .{};
        for (0..pool_size) |i| {
            arena.free_list[i] = @intCast(pool_size - 1 - i);
            arena.pool[i] = .{};
        }
        return arena;
    }

    pub fn alloc(self: *CellArena) CellError!*Cell {
        if (self.free_count == 0) return error.OutOfMemory;
        self.free_count -= 1;
        const idx = self.free_list[self.free_count];
        self.pool[idx] = .{};
        self.pool[idx].rc = 1;
        self.allocated += 1;
        return &self.pool[idx];
    }

    pub fn free(self: *CellArena, c: *Cell) void {
        const addr = @intFromPtr(c);
        const base = @intFromPtr(&self.pool[0]);
        const idx: u32 = @intCast((addr - base) / @sizeOf(Cell));
        if (idx < pool_size) {
            self.free_list[self.free_count] = idx;
            self.free_count += 1;
            self.allocated -= 1;
        }
    }

    pub fn reset(self: *CellArena) void {
        for (0..pool_size) |i| {
            self.free_list[i] = @intCast(pool_size - 1 - i);
            self.pool[i] = .{};
        }
        self.free_count = pool_size;
        self.allocated = 0;
    }
};

// ---------------------------------------------------------------------------
// Slice -- lightweight read cursor over a Cell
// ---------------------------------------------------------------------------

pub const Slice = struct {
    cell: *Cell = undefined,
    bit_offset: u16 = 0,
    bit_end: u16 = 0,
    ref_offset: u8 = 0,
    ref_end: u8 = 0,

    pub fn empty() Slice {
        return .{};
    }

    pub fn fromCell(c: *Cell) Slice {
        return .{
            .cell = c,
            .bit_offset = 0,
            .bit_end = c.bit_len,
            .ref_offset = 0,
            .ref_end = c.ref_count,
        };
    }

    pub fn remainingBits(self: Slice) u16 {
        if (self.bit_end <= self.bit_offset) return 0;
        return self.bit_end - self.bit_offset;
    }

    pub fn remainingRefs(self: Slice) u8 {
        if (self.ref_end <= self.ref_offset) return 0;
        return self.ref_end - self.ref_offset;
    }

    pub fn isEmpty(self: Slice) bool {
        return self.remainingBits() == 0 and self.remainingRefs() == 0;
    }

    pub fn skipBits(self: *Slice, n: u16) void {
        self.bit_offset += n;
    }

    /// Load n bits (1..64) as u64, MSB-first (big-endian bit order per TVM spec)
    pub fn loadUint(self: *Slice, n: u16) CellError!u64 {
        if (n == 0) return 0;
        if (n > 64) return error.CellUnderflow;
        if (self.remainingBits() < n) return error.CellUnderflow;

        var result: u64 = 0;
        var bits_left: u16 = n;
        var offset = self.bit_offset;

        while (bits_left > 0) {
            const byte_idx = offset / 8;
            const bit_in_byte: u4 = @truncate(offset % 8);
            const avail: u16 = 8 - @as(u16, bit_in_byte);
            const take: u16 = @min(avail, bits_left);

            const shift: u3 = @truncate(avail - take);
            const mask: u8 = @truncate((@as(u16, 1) << @as(u4, @truncate(take))) - 1);
            const bits: u64 = @as(u64, (self.cell.data[byte_idx] >> shift) & mask);

            result = (result << @as(u6, @truncate(take))) | bits;
            offset += take;
            bits_left -= take;
        }

        self.bit_offset += n;
        return result;
    }

    /// Load n-bit signed integer (two's complement)
    pub fn loadInt(self: *Slice, n: u16) CellError!i64 {
        if (n == 0) return 0;
        const raw = try self.loadUint(n);
        if (n >= 64) return @bitCast(raw);
        const sign_bit = raw >> @as(u6, @truncate(n - 1));
        if (sign_bit != 0) {
            const mask = (@as(u64, 1) << @as(u6, @truncate(n))) - 1;
            return @bitCast(raw | ~mask);
        }
        return @intCast(raw);
    }

    pub fn loadRef(self: *Slice) CellError!*Cell {
        if (self.ref_offset >= self.ref_end) return error.CellUnderflow;
        const r = self.cell.refs[self.ref_offset];
        self.ref_offset += 1;
        return r;
    }
};

// ---------------------------------------------------------------------------
// Builder -- write buffer to construct cells
// ---------------------------------------------------------------------------

pub const Builder = struct {
    data: [128]u8 = .{0} ** 128,
    bit_len: u16 = 0,
    refs: [4]*Cell = undefined,
    ref_count: u8 = 0,

    pub fn init() Builder {
        return .{};
    }

    /// Store n bits (0..64) from val, MSB-first
    pub fn storeUint(self: *Builder, val: u64, n: u16) CellError!void {
        if (n == 0) return;
        if (self.bit_len + n > 1023) return error.CellOverflow;

        var bits_left: u16 = n;
        var offset = self.bit_len;

        while (bits_left > 0) {
            const byte_idx = offset / 8;
            const bit_in_byte: u4 = @truncate(offset % 8);
            const avail: u16 = 8 - @as(u16, bit_in_byte);
            const take: u16 = @min(avail, bits_left);

            const shift: u6 = @truncate(bits_left - take);
            const bits: u8 = @truncate(val >> shift);
            const mask: u8 = @truncate((@as(u16, 1) << @as(u4, @truncate(take))) - 1);
            const aligned_bits = bits & mask;

            const place_shift: u3 = @truncate(avail - take);
            self.data[byte_idx] |= aligned_bits << place_shift;

            offset += take;
            bits_left -= take;
        }

        self.bit_len += n;
    }

    /// Store Int257 as n-bit value
    pub fn storeInt(self: *Builder, val: Int257, n: u16) CellError!void {
        if (n == 0) return;
        if (n <= 64) {
            const i = val.toI64();
            const raw: u64 = @bitCast(i);
            if (n >= 64) {
                try self.storeUint(raw, n);
            } else {
                const mask = (@as(u64, 1) << @as(u6, @truncate(n))) - 1;
                try self.storeUint(raw & mask, n);
            }
        } else {
            // Multi-limb store: sign bit + magnitude (big-endian)
            try self.storeUint(if (val.sign) 1 else 0, 1);
            var remaining = n - 1;
            var limb_idx: usize = 4;
            while (limb_idx > 0 and remaining > 0) {
                limb_idx -= 1;
                const chunk = @min(remaining, 64);
                try self.storeUint(val.limbs[limb_idx], chunk);
                remaining -= chunk;
            }
        }
    }

    pub fn storeRef(self: *Builder, c: *Cell) CellError!void {
        if (self.ref_count >= 4) return error.CellOverflow;
        self.refs[self.ref_count] = c;
        self.ref_count += 1;
    }

    pub fn storeSlice(self: *Builder, s: *Slice) CellError!void {
        var remaining = s.remainingBits();
        while (remaining > 0) {
            const chunk: u16 = @min(remaining, 64);
            const val = try s.loadUint(chunk);
            try self.storeUint(val, chunk);
            remaining -= chunk;
        }
        while (s.ref_offset < s.ref_end) {
            const ref = try s.loadRef();
            try self.storeRef(ref);
        }
    }

    pub fn finalize(self: *Builder, arena: *CellArena) CellError!*Cell {
        const c = try arena.alloc();
        @memcpy(&c.data, &self.data);
        c.bit_len = self.bit_len;
        c.ref_count = self.ref_count;
        for (0..self.ref_count) |i| {
            c.refs[i] = self.refs[i];
            c.refs[i].rc += 1;
        }
        return c;
    }
};

// ===========================================================================
// Unit Tests
// ===========================================================================

test "Int257 fromI64/toI64 round-trip" {
    const cases = [_]i64{ 0, 1, -1, 42, -42, 1000000, -1000000, std.math.maxInt(i64), std.math.minInt(i64) };
    for (cases) |v| {
        const x = Int257.fromI64(v);
        try std.testing.expectEqual(v, x.toI64());
    }
}

test "Int257 zero is zero" {
    const z = Int257.zero();
    try std.testing.expect(z.isZero());
    try std.testing.expectEqual(@as(i64, 0), z.toI64());
}

test "Int257 add basic" {
    const a = Int257.fromI64(100);
    const b = Int257.fromI64(200);
    const r = try a.add(b);
    try std.testing.expectEqual(@as(i64, 300), r.toI64());
}

test "Int257 add negative" {
    const a = Int257.fromI64(100);
    const b = Int257.fromI64(-300);
    const r = try a.add(b);
    try std.testing.expectEqual(@as(i64, -200), r.toI64());
}

test "Int257 sub" {
    const a = Int257.fromI64(50);
    const b = Int257.fromI64(80);
    const r = try a.sub(b);
    try std.testing.expectEqual(@as(i64, -30), r.toI64());
}

test "Int257 mul" {
    const a = Int257.fromI64(123);
    const b = Int257.fromI64(456);
    const r = try a.mul(b);
    try std.testing.expectEqual(@as(i64, 56088), r.toI64());
}

test "Int257 mul negative" {
    const a = Int257.fromI64(-7);
    const b = Int257.fromI64(6);
    const r = try a.mul(b);
    try std.testing.expectEqual(@as(i64, -42), r.toI64());
}

test "Int257 divmod" {
    const a = Int257.fromI64(17);
    const b = Int257.fromI64(5);
    const dm = try Int257.divmod(a, b);
    try std.testing.expectEqual(@as(i64, 3), dm[0].toI64());
    try std.testing.expectEqual(@as(i64, 2), dm[1].toI64());
}

test "Int257 floor division negative" {
    const a = Int257.fromI64(-7);
    const b = Int257.fromI64(2);
    const dm = try Int257.divmod(a, b);
    try std.testing.expectEqual(@as(i64, -4), dm[0].toI64());
    try std.testing.expectEqual(@as(i64, 1), dm[1].toI64());
}

test "Int257 div by zero" {
    const a = Int257.fromI64(42);
    const b = Int257.zero();
    try std.testing.expectError(error.DivisionByZero, Int257.divmod(a, b));
}

test "Int257 comparison" {
    const a = Int257.fromI64(10);
    const b = Int257.fromI64(20);
    const c = Int257.fromI64(-5);
    try std.testing.expectEqual(std.math.Order.lt, a.cmp(b));
    try std.testing.expectEqual(std.math.Order.gt, b.cmp(a));
    try std.testing.expectEqual(std.math.Order.eq, a.cmp(a));
    try std.testing.expectEqual(std.math.Order.gt, a.cmp(c));
    try std.testing.expectEqual(std.math.Order.lt, c.cmp(a));
}

test "Int257 shift left and right" {
    const a = Int257.fromI64(1);
    const shifted = try a.shl(10);
    try std.testing.expectEqual(@as(i64, 1024), shifted.toI64());
    const back = shifted.shr(10);
    try std.testing.expectEqual(@as(i64, 1), back.toI64());
}

test "Int257 bitwise ops" {
    const a = Int257.fromI64(0xFF);
    const b = Int257.fromI64(0x0F);
    const and_r = a.bitAnd(b);
    try std.testing.expectEqual(@as(i64, 0x0F), and_r.toI64());
    const or_r = a.bitOr(b);
    try std.testing.expectEqual(@as(i64, 0xFF), or_r.toI64());
    const xor_r = a.bitXor(b);
    try std.testing.expectEqual(@as(i64, 0xF0), xor_r.toI64());
}

test "Int257 large multiplication" {
    const a = Int257{ .limbs = .{ 1 << 32, 0, 0, 0 } };
    const b = Int257{ .limbs = .{ 1 << 32, 0, 0, 0 } };
    const r = try a.mul(b);
    try std.testing.expectEqual(@as(u64, 0), r.limbs[0]);
    try std.testing.expectEqual(@as(u64, 1), r.limbs[1]);
}

test "CellArena alloc and free" {
    var arena = CellArena.init();
    const c1 = try arena.alloc();
    const c2 = try arena.alloc();
    try std.testing.expect(c1 != c2);
    try std.testing.expectEqual(@as(u32, 2), arena.allocated);

    arena.free(c1);
    try std.testing.expectEqual(@as(u32, 1), arena.allocated);

    const c3 = try arena.alloc();
    try std.testing.expect(c3 == c1);
}

test "Builder/Slice round-trip u64" {
    var arena = CellArena.init();
    var b = Builder.init();
    try b.storeUint(0xDEAD, 16);
    try b.storeUint(0xBEEF, 16);
    try b.storeUint(42, 8);

    const c = try b.finalize(&arena);
    var s = Slice.fromCell(c);
    try std.testing.expectEqual(@as(u64, 0xDEAD), try s.loadUint(16));
    try std.testing.expectEqual(@as(u64, 0xBEEF), try s.loadUint(16));
    try std.testing.expectEqual(@as(u64, 42), try s.loadUint(8));
    try std.testing.expect(s.remainingBits() == 0);
}

test "Builder/Slice round-trip signed int" {
    var arena = CellArena.init();
    var b = Builder.init();
    try b.storeUint(@as(u64, @bitCast(@as(i64, -100))) & 0xFFFF, 16);
    try b.storeUint(@as(u64, @bitCast(@as(i64, 100))) & 0xFFFF, 16);

    const c = try b.finalize(&arena);
    var s = Slice.fromCell(c);
    try std.testing.expectEqual(@as(i64, -100), try s.loadInt(16));
    try std.testing.expectEqual(@as(i64, 100), try s.loadInt(16));
}

test "Builder storeRef and Slice loadRef" {
    var arena = CellArena.init();
    const child = try arena.alloc();

    var b = Builder.init();
    try b.storeUint(0xFF, 8);
    try b.storeRef(child);
    const c = try b.finalize(&arena);

    var s = Slice.fromCell(c);
    try std.testing.expectEqual(@as(u64, 0xFF), try s.loadUint(8));
    try std.testing.expectEqual(@as(u8, 1), s.remainingRefs());
    const ref = try s.loadRef();
    try std.testing.expect(ref == child);
}

test "Builder bit-level alignment" {
    var arena = CellArena.init();
    var b = Builder.init();
    try b.storeUint(0b101, 3);
    try b.storeUint(0b11010, 5);
    try b.storeUint(0xFF, 8);

    const c = try b.finalize(&arena);
    var s = Slice.fromCell(c);
    try std.testing.expectEqual(@as(u64, 0b101), try s.loadUint(3));
    try std.testing.expectEqual(@as(u64, 0b11010), try s.loadUint(5));
    try std.testing.expectEqual(@as(u64, 0xFF), try s.loadUint(8));
}

test "Slice empty" {
    var arena = CellArena.init();
    const c = try arena.alloc();
    const s = Slice.fromCell(c);
    try std.testing.expect(s.isEmpty());
}

test "Cell hash" {
    var arena = CellArena.init();
    var b = Builder.init();
    try b.storeUint(0xCAFE, 16);
    var c = try b.finalize(&arena);

    const h1 = c.computeHash();
    const h2 = c.computeHash();
    try std.testing.expectEqualSlices(u8, &h1, &h2);
    var all_zero = true;
    for (h1) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}
