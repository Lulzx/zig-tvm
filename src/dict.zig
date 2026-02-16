const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;
const CellArena = cell.CellArena;
const Slice = cell.Slice;
const Builder = cell.Builder;
const CellError = cell.CellError;

pub const DictError = error{
    CellOverflow,
    CellUnderflow,
    OutOfMemory,
    InvalidDict,
};

// ── DictKey ────────────────────────────────────────────────────────────

pub const DictKey = struct {
    data: [128]u8 = .{0} ** 128,
    bit_len: u16 = 0,

    pub fn getBit(self: *const DictKey, idx: u16) u1 {
        const byte_idx = idx / 8;
        const bit_idx: u3 = @truncate(7 - (idx % 8));
        return @truncate((self.data[byte_idx] >> bit_idx) & 1);
    }

    pub fn setBit(self: *DictKey, idx: u16, val: u1) void {
        const byte_idx = idx / 8;
        const bit_idx: u3 = @truncate(7 - (idx % 8));
        if (val == 1) {
            self.data[byte_idx] |= @as(u8, 1) << bit_idx;
        } else {
            self.data[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        }
    }

    pub fn fromUint(val: u64, bit_len: u16) DictKey {
        var key = DictKey{ .bit_len = bit_len };
        if (bit_len == 0) return key;
        var i: u16 = 0;
        while (i < bit_len and i < 64) : (i += 1) {
            const shift: u6 = @truncate(bit_len - 1 - i);
            const bit: u1 = @truncate((val >> shift) & 1);
            key.setBit(i, bit);
        }
        return key;
    }

    pub fn fromInt(val: i64, bit_len: u16) DictKey {
        const raw: u64 = @bitCast(val);
        // Use the lower bit_len bits in two's complement
        if (bit_len >= 64) {
            return fromUint(raw, bit_len);
        }
        const mask = (@as(u64, 1) << @intCast(bit_len)) - 1;
        return fromUint(raw & mask, bit_len);
    }

    pub fn toUint(self: *const DictKey) u64 {
        var result: u64 = 0;
        var i: u16 = 0;
        while (i < self.bit_len and i < 64) : (i += 1) {
            result = (result << 1) | @as(u64, self.getBit(i));
        }
        return result;
    }

    pub fn toInt(self: *const DictKey) i64 {
        const raw = self.toUint();
        if (self.bit_len == 0 or self.bit_len >= 64) return @bitCast(raw);
        // Sign extend
        const sign_bit = raw >> @intCast(self.bit_len - 1);
        if (sign_bit != 0) {
            const mask = (@as(u64, 1) << @intCast(self.bit_len)) - 1;
            return @bitCast(raw | ~mask);
        }
        return @intCast(raw);
    }
};

// ── Label parsing helpers ──────────────────────────────────────────────

const LabelInfo = struct {
    bits: DictKey, // label bits stored here
    len: u16, // number of label bits
};

fn bitLength(m: u16) u16 {
    if (m == 0) return 0;
    var n: u16 = 0;
    var v: u16 = m;
    while (v > 0) : (v >>= 1) {
        n += 1;
    }
    return n;
}

/// Parse an HmLabel from a slice. m = remaining key bits at this level.
fn parseLabel(s: *Slice, m: u16) DictError!LabelInfo {
    const first_bit = s.loadUint(1) catch return error.CellUnderflow;
    if (first_bit == 0) {
        // hml_short$0: unary(n) + n bits
        var n: u16 = 0;
        while (true) {
            const b = s.loadUint(1) catch return error.CellUnderflow;
            if (b == 0) break;
            n += 1;
            if (n > m) return error.InvalidDict;
        }
        var info = LabelInfo{ .bits = .{}, .len = n };
        var i: u16 = 0;
        while (i < n) : (i += 1) {
            const b: u1 = @truncate(s.loadUint(1) catch return error.CellUnderflow);
            info.bits.setBit(i, b);
        }
        return info;
    }
    const second_bit = s.loadUint(1) catch return error.CellUnderflow;
    if (second_bit == 0) {
        // hml_long$10: len_bits(ceil(log2(m+1))) + n bits
        const len_bits = bitLength(m);
        if (len_bits == 0) return LabelInfo{ .bits = .{}, .len = 0 };
        const n: u16 = @intCast(s.loadUint(len_bits) catch return error.CellUnderflow);
        if (n > m) return error.InvalidDict;
        var info = LabelInfo{ .bits = .{}, .len = n };
        var i: u16 = 0;
        while (i < n) : (i += 1) {
            const b: u1 = @truncate(s.loadUint(1) catch return error.CellUnderflow);
            info.bits.setBit(i, b);
        }
        return info;
    }
    // hml_same$11: bit_value + len_bits(ceil(log2(m+1)))
    const bit_val: u1 = @truncate(s.loadUint(1) catch return error.CellUnderflow);
    const len_bits = bitLength(m);
    if (len_bits == 0) return LabelInfo{ .bits = .{}, .len = 0 };
    const n: u16 = @intCast(s.loadUint(len_bits) catch return error.CellUnderflow);
    if (n > m) return error.InvalidDict;
    var info = LabelInfo{ .bits = .{}, .len = n };
    var i: u16 = 0;
    while (i < n) : (i += 1) {
        info.bits.setBit(i, bit_val);
    }
    return info;
}

/// Write label in hml_short encoding: $0 + unary(n) + n bits
fn writeLabel(b: *Builder, key: *const DictKey, offset: u16, n: u16) DictError!void {
    // hml_short: $0
    b.storeUint(0, 1) catch return error.CellOverflow;
    // unary(n): n ones followed by a zero
    var i: u16 = 0;
    while (i < n) : (i += 1) {
        b.storeUint(1, 1) catch return error.CellOverflow;
    }
    b.storeUint(0, 1) catch return error.CellOverflow;
    // n bits of label data
    i = 0;
    while (i < n) : (i += 1) {
        b.storeUint(@as(u64, key.getBit(offset + i)), 1) catch return error.CellOverflow;
    }
}

/// Write label from a LabelInfo (already extracted bits)
fn writeLabelFromInfo(b: *Builder, info: *const LabelInfo) DictError!void {
    b.storeUint(0, 1) catch return error.CellOverflow;
    var i: u16 = 0;
    while (i < info.len) : (i += 1) {
        b.storeUint(1, 1) catch return error.CellOverflow;
    }
    b.storeUint(0, 1) catch return error.CellOverflow;
    i = 0;
    while (i < info.len) : (i += 1) {
        b.storeUint(@as(u64, info.bits.getBit(i)), 1) catch return error.CellOverflow;
    }
}

/// Copy remaining bits and refs from a Slice into a Builder
fn copySliceToBuilder(b: *Builder, s: *Slice) DictError!void {
    var remaining = s.remainingBits();
    while (remaining > 0) {
        const chunk: u16 = @min(remaining, 64);
        const val = s.loadUint(chunk) catch return error.CellUnderflow;
        b.storeUint(val, chunk) catch return error.CellOverflow;
        remaining -= chunk;
    }
    while (s.ref_offset < s.ref_end) {
        const ref = s.loadRef() catch return error.CellUnderflow;
        b.storeRef(ref) catch return error.CellOverflow;
    }
}

// ── dictGet ────────────────────────────────────────────────────────────

/// Look up key in dictionary. Returns value slice if found.
pub fn dictGet(dict: ?*Cell, key: *const DictKey, key_len: u16) DictError!?Slice {
    const root = dict orelse return null;
    return dictGetImpl(root, key, key_len, 0);
}

fn dictGetImpl(node: *Cell, key: *const DictKey, key_len: u16, offset: u16) DictError!?Slice {
    var s = Slice.fromCell(node);
    const remaining = key_len - offset;

    // Parse the edge label
    const label = try parseLabel(&s, remaining);

    // Check that label matches key bits
    if (label.len > remaining) return null;
    var i: u16 = 0;
    while (i < label.len) : (i += 1) {
        if (label.bits.getBit(i) != key.getBit(offset + i)) return null;
    }

    const new_offset = offset + label.len;
    if (new_offset == key_len) {
        // Leaf: remaining slice is the value
        return s;
    }

    // Fork: need to go to child ref
    if (s.remainingRefs() < 2) return error.InvalidDict;
    const dir = key.getBit(new_offset);
    // Load both refs to advance past them, but only use the one we need
    const left = s.loadRef() catch return error.CellUnderflow;
    const right = s.loadRef() catch return error.CellUnderflow;
    const child = if (dir == 0) left else right;
    return dictGetImpl(child, key, key_len, new_offset + 1);
}

// ── dictSet ────────────────────────────────────────────────────────────

/// Insert or update key in dictionary. Returns new root cell.
pub fn dictSet(dict: ?*Cell, key: *const DictKey, key_len: u16, value: *Slice, arena: *CellArena) DictError!*Cell {
    if (dict == null) {
        // Empty dict: create single leaf
        return makeLeaf(key, key_len, 0, key_len, value, arena);
    }
    return dictSetImpl(dict.?, key, key_len, 0, value, arena);
}

fn makeLeaf(key: *const DictKey, key_len: u16, offset: u16, remaining: u16, value: *Slice, arena: *CellArena) DictError!*Cell {
    _ = key_len;
    var b = Builder.init();
    try writeLabel(&b, key, offset, remaining);
    try copySliceToBuilder(&b, value);
    return b.finalize(arena) catch return error.OutOfMemory;
}

fn dictSetImpl(node: *Cell, key: *const DictKey, key_len: u16, offset: u16, value: *Slice, arena: *CellArena) DictError!*Cell {
    var s = Slice.fromCell(node);
    const remaining = key_len - offset;

    const label = try parseLabel(&s, remaining);

    // Find common prefix length between label and key
    const match_len = matchPrefix(key, offset, &label);

    if (match_len < label.len) {
        // Partial match: split edge
        return splitEdge(key, key_len, offset, &label, match_len, &s, value, arena);
    }

    // Full label match
    const new_offset = offset + label.len;
    if (new_offset == key_len) {
        // Replace leaf value
        var b = Builder.init();
        try writeLabel(&b, key, offset, label.len);
        try copySliceToBuilder(&b, value);
        return b.finalize(arena) catch return error.OutOfMemory;
    }

    // Fork: recurse into the appropriate child
    if (s.remainingRefs() < 2) return error.InvalidDict;
    const left = s.loadRef() catch return error.CellUnderflow;
    const right = s.loadRef() catch return error.CellUnderflow;

    const dir = key.getBit(new_offset);
    const updated_child = if (dir == 0)
        try dictSetImpl(left, key, key_len, new_offset + 1, value, arena)
    else
        try dictSetImpl(right, key, key_len, new_offset + 1, value, arena);

    // Rebuild fork with updated child
    var b = Builder.init();
    try writeLabel(&b, key, offset, label.len);
    if (dir == 0) {
        b.storeRef(updated_child) catch return error.CellOverflow;
        b.storeRef(right) catch return error.CellOverflow;
    } else {
        b.storeRef(left) catch return error.CellOverflow;
        b.storeRef(updated_child) catch return error.CellOverflow;
    }
    // Copy any remaining data bits after refs in the original fork
    try copySliceToBuilder(&b, &s);
    return b.finalize(arena) catch return error.OutOfMemory;
}

fn matchPrefix(key: *const DictKey, offset: u16, label: *const LabelInfo) u16 {
    var i: u16 = 0;
    while (i < label.len) : (i += 1) {
        if (key.getBit(offset + i) != label.bits.getBit(i)) return i;
    }
    return label.len;
}

fn splitEdge(key: *const DictKey, key_len: u16, offset: u16, label: *const LabelInfo, match_len: u16, rest: *Slice, value: *Slice, arena: *CellArena) DictError!*Cell {
    // Create the old subtree child (with suffix of old label)
    const old_suffix_start = match_len + 1;
    const old_suffix_len = label.len - old_suffix_start;
    var old_child_b = Builder.init();
    // Write the remaining suffix of the old label
    var old_suffix_label = LabelInfo{ .bits = .{}, .len = old_suffix_len };
    var i: u16 = 0;
    while (i < old_suffix_len) : (i += 1) {
        old_suffix_label.bits.setBit(i, label.bits.getBit(old_suffix_start + i));
    }
    try writeLabelFromInfo(&old_child_b, &old_suffix_label);
    // Copy the rest of the original cell data (value or fork refs)
    var rest_copy = rest.*;
    try copySliceToBuilder(&old_child_b, &rest_copy);
    const old_child = old_child_b.finalize(arena) catch return error.OutOfMemory;

    // Create the new leaf child
    const new_remaining = key_len - (offset + match_len + 1);
    var new_value_copy = value.*;
    const new_child = try makeLeaf(key, key_len, offset + match_len + 1, new_remaining, &new_value_copy, arena);

    // Determine which direction each child goes
    const old_dir = label.bits.getBit(match_len);
    const new_dir = key.getBit(offset + match_len);
    _ = new_dir; // Should be opposite of old_dir

    // Build the fork node with common prefix label
    var fork_b = Builder.init();
    try writeLabel(&fork_b, key, offset, match_len);
    if (old_dir == 0) {
        fork_b.storeRef(old_child) catch return error.CellOverflow;
        fork_b.storeRef(new_child) catch return error.CellOverflow;
    } else {
        fork_b.storeRef(new_child) catch return error.CellOverflow;
        fork_b.storeRef(old_child) catch return error.CellOverflow;
    }
    return fork_b.finalize(arena) catch return error.OutOfMemory;
}

// ── dictDel ────────────────────────────────────────────────────────────

pub const DelResult = struct {
    root: ?*Cell,
    deleted: bool,
};

/// Delete key from dictionary. Returns new root and whether deletion happened.
pub fn dictDel(dict: ?*Cell, key: *const DictKey, key_len: u16, arena: *CellArena) DictError!DelResult {
    const root = dict orelse return .{ .root = null, .deleted = false };
    return dictDelImpl(root, key, key_len, 0, arena);
}

fn dictDelImpl(node: *Cell, key: *const DictKey, key_len: u16, offset: u16, arena: *CellArena) DictError!DelResult {
    var s = Slice.fromCell(node);
    const remaining = key_len - offset;

    const label = try parseLabel(&s, remaining);

    // Check label match
    const match_len = matchPrefix(key, offset, &label);
    if (match_len < label.len) {
        // Label mismatch: key not found
        return .{ .root = node, .deleted = false };
    }

    const new_offset = offset + label.len;
    if (new_offset == key_len) {
        // Found the leaf to delete
        return .{ .root = null, .deleted = true };
    }

    // Fork: recurse into child
    if (s.remainingRefs() < 2) return .{ .root = node, .deleted = false };
    const left = s.loadRef() catch return error.CellUnderflow;
    const right = s.loadRef() catch return error.CellUnderflow;

    const dir = key.getBit(new_offset);
    const target = if (dir == 0) left else right;
    const other = if (dir == 0) right else left;

    const result = try dictDelImpl(target, key, key_len, new_offset + 1, arena);
    if (!result.deleted) return .{ .root = node, .deleted = false };

    if (result.root == null) {
        // Child was deleted entirely: collapse the surviving child
        // Merge parent_label + direction_bit(other_dir) + child_label
        return .{ .root = try mergeChild(key, offset, &label, 1 - dir, other, arena), .deleted = true };
    }

    // Rebuild fork with updated child
    var b = Builder.init();
    try writeLabel(&b, key, offset, label.len);
    if (dir == 0) {
        b.storeRef(result.root.?) catch return error.CellOverflow;
        b.storeRef(right) catch return error.CellOverflow;
    } else {
        b.storeRef(left) catch return error.CellOverflow;
        b.storeRef(result.root.?) catch return error.CellOverflow;
    }
    try copySliceToBuilder(&b, &s);
    return .{ .root = b.finalize(arena) catch return error.OutOfMemory, .deleted = true };
}

/// Merge a parent label + direction bit + child label into a single edge node.
fn mergeChild(_: *const DictKey, _: u16, parent_label: *const LabelInfo, child_dir: u1, child: *Cell, arena: *CellArena) DictError!*Cell {
    var child_s = Slice.fromCell(child);
    const child_remaining = child_s.cell.bit_len; // approximation; parse actual label
    // We need to parse the child's label to merge
    // The child is at the level after parent_label + 1 direction bit
    // We don't know the exact remaining key_len, but we can parse hml_short
    // by just reading the child slice

    // Save child slice state to parse its label
    var child_parse = Slice.fromCell(child);
    // We need the remaining bits at the child level. Since the child was
    // one level below the fork, and we're going to merge it up, we can
    // just read the label and reconstruct.

    // Attempt to parse child label - we need the 'm' parameter.
    // The child was at depth (offset + parent_label.len + 1), so
    // remaining at child level = total_key_len - offset - parent_label.len - 1
    // But we don't have total_key_len here easily.
    // Instead, use a simpler approach: read the raw child cell bits.

    // Build merged label: parent_label bits + child_dir bit + child's raw content
    _ = child_remaining;
    var b = Builder.init();

    // Build the merged label manually
    // First, construct the merged label bits
    var merged_label = LabelInfo{ .bits = .{}, .len = parent_label.len + 1 };
    var i: u16 = 0;
    while (i < parent_label.len) : (i += 1) {
        merged_label.bits.setBit(i, parent_label.bits.getBit(i));
    }
    merged_label.bits.setBit(parent_label.len, child_dir);

    // Now we need to read the child's label and append it
    // Parse child label with a reasonable m value
    // The child's m is whatever remains after parent+1; to parse hml_short we
    // just need m >= actual label length. Use 1023 as safe upper bound.
    const child_label = parseLabel(&child_parse, 1023) catch {
        // If parsing fails, just write what we have and copy the rest raw
        try writeLabelFromInfo(&b, &merged_label);
        try copySliceToBuilder(&b, &child_s);
        return b.finalize(arena) catch return error.OutOfMemory;
    };

    // Extend merged label with child's label
    const total_len = merged_label.len + child_label.len;
    merged_label.len = total_len;
    i = 0;
    while (i < child_label.len) : (i += 1) {
        merged_label.bits.setBit(parent_label.len + 1 + i, child_label.bits.getBit(i));
    }

    try writeLabelFromInfo(&b, &merged_label);
    // Copy child's remaining data (value or refs after label)
    try copySliceToBuilder(&b, &child_parse);
    return b.finalize(arena) catch return error.OutOfMemory;
}

// ── Slice-to-DictKey helper ────────────────────────────────────────────

pub fn sliceToDictKey(s: *Slice, n: u16) DictError!DictKey {
    var key = DictKey{ .bit_len = n };
    var i: u16 = 0;
    while (i < n) : (i += 1) {
        const b: u1 = @truncate(s.loadUint(1) catch return error.CellUnderflow);
        key.setBit(i, b);
    }
    return key;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "DictKey fromUint/toUint round-trip" {
    const key = DictKey.fromUint(42, 8);
    try std.testing.expectEqual(@as(u64, 42), key.toUint());
    try std.testing.expectEqual(@as(u16, 8), key.bit_len);
}

test "DictKey fromInt/toInt round-trip" {
    const key = DictKey.fromInt(-1, 8);
    try std.testing.expectEqual(@as(i64, -1), key.toInt());

    const key2 = DictKey.fromInt(42, 8);
    try std.testing.expectEqual(@as(i64, 42), key2.toInt());

    const key3 = DictKey.fromInt(-128, 8);
    try std.testing.expectEqual(@as(i64, -128), key3.toInt());
}

test "DictKey getBit/setBit" {
    var key = DictKey{ .bit_len = 8 };
    key.setBit(0, 1);
    key.setBit(7, 1);
    try std.testing.expectEqual(@as(u1, 1), key.getBit(0));
    try std.testing.expectEqual(@as(u1, 0), key.getBit(1));
    try std.testing.expectEqual(@as(u1, 1), key.getBit(7));
}

test "empty dict get returns null" {
    const result = try dictGet(null, &DictKey.fromUint(0, 8), 8);
    try std.testing.expect(result == null);
}

test "dict set then get single key" {
    var arena = CellArena.init();

    // Create a value cell
    var vb = Builder.init();
    vb.storeUint(0xCAFE, 16) catch unreachable;
    const vc = vb.finalize(&arena) catch unreachable;
    var vs = Slice.fromCell(vc);

    const key = DictKey.fromUint(5, 8);
    const root = try dictSet(null, &key, 8, &vs, &arena);

    // Get it back
    const result = try dictGet(root, &key, 8);
    try std.testing.expect(result != null);
    var result_s = result.?;
    const val = result_s.loadUint(16) catch unreachable;
    try std.testing.expectEqual(@as(u64, 0xCAFE), val);
}

test "dict set multiple keys and get each" {
    var arena = CellArena.init();

    var root: ?*Cell = null;

    // Insert key=1 -> value=100
    var vb1 = Builder.init();
    vb1.storeUint(100, 16) catch unreachable;
    const vc1 = vb1.finalize(&arena) catch unreachable;
    var vs1 = Slice.fromCell(vc1);
    const key1 = DictKey.fromUint(1, 8);
    root = try dictSet(root, &key1, 8, &vs1, &arena);

    // Insert key=2 -> value=200
    var vb2 = Builder.init();
    vb2.storeUint(200, 16) catch unreachable;
    const vc2 = vb2.finalize(&arena) catch unreachable;
    var vs2 = Slice.fromCell(vc2);
    const key2 = DictKey.fromUint(2, 8);
    root = try dictSet(root, &key2, 8, &vs2, &arena);

    // Insert key=3 -> value=300
    var vb3 = Builder.init();
    vb3.storeUint(300, 16) catch unreachable;
    const vc3 = vb3.finalize(&arena) catch unreachable;
    var vs3 = Slice.fromCell(vc3);
    const key3 = DictKey.fromUint(3, 8);
    root = try dictSet(root, &key3, 8, &vs3, &arena);

    // Get each key
    {
        const r = try dictGet(root, &key1, 8);
        try std.testing.expect(r != null);
        var rs = r.?;
        try std.testing.expectEqual(@as(u64, 100), rs.loadUint(16) catch unreachable);
    }
    {
        const r = try dictGet(root, &key2, 8);
        try std.testing.expect(r != null);
        var rs = r.?;
        try std.testing.expectEqual(@as(u64, 200), rs.loadUint(16) catch unreachable);
    }
    {
        const r = try dictGet(root, &key3, 8);
        try std.testing.expect(r != null);
        var rs = r.?;
        try std.testing.expectEqual(@as(u64, 300), rs.loadUint(16) catch unreachable);
    }

    // Non-existent key
    const key_missing = DictKey.fromUint(99, 8);
    const r_miss = try dictGet(root, &key_missing, 8);
    try std.testing.expect(r_miss == null);
}

test "dict overwrite existing key" {
    var arena = CellArena.init();

    const key = DictKey.fromUint(7, 8);

    // Insert value=111
    var vb1 = Builder.init();
    vb1.storeUint(111, 16) catch unreachable;
    const vc1 = vb1.finalize(&arena) catch unreachable;
    var vs1 = Slice.fromCell(vc1);
    var root = try dictSet(null, &key, 8, &vs1, &arena);

    // Overwrite with value=222
    var vb2 = Builder.init();
    vb2.storeUint(222, 16) catch unreachable;
    const vc2 = vb2.finalize(&arena) catch unreachable;
    var vs2 = Slice.fromCell(vc2);
    root = try dictSet(root, &key, 8, &vs2, &arena);

    const result = try dictGet(root, &key, 8);
    try std.testing.expect(result != null);
    var rs = result.?;
    try std.testing.expectEqual(@as(u64, 222), rs.loadUint(16) catch unreachable);
}

test "dict delete from single-element dict" {
    var arena = CellArena.init();

    const key = DictKey.fromUint(5, 8);
    var vb = Builder.init();
    vb.storeUint(0xBEEF, 16) catch unreachable;
    const vc = vb.finalize(&arena) catch unreachable;
    var vs = Slice.fromCell(vc);
    const root = try dictSet(null, &key, 8, &vs, &arena);

    const del_result = try dictDel(root, &key, 8, &arena);
    try std.testing.expect(del_result.deleted);
    try std.testing.expect(del_result.root == null);
}

test "dict delete non-existent key" {
    var arena = CellArena.init();

    const key = DictKey.fromUint(5, 8);
    var vb = Builder.init();
    vb.storeUint(0xBEEF, 16) catch unreachable;
    const vc = vb.finalize(&arena) catch unreachable;
    var vs = Slice.fromCell(vc);
    const root = try dictSet(null, &key, 8, &vs, &arena);

    const missing_key = DictKey.fromUint(99, 8);
    const del_result = try dictDel(root, &missing_key, 8, &arena);
    try std.testing.expect(!del_result.deleted);
    try std.testing.expect(del_result.root != null);

    // Original key still accessible
    const r = try dictGet(del_result.root, &key, 8);
    try std.testing.expect(r != null);
}

test "dict delete causing fork collapse" {
    var arena = CellArena.init();

    var root: ?*Cell = null;

    // Insert two keys
    const key1 = DictKey.fromUint(1, 8);
    var vb1 = Builder.init();
    vb1.storeUint(100, 16) catch unreachable;
    const vc1 = vb1.finalize(&arena) catch unreachable;
    var vs1 = Slice.fromCell(vc1);
    root = try dictSet(root, &key1, 8, &vs1, &arena);

    const key2 = DictKey.fromUint(2, 8);
    var vb2 = Builder.init();
    vb2.storeUint(200, 16) catch unreachable;
    const vc2 = vb2.finalize(&arena) catch unreachable;
    var vs2 = Slice.fromCell(vc2);
    root = try dictSet(root, &key2, 8, &vs2, &arena);

    // Delete key1 - should collapse fork, leaving key2 as the only entry
    const del_result = try dictDel(root, &key1, 8, &arena);
    try std.testing.expect(del_result.deleted);
    try std.testing.expect(del_result.root != null);

    // key2 should still be accessible
    const r = try dictGet(del_result.root, &key2, 8);
    try std.testing.expect(r != null);
    var rs = r.?;
    try std.testing.expectEqual(@as(u64, 200), rs.loadUint(16) catch unreachable);

    // key1 should be gone
    const r1 = try dictGet(del_result.root, &key1, 8);
    try std.testing.expect(r1 == null);
}

test "bitLength" {
    try std.testing.expectEqual(@as(u16, 0), bitLength(0));
    try std.testing.expectEqual(@as(u16, 1), bitLength(1));
    try std.testing.expectEqual(@as(u16, 2), bitLength(2));
    try std.testing.expectEqual(@as(u16, 2), bitLength(3));
    try std.testing.expectEqual(@as(u16, 3), bitLength(4));
    try std.testing.expectEqual(@as(u16, 8), bitLength(255));
}

// ── Edge-case tests ────────────────────────────────────────────────────

fn makeValue(arena: *CellArena, val: u64) Slice {
    var vb = Builder.init();
    vb.storeUint(val, 16) catch unreachable;
    const vc = vb.finalize(arena) catch unreachable;
    return Slice.fromCell(vc);
}

fn getValue(maybe_s: ?Slice) ?u64 {
    var s = maybe_s orelse return null;
    return s.loadUint(16) catch null;
}

test "dict with 1-bit key width" {
    var arena = CellArena.init();

    // Only two possible keys: 0 and 1
    const key0 = DictKey.fromUint(0, 1);
    const key1 = DictKey.fromUint(1, 1);

    var vs0 = makeValue(&arena, 0xAA);
    var root = try dictSet(null, &key0, 1, &vs0, &arena);

    var vs1 = makeValue(&arena, 0xBB);
    root = try dictSet(root, &key1, 1, &vs1, &arena);

    try std.testing.expectEqual(@as(u64, 0xAA), getValue(try dictGet(root, &key0, 1)).?);
    try std.testing.expectEqual(@as(u64, 0xBB), getValue(try dictGet(root, &key1, 1)).?);
}

test "dict with zero key" {
    var arena = CellArena.init();

    const key = DictKey.fromUint(0, 8);
    var vs = makeValue(&arena, 0xDEAD);
    const root = try dictSet(null, &key, 8, &vs, &arena);

    try std.testing.expectEqual(@as(u64, 0xDEAD), getValue(try dictGet(root, &key, 8)).?);
}

test "dict with max key (0xFF for 8-bit)" {
    var arena = CellArena.init();

    const key = DictKey.fromUint(0xFF, 8);
    var vs = makeValue(&arena, 0xBEEF);
    const root = try dictSet(null, &key, 8, &vs, &arena);

    try std.testing.expectEqual(@as(u64, 0xBEEF), getValue(try dictGet(root, &key, 8)).?);
}

test "dict with signed negative key" {
    var arena = CellArena.init();

    const key_neg = DictKey.fromInt(-1, 8);
    const key_pos = DictKey.fromInt(1, 8);

    var vs_neg = makeValue(&arena, 111);
    var root = try dictSet(null, &key_neg, 8, &vs_neg, &arena);

    var vs_pos = makeValue(&arena, 222);
    root = try dictSet(root, &key_pos, 8, &vs_pos, &arena);

    try std.testing.expectEqual(@as(u64, 111), getValue(try dictGet(root, &key_neg, 8)).?);
    try std.testing.expectEqual(@as(u64, 222), getValue(try dictGet(root, &key_pos, 8)).?);
}

test "dict keys sharing long common prefix" {
    var arena = CellArena.init();

    // 0b00000000 and 0b00000001 share 7-bit prefix
    const key0 = DictKey.fromUint(0, 8);
    const key1 = DictKey.fromUint(1, 8);

    var vs0 = makeValue(&arena, 10);
    var root = try dictSet(null, &key0, 8, &vs0, &arena);

    var vs1 = makeValue(&arena, 11);
    root = try dictSet(root, &key1, 8, &vs1, &arena);

    try std.testing.expectEqual(@as(u64, 10), getValue(try dictGet(root, &key0, 8)).?);
    try std.testing.expectEqual(@as(u64, 11), getValue(try dictGet(root, &key1, 8)).?);
}

test "dict delete from 3-key dict leaves 2 intact" {
    var arena = CellArena.init();

    const key1 = DictKey.fromUint(10, 8);
    const key2 = DictKey.fromUint(20, 8);
    const key3 = DictKey.fromUint(30, 8);

    var vs1 = makeValue(&arena, 100);
    var root: ?*Cell = try dictSet(null, &key1, 8, &vs1, &arena);
    var vs2 = makeValue(&arena, 200);
    root = try dictSet(root, &key2, 8, &vs2, &arena);
    var vs3 = makeValue(&arena, 300);
    root = try dictSet(root, &key3, 8, &vs3, &arena);

    // Delete middle key
    const del = try dictDel(root, &key2, 8, &arena);
    try std.testing.expect(del.deleted);

    // Remaining keys still work
    try std.testing.expectEqual(@as(u64, 100), getValue(try dictGet(del.root, &key1, 8)).?);
    try std.testing.expect((try dictGet(del.root, &key2, 8)) == null);
    try std.testing.expectEqual(@as(u64, 300), getValue(try dictGet(del.root, &key3, 8)).?);
}

test "dict delete all keys yields empty dict" {
    var arena = CellArena.init();

    const key1 = DictKey.fromUint(0xAA, 8);
    const key2 = DictKey.fromUint(0x55, 8);

    var vs1 = makeValue(&arena, 1);
    var root: ?*Cell = try dictSet(null, &key1, 8, &vs1, &arena);
    var vs2 = makeValue(&arena, 2);
    root = try dictSet(root, &key2, 8, &vs2, &arena);

    const del1 = try dictDel(root, &key1, 8, &arena);
    try std.testing.expect(del1.deleted);
    const del2 = try dictDel(del1.root, &key2, 8, &arena);
    try std.testing.expect(del2.deleted);
    try std.testing.expect(del2.root == null);
}

test "dict delete from empty dict is no-op" {
    var arena = CellArena.init();
    const key = DictKey.fromUint(42, 8);
    const result = try dictDel(null, &key, 8, &arena);
    try std.testing.expect(!result.deleted);
    try std.testing.expect(result.root == null);
}

test "dict overwrite preserves other keys" {
    var arena = CellArena.init();

    const key1 = DictKey.fromUint(1, 8);
    const key2 = DictKey.fromUint(2, 8);

    var vs1 = makeValue(&arena, 100);
    var root: ?*Cell = try dictSet(null, &key1, 8, &vs1, &arena);
    var vs2 = makeValue(&arena, 200);
    root = try dictSet(root, &key2, 8, &vs2, &arena);

    // Overwrite key1
    var vs1_new = makeValue(&arena, 999);
    root = try dictSet(root, &key1, 8, &vs1_new, &arena);

    try std.testing.expectEqual(@as(u64, 999), getValue(try dictGet(root, &key1, 8)).?);
    try std.testing.expectEqual(@as(u64, 200), getValue(try dictGet(root, &key2, 8)).?);
}

test "dict 16-bit keys" {
    var arena = CellArena.init();

    const key1 = DictKey.fromUint(0x1234, 16);
    const key2 = DictKey.fromUint(0x5678, 16);
    const key3 = DictKey.fromUint(0x1235, 16); // shares 15-bit prefix with key1

    var vs1 = makeValue(&arena, 0xA);
    var root: ?*Cell = try dictSet(null, &key1, 16, &vs1, &arena);
    var vs2 = makeValue(&arena, 0xB);
    root = try dictSet(root, &key2, 16, &vs2, &arena);
    var vs3 = makeValue(&arena, 0xC);
    root = try dictSet(root, &key3, 16, &vs3, &arena);

    try std.testing.expectEqual(@as(u64, 0xA), getValue(try dictGet(root, &key1, 16)).?);
    try std.testing.expectEqual(@as(u64, 0xB), getValue(try dictGet(root, &key2, 16)).?);
    try std.testing.expectEqual(@as(u64, 0xC), getValue(try dictGet(root, &key3, 16)).?);
}

test "sliceToDictKey" {
    var arena = CellArena.init();
    var b = Builder.init();
    b.storeUint(0b10110000, 8) catch unreachable;
    const c = b.finalize(&arena) catch unreachable;
    var s = Slice.fromCell(c);

    const key = try sliceToDictKey(&s, 5);
    try std.testing.expectEqual(@as(u16, 5), key.bit_len);
    try std.testing.expectEqual(@as(u1, 1), key.getBit(0));
    try std.testing.expectEqual(@as(u1, 0), key.getBit(1));
    try std.testing.expectEqual(@as(u1, 1), key.getBit(2));
    try std.testing.expectEqual(@as(u1, 1), key.getBit(3));
    try std.testing.expectEqual(@as(u1, 0), key.getBit(4));
}

test "DictKey fromUint 16-bit round-trip" {
    const key = DictKey.fromUint(0xABCD, 16);
    try std.testing.expectEqual(@as(u64, 0xABCD), key.toUint());
}

test "DictKey fromInt boundary values" {
    // Min signed 8-bit
    const k_min = DictKey.fromInt(-128, 8);
    try std.testing.expectEqual(@as(i64, -128), k_min.toInt());

    // Max signed 8-bit
    const k_max = DictKey.fromInt(127, 8);
    try std.testing.expectEqual(@as(i64, 127), k_max.toInt());

    // Zero
    const k_zero = DictKey.fromInt(0, 8);
    try std.testing.expectEqual(@as(i64, 0), k_zero.toInt());

    // 16-bit boundary
    const k16 = DictKey.fromInt(-32768, 16);
    try std.testing.expectEqual(@as(i64, -32768), k16.toInt());
}
