const std = @import("std");
const tvm_mod = @import("tvm.zig");
const cell = @import("cell.zig");

const TVM = tvm_mod.TVM;
const TvmError = tvm_mod.TvmError;
const Value = tvm_mod.Value;
const Int257 = cell.Int257;
const Slice = cell.Slice;
const Builder = cell.Builder;
const Continuation = tvm_mod.Continuation;
const Tuple = tvm_mod.Tuple;

const Handler = *const fn (*TVM, u32) TvmError!void;

// ── Dispatch Table (comptime-generated) ────────────────────────────────

const dispatch_l0: [256]Handler = blk: {
    var t: [256]Handler = [_]Handler{&op_invalid} ** 256;

    // 0x00: NOP
    t[0x00] = &op_nop;

    // 0x01-0x0F: XCHG s0, s(i)
    for (0x01..0x10) |i| t[i] = &op_xchg_s0;

    // 0x10-0x1F: XCHG s1, s(i)
    for (0x10..0x20) |i| t[i] = &op_xchg_s1;

    // 0x20-0x2F: PUSH s(i)
    for (0x20..0x30) |i| t[i] = &op_push;

    // 0x30-0x3F: POP s(i)
    for (0x30..0x40) |i| t[i] = &op_pop;

    // 0x40-0x4F: XCHG s0, s(i) extended via next byte — simplified: XCHG3/XCHG2/XCPU/PUXC
    for (0x40..0x50) |i| t[i] = &op_stack_complex;

    // 0x50: XCHG s0, s(ii) with next byte
    t[0x50] = &op_xchg_long;
    // 0x51: XCHG s1, s(ii)
    t[0x51] = &op_xchg_s1_long;
    // 0x52: PUSH s(ii)
    t[0x52] = &op_push_long;
    // 0x53: POP s(ii)
    t[0x53] = &op_pop_long;

    // 0x54: OVER (PUSH s1)
    t[0x54] = &op_over;
    // 0x55..0x57: multi-stack complex ops
    t[0x55] = &op_nop; // BLKSWAP2 etc (simplified)
    t[0x56] = &op_pick; // PICK
    t[0x57] = &op_roll_op;

    // 0x58: ROT
    t[0x58] = &op_rot;
    // 0x59: ROTREV (-ROT)
    t[0x59] = &op_rotrev;
    // 0x5A: SWAP2 (2SWAP)
    t[0x5A] = &op_swap2;
    // 0x5B: DROP2 (2DROP)
    t[0x5B] = &op_drop2;
    // 0x5C: DUP2 (2DUP)
    t[0x5C] = &op_dup2;
    // 0x5D: OVER2 (2OVER)
    t[0x5D] = &op_over2;

    // 0x5E: REVERSE i,j (next byte: high=i, low=j)
    t[0x5E] = &op_reverse;

    // 0x5F: BLKDROP with next byte
    t[0x5F] = &op_blkdrop_ext;

    // 0x60: DEPTH
    t[0x60] = &op_depth;

    // 0x61: CHKDEPTH
    t[0x61] = &op_chkdepth;

    // 0x62: ONLYTOP
    t[0x62] = &op_onlytop;

    // 0x63: ONLYX
    t[0x63] = &op_nop;

    // 0x64-0x6B: BLKDROP/BLKPUSH/BLKSWAP with embedded args
    for (0x64..0x6C) |i| t[i] = &op_blk_ops;

    // 0x6C: PUSH with next byte embedded continuation ref
    t[0x6C] = &op_nop;

    // 0x6D: Tuple operations prefix
    t[0x6D] = &op_tuple_prefix;

    // 0x6E-0x6F: reserved
    t[0x6E] = &op_nop;
    t[0x6F] = &op_nop;

    // 0x70: PUSHINT_4 (tiny) — 0x7i pushes i (0-15)
    for (0x70..0x80) |i| t[i] = &op_pushint_tiny;

    // 0x80: PUSHINT_8 (next byte, signed)
    t[0x80] = &op_pushint_8;
    // 0x81: PUSHINT_16
    t[0x81] = &op_pushint_16;

    // 0x82: PUSHINT_long (next byte = length, then data)
    t[0x82] = &op_pushint_long;

    // 0x83: PUSHPOW2 (next byte n, push 2^(n+1))
    t[0x83] = &op_pushpow2;

    // 0x84: PUSHNAN — simplified
    t[0x84] = &op_nop;

    // 0x85: PUSHPOW2DEC (2^(n+1) - 1)
    t[0x85] = &op_pushpow2dec;

    // 0x86: PUSHNEGPOW2 (-2^(n+1))
    t[0x86] = &op_pushnegpow2;

    // 0x88: PUSHREF
    t[0x88] = &op_pushref;

    // 0x89: PUSHREFSLICE
    t[0x89] = &op_pushrefslice;

    // 0x8A: PUSHREFCONT
    t[0x8A] = &op_pushrefcont;

    // 0x8B: PUSHSLICE short
    t[0x8B] = &op_pushslice_short;

    // 0x8C-0x8D: PUSHSLICE medium (simplified)
    t[0x8C] = &op_pushslice_mid;
    t[0x8D] = &op_pushslice_mid;

    // 0x8E-0x8F: PUSHCONT (inline continuation)
    t[0x8E] = &op_pushcont_short;
    t[0x8F] = &op_pushcont_short;

    // 0x90-0x9F: SETCP/ADDCP etc — simplified
    for (0x90..0xA0) |i| t[i] = &op_nop;

    // ── Arithmetic ─────────────────────────────────────────
    // 0xA0: ADD
    t[0xA0] = &op_add;
    // 0xA1: SUB
    t[0xA1] = &op_sub;
    // 0xA2: SUBR
    t[0xA2] = &op_subr;
    // 0xA3: NEGATE
    t[0xA3] = &op_negate;
    // 0xA4: INC
    t[0xA4] = &op_inc;
    // 0xA5: DEC
    t[0xA5] = &op_dec;
    // 0xA6: MUL
    t[0xA6] = &op_mul;

    // 0xA7: reserved/extended arithmetic prefix
    t[0xA7] = &op_nop;

    // 0xA8: ABS
    // Note: In TVM spec, this might be under A6xx prefix, but we place it here for simplicity
    t[0xA8] = &op_abs;

    // 0xA9: DIV prefix (multi-byte)
    t[0xA9] = &op_div_prefix;

    // 0xAA: ADDCONST (next byte, signed)
    t[0xAA] = &op_addconst;
    // 0xAB: MULCONST
    t[0xAB] = &op_mulconst;

    // 0xAC: LSHIFT (next byte = shift amount)
    t[0xAC] = &op_lshift;
    // 0xAD: RSHIFT
    t[0xAD] = &op_rshift;

    // 0xAE: LSHIFT var (shift amount from stack)
    t[0xAE] = &op_lshift_var;
    // 0xAF: RSHIFT var
    t[0xAF] = &op_rshift_var;

    // ── Comparison ─────────────────────────────────────────
    // 0xB0: SGN
    t[0xB0] = &op_sgn;
    // 0xB1: LESS
    t[0xB1] = &op_less;
    // 0xB2: EQUAL
    t[0xB2] = &op_equal;
    // 0xB3: LEQ
    t[0xB3] = &op_leq;
    // 0xB4: GREATER
    t[0xB4] = &op_greater;
    // 0xB5: GEQ
    t[0xB5] = &op_geq;
    // 0xB6: CMP
    t[0xB6] = &op_cmp;
    // 0xB7: logic prefix (AND/OR/XOR/NOT)
    t[0xB7] = &op_logic_prefix;
    // 0xB8: EQINT (next byte signed)
    t[0xB8] = &op_eqint;
    // 0xB9: LESSINT
    t[0xB9] = &op_lessint;
    // 0xBA: GTINT
    t[0xBA] = &op_gtint;
    // 0xBB: NEQINT
    t[0xBB] = &op_neqint;

    // 0xBC: ISNAN
    t[0xBC] = &op_nop;
    // 0xBD: CHKNAN
    t[0xBD] = &op_nop;

    // ── 0xBE-0xBF reserved ─────────────────────────────────
    t[0xBE] = &op_nop;
    t[0xBF] = &op_nop;

    // ── 0xC0-0xC7: various constant/config ops ────────────
    for (0xC0..0xC8) |i| t[i] = &op_nop;

    // ── Cell operations ────────────────────────────────────
    // 0xC8: NEWC
    t[0xC8] = &op_newc;
    // 0xC9: ENDC
    t[0xC9] = &op_endc;
    // 0xCA: STI/STU prefix (next byte selects variant)
    t[0xCA] = &op_sti_stu;
    // 0xCB: STREF
    t[0xCB] = &op_stref;
    // 0xCC: ENDCST / STSLICE
    t[0xCC] = &op_stslice;
    // 0xCD: STIX/STUX (variable length store)
    t[0xCD] = &op_stix;
    // 0xCE: STSLICER
    t[0xCE] = &op_nop;
    // 0xCF: cell serialization prefix
    t[0xCF] = &op_nop;

    // 0xD0: CTOS (cell to slice)
    t[0xD0] = &op_ctos;
    // 0xD1: LDI/LDU prefix
    t[0xD1] = &op_ldi_ldu;
    // 0xD2: LDIX/LDUX (variable-length load)
    t[0xD2] = &op_ldix;
    // 0xD3: PLDIX/PLDUX (preload, don't advance)
    t[0xD3] = &op_nop;
    // 0xD4: LDREF
    t[0xD4] = &op_ldref;
    // 0xD5: LDSLICE
    t[0xD5] = &op_ldslice;

    // 0xD6-0xD7: LDDICT / SKIPDICT / cell query ops
    t[0xD6] = &op_nop;
    t[0xD7] = &op_cell_query;

    // ── Control flow ───────────────────────────────────────
    // 0xD8: EXECUTE/CALLX
    t[0xD8] = &op_execute;
    // 0xD9: JMPX
    t[0xD9] = &op_jmpx;
    // 0xDA: prefix for CALLXARGS etc
    t[0xDA] = &op_callx_prefix;
    // 0xDB: prefix for more control flow
    t[0xDB] = &op_control_prefix;

    // 0xDC: IF
    t[0xDC] = &op_if;
    // 0xDD: IFNOT
    t[0xDD] = &op_ifnot;
    // 0xDE: IFJMP
    t[0xDE] = &op_ifjmp;
    // 0xDF: IFNOTJMP
    t[0xDF] = &op_ifnotjmp;

    // 0xE0: IFELSE
    t[0xE0] = &op_ifelse;

    // 0xE1-0xE3: IFREF, IFNOTREF, IFELSEREF
    t[0xE1] = &op_nop;
    t[0xE2] = &op_nop;
    t[0xE3] = &op_nop;

    // 0xE4: REPEAT
    t[0xE4] = &op_repeat;
    // 0xE5: REPEATEND (simplified)
    t[0xE5] = &op_nop;
    // 0xE6: UNTIL
    t[0xE6] = &op_until;
    // 0xE7: UNTILEND
    t[0xE7] = &op_nop;
    // 0xE8: WHILE
    t[0xE8] = &op_while;
    // 0xE9: WHILEEND
    t[0xE9] = &op_nop;
    // 0xEA: AGAIN
    t[0xEA] = &op_again;
    // 0xEB: AGAINEND
    t[0xEB] = &op_nop;

    // 0xEC-0xED: SETCONTARGS/RETURNARGS
    t[0xEC] = &op_nop;
    t[0xED] = &op_cont_prefix;

    // 0xEE-0xEF: reserved
    t[0xEE] = &op_nop;
    t[0xEF] = &op_nop;

    // ── 0xF0: dictionary ops prefix ────────────────────────
    t[0xF0] = &op_dict_prefix;
    t[0xF1] = &op_dict_prefix;

    // 0xF2: exception handling prefix
    t[0xF2] = &op_throw_prefix;
    // 0xF3: exception prefix 2
    t[0xF3] = &op_nop;

    // 0xF4-0xF7: reserved/dict/debug
    for (0xF4..0xF8) |i| t[i] = &op_nop;

    // 0xF8-0xFB: reserved
    for (0xF8..0xFC) |i| t[i] = &op_nop;

    // 0xFC-0xFD: reserved
    t[0xFC] = &op_nop;
    t[0xFD] = &op_nop;

    // 0xFE: DEBUG
    t[0xFE] = &op_debug;

    // 0xFF: SETCP / special (exit)
    t[0xFF] = &op_setcp_special;

    break :blk t;
};

/// Public dispatch function called by TVM execution loop
pub fn dispatch(vm: *TVM, byte0: u32) TvmError!void {
    return dispatch_l0[byte0 & 0xFF](vm, byte0);
}

// ── NOP / Invalid ──────────────────────────────────────────────────────

fn op_nop(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
}

fn op_invalid(_: *TVM, _: u32) TvmError!void {
    return error.InvalidOpcode;
}

// ── Stack Manipulation ─────────────────────────────────────────────────

fn op_xchg_s0(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const i = byte0 & 0x0F;
    try vm.stack.xchg(0, i);
}

fn op_xchg_s1(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const i = byte0 & 0x0F;
    try vm.stack.xchg(1, i);
}

fn op_push(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const i = byte0 & 0x0F;
    const val = try vm.stack.peek(i);
    try vm.stack.push(val);
}

fn op_pop(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const i = byte0 & 0x0F;
    if (i == 0) {
        _ = try vm.stack.pop();
    } else {
        const val = try vm.stack.pop();
        // s(i) after pop is at index i-1 in the original numbering
        if (i - 1 >= vm.stack.depth) return error.StackUnderflow;
        vm.stack.items[vm.stack.depth - i] = val;
    }
}

fn op_stack_complex(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    // 0x4ijk style triple exchanges - simplified
    const next = try vm.fetchUint(8);
    const i = (byte0 & 0x0F);
    const j = (next >> 4) & 0x0F;
    const k = next & 0x0F;
    try vm.stack.xchg(0, @intCast(i));
    try vm.stack.xchg(0, @intCast(j));
    try vm.stack.xchg(0, @intCast(k));
}

fn op_xchg_long(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const i = try vm.fetchUint(8);
    try vm.stack.xchg(0, @intCast(i));
}

fn op_xchg_s1_long(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const i = try vm.fetchUint(8);
    try vm.stack.xchg(1, @intCast(i));
}

fn op_push_long(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const i = try vm.fetchUint(8);
    const val = try vm.stack.peek(@intCast(i));
    try vm.stack.push(val);
}

fn op_pop_long(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const i: u32 = @intCast(try vm.fetchUint(8));
    if (i == 0) {
        _ = try vm.stack.pop();
    } else {
        const val = try vm.stack.pop();
        if (i - 1 >= vm.stack.depth) return error.StackUnderflow;
        vm.stack.items[vm.stack.depth - i] = val;
    }
}

fn op_over(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const val = try vm.stack.peek(1);
    try vm.stack.push(val);
}

fn op_pick(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    // PICK: index from stack top
    const idx_val = try (try vm.stack.pop()).asInt();
    const idx = idx_val.toI64();
    if (idx < 0) return error.IntegerOutOfRange;
    const val = try vm.stack.peek(@intCast(idx));
    try vm.stack.push(val);
}

fn op_roll_op(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    if (sub == 0) {
        // ROLL
        const n_val = try (try vm.stack.pop()).asInt();
        const n = n_val.toI64();
        if (n < 0) return error.IntegerOutOfRange;
        try vm.stack.roll(@intCast(n));
    } else {
        // ROLLREV
        const n_val = try (try vm.stack.pop()).asInt();
        const n = n_val.toI64();
        if (n < 0) return error.IntegerOutOfRange;
        try vm.stack.rollRev(@intCast(n));
    }
}

fn op_rot(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.roll(2); // ROT = move s(2) to top
}

fn op_rotrev(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.rollRev(2);
}

fn op_swap2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.blkswap(2, 2);
}

fn op_drop2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.blkdrop(2);
}

fn op_dup2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try vm.stack.peek(1);
    const b = try vm.stack.peek(0);
    try vm.stack.push(a);
    try vm.stack.push(b);
}

fn op_over2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try vm.stack.peek(3);
    const b = try vm.stack.peek(2);
    try vm.stack.push(a);
    try vm.stack.push(b);
}

fn op_reverse(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const args = try vm.fetchUint(8);
    const i: u32 = @intCast((args >> 4) & 0x0F);
    const j: u32 = @intCast(args & 0x0F);
    if (i + j + 2 > vm.stack.depth) return error.StackUnderflow;
    vm.stack.reverseRange(vm.stack.depth - i - j - 2, vm.stack.depth - j);
}

fn op_blkdrop_ext(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const args = try vm.fetchUint(8);
    const n: u32 = @intCast((args >> 4) & 0x0F);
    _ = @as(u32, @intCast(args & 0x0F));
    try vm.stack.blkdrop(n);
}

fn op_depth(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.push(.{ .int = Int257.fromI64(@intCast(vm.stack.depth)) });
}

fn op_chkdepth(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n_val = try (try vm.stack.pop()).asInt();
    const n = n_val.toI64();
    if (n < 0 or @as(u32, @intCast(n)) > vm.stack.depth) return error.StackUnderflow;
}

fn op_onlytop(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n_val = try (try vm.stack.pop()).asInt();
    const n = n_val.toI64();
    if (n < 0) return error.IntegerOutOfRange;
    const keep: u32 = @intCast(n);
    if (keep > vm.stack.depth) return error.StackUnderflow;
    // Remove everything below top 'keep' elements
    const remove = vm.stack.depth - keep;
    if (remove > 0) {
        // Shift top elements down
        var k: u32 = 0;
        while (k < keep) : (k += 1) {
            vm.stack.items[k] = vm.stack.items[k + remove];
        }
        vm.stack.depth = keep;
    }
}

fn op_blk_ops(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const sub = byte0 & 0x0F;
    const args = try vm.fetchUint(8);
    const hi: u32 = @intCast((args >> 4) & 0x0F);
    const lo: u32 = @intCast(args & 0x0F);
    switch (sub) {
        0x4 => try vm.stack.blkdrop(hi), // BLKDROP
        0x5 => try vm.stack.blkpush(hi, lo), // BLKPUSH
        0x6 => try vm.stack.blkswap(hi + 1, lo + 1), // BLKSWAP
        else => {},
    }
}

// ── Tuple operations ───────────────────────────────────────────────────

fn op_tuple_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const n: u8 = @intCast(sub & 0x0F);
    const op = (sub >> 4) & 0x0F;

    switch (op) {
        0x0 => {
            // TUPLE n: pop n values, create tuple
            const t = try vm.tuple_arena.alloc();
            var i: u8 = 0;
            while (i < n) : (i += 1) {
                t.items[n - 1 - i] = try vm.stack.pop();
            }
            t.len = n;
            try vm.stack.push(.{ .tuple = t });
        },
        0x1 => {
            // UNTUPLE n: pop tuple, push n values
            const t = try (try vm.stack.pop()).asTuple();
            if (t.len != n) return error.TypeMismatch;
            var i: u8 = 0;
            while (i < n) : (i += 1) {
                try vm.stack.push(t.items[i]);
            }
            vm.tuple_arena.free(t);
        },
        0x2 => {
            // INDEX n: pop tuple, push tuple[n]
            const t = try (try vm.stack.pop()).asTuple();
            const val = try t.get(n);
            try vm.stack.push(val);
        },
        0x3 => {
            if (n == 0) {
                // TPUSH
                const val = try vm.stack.pop();
                const t = try (try vm.stack.pop()).asTuple();
                try t.tpush(val);
                try vm.stack.push(.{ .tuple = t });
            } else if (n == 1) {
                // TPOP
                const t = try (try vm.stack.pop()).asTuple();
                const val = try t.tpop();
                try vm.stack.push(.{ .tuple = t });
                try vm.stack.push(val);
            } else {
                return error.InvalidOpcode;
            }
        },
        0x5 => {
            // INDEXVAR: index from stack
            const idx_val = try (try vm.stack.pop()).asInt();
            const t = try (try vm.stack.pop()).asTuple();
            const idx = idx_val.toI64();
            if (idx < 0 or idx >= t.len) return error.TupleIndexOutOfRange;
            const val = try t.get(@intCast(idx));
            try vm.stack.push(val);
        },
        0x6 => {
            // SETINDEX n: set tuple[n] = value
            const val = try vm.stack.pop();
            const t = try (try vm.stack.pop()).asTuple();
            try t.set(n, val);
            try vm.stack.push(.{ .tuple = t });
        },
        0x7 => {
            // SETINDEXVAR: index from stack
            const val = try vm.stack.pop();
            const idx_val = try (try vm.stack.pop()).asInt();
            const t = try (try vm.stack.pop()).asTuple();
            const idx = idx_val.toI64();
            if (idx < 0 or idx >= t.len) return error.TupleIndexOutOfRange;
            try t.set(@intCast(idx), val);
            try vm.stack.push(.{ .tuple = t });
        },
        0x8 => {
            // TUPLEVAR: n from stack
            const nv = try (try vm.stack.pop()).asInt();
            const cnt: u8 = @intCast(nv.toI64());
            const t = try vm.tuple_arena.alloc();
            var i: u8 = 0;
            while (i < cnt) : (i += 1) {
                t.items[cnt - 1 - i] = try vm.stack.pop();
            }
            t.len = cnt;
            try vm.stack.push(.{ .tuple = t });
        },
        0x9 => {
            // UNTUPLEVAR
            const nv = try (try vm.stack.pop()).asInt();
            const cnt: u8 = @intCast(nv.toI64());
            const t = try (try vm.stack.pop()).asTuple();
            if (t.len != cnt) return error.TypeMismatch;
            var i: u8 = 0;
            while (i < cnt) : (i += 1) {
                try vm.stack.push(t.items[i]);
            }
            vm.tuple_arena.free(t);
        },
        0xA => {
            // TLEN: push tuple length
            const t = try (try vm.stack.pop()).asTuple();
            try vm.stack.push(.{ .int = Int257.fromI64(t.len) });
        },
        0xC => {
            // NULLSWAPIF etc (simplified)
            const top = try vm.stack.peek(0);
            if (top.isNull()) {
                _ = try vm.stack.pop();
            }
        },
        else => return error.InvalidOpcode,
    }
}

// ── Push Integer ───────────────────────────────────────────────────────

fn op_pushint_tiny(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    const val: i64 = @intCast(byte0 & 0x0F);
    try vm.stack.push(.{ .int = Int257.fromI64(val) });
}

fn op_pushint_8(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const val = try vm.fetchInt(8);
    try vm.stack.push(.{ .int = Int257.fromI64(val) });
}

fn op_pushint_16(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const val = try vm.fetchInt(16);
    try vm.stack.push(.{ .int = Int257.fromI64(val) });
}

fn op_pushint_long(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const len_byte = try vm.fetchUint(5);
    const bit_len: u16 = @intCast((len_byte + 1) * 8);
    // Read big integer from instruction stream
    if (bit_len <= 64) {
        const val = try vm.fetchInt(@intCast(bit_len));
        try vm.stack.push(.{ .int = Int257.fromI64(val) });
    } else {
        // Multi-limb read
        var result = Int257.zero();
        const sign_bit = try vm.fetchUint(1);
        const remaining = bit_len - 1;
        // Read in 64-bit chunks
        var bits_read: u16 = 0;
        var limb_idx: usize = 3;
        while (bits_read < remaining) {
            const chunk = @min(remaining - bits_read, 64);
            const val = try vm.fetchUint(chunk);
            if (limb_idx < 4) {
                result.limbs[limb_idx] = val;
            }
            bits_read += chunk;
            if (limb_idx == 0) break;
            limb_idx -= 1;
        }
        result.sign = sign_bit != 0;
        try vm.stack.push(.{ .int = result });
    }
}

fn op_pushpow2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n = try vm.fetchUint(8);
    const shift: u8 = @intCast(n + 1);
    var result = Int257.zero();
    if (shift < 64) {
        result.limbs[0] = @as(u64, 1) << @intCast(shift);
    } else if (shift < 128) {
        result.limbs[1] = @as(u64, 1) << @intCast(shift - 64);
    } else if (shift < 192) {
        result.limbs[2] = @as(u64, 1) << @intCast(shift - 128);
    } else if (shift < 256) {
        result.limbs[3] = @as(u64, 1) << @intCast(shift - 192);
    }
    try vm.stack.push(.{ .int = result });
}

fn op_pushpow2dec(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n = try vm.fetchUint(8);
    // 2^(n+1) - 1
    var result = Int257.zero();
    const shift: u9 = @intCast(n + 1);
    // Fill all bits below shift with 1s
    const full_limbs = shift / 64;
    const rem_bits: u6 = @intCast(shift % 64);
    for (0..@min(full_limbs, 4)) |i| {
        result.limbs[i] = std.math.maxInt(u64);
    }
    if (full_limbs < 4 and rem_bits > 0) {
        result.limbs[full_limbs] = (@as(u64, 1) << rem_bits) - 1;
    }
    try vm.stack.push(.{ .int = result });
}

fn op_pushnegpow2(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n = try vm.fetchUint(8);
    const shift: u8 = @intCast(n + 1);
    var result = Int257.zero();
    if (shift < 64) {
        result.limbs[0] = @as(u64, 1) << @intCast(shift);
    } else if (shift < 128) {
        result.limbs[1] = @as(u64, 1) << @intCast(shift - 64);
    } else if (shift < 192) {
        result.limbs[2] = @as(u64, 1) << @intCast(shift - 128);
    } else if (shift < 256) {
        result.limbs[3] = @as(u64, 1) << @intCast(shift - 192);
    }
    result.sign = true;
    try vm.stack.push(.{ .int = result });
}

// ── Push Ref/Slice/Cont ────────────────────────────────────────────────

fn op_pushref(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = vm.cc.code.loadRef() catch return error.InvalidOpcode;
    try vm.stack.push(.{ .cell = c });
}

fn op_pushrefslice(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = vm.cc.code.loadRef() catch return error.InvalidOpcode;
    try vm.stack.push(.{ .slice = Slice.fromCell(c) });
}

fn op_pushrefcont(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = vm.cc.code.loadRef() catch return error.InvalidOpcode;
    try vm.stack.push(.{ .cont = Continuation.fromSlice(Slice.fromCell(c)) });
}

fn op_pushslice_short(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const len_bits = try vm.fetchUint(4);
    const bit_count: u16 = @intCast(len_bits * 8 + 4);
    // Create a cell with these bits
    const c = try vm.cell_arena.alloc();
    var bits_remaining: u16 = bit_count;
    var byte_idx: u16 = 0;
    while (bits_remaining >= 8) {
        const b: u8 = @intCast(try vm.fetchUint(8));
        c.data[byte_idx] = b;
        byte_idx += 1;
        bits_remaining -= 8;
    }
    if (bits_remaining > 0) {
        const b: u8 = @intCast(try vm.fetchUint(bits_remaining));
        c.data[byte_idx] = @as(u8, b) << @intCast(8 - bits_remaining);
    }
    c.bit_len = bit_count;
    try vm.stack.push(.{ .slice = Slice.fromCell(c) });
}

fn op_pushslice_mid(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const len_and_refs = try vm.fetchUint(8);
    const refs: u8 = @intCast((len_and_refs >> 5) & 0x07);
    const data_bits: u16 = @intCast((len_and_refs & 0x1F) * 8 + 1);
    const c = try vm.cell_arena.alloc();
    var bits_remaining: u16 = data_bits;
    var byte_idx: u16 = 0;
    while (bits_remaining >= 8) {
        const b: u8 = @intCast(try vm.fetchUint(8));
        c.data[byte_idx] = b;
        byte_idx += 1;
        bits_remaining -= 8;
    }
    if (bits_remaining > 0) {
        const b: u8 = @intCast(try vm.fetchUint(bits_remaining));
        c.data[byte_idx] = @as(u8, b) << @intCast(8 - bits_remaining);
    }
    c.bit_len = data_bits;
    var i: u8 = 0;
    while (i < refs) : (i += 1) {
        c.refs[i] = vm.cc.code.loadRef() catch return error.InvalidOpcode;
        c.ref_count = i + 1;
    }
    try vm.stack.push(.{ .slice = Slice.fromCell(c) });
}

fn op_pushcont_short(vm: *TVM, byte0: u32) TvmError!void {
    try vm.charge(26);
    // 0x8E: r=0, next nibble = data length in bytes
    // 0x8F: r in high bits
    const sub = try vm.fetchUint(8);
    var data_bytes: u16 = undefined;
    var refs: u8 = 0;

    if (byte0 == 0x8E) {
        data_bytes = @intCast((sub >> 4) & 0x0F);
        refs = 0;
        _ = sub & 0x0F; // reserved
    } else {
        data_bytes = @intCast(sub & 0x3F);
        refs = @intCast((sub >> 6) & 0x03);
    }

    const c = try vm.cell_arena.alloc();
    const data_bits = data_bytes * 8;
    var k: u16 = 0;
    while (k < data_bytes) : (k += 1) {
        c.data[k] = @intCast(try vm.fetchUint(8));
    }
    c.bit_len = data_bits;

    var i: u8 = 0;
    while (i < refs) : (i += 1) {
        c.refs[i] = vm.cc.code.loadRef() catch return error.InvalidOpcode;
        c.ref_count = i + 1;
    }

    try vm.stack.push(.{ .cont = Continuation.fromSlice(Slice.fromCell(c)) });
}

// ── Arithmetic ─────────────────────────────────────────────────────────

fn op_add(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const result = a.add(b) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_sub(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const result = a.sub(b) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_subr(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const result = b.sub(a) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_negate(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try (try vm.stack.pop()).asInt();
    var result = a;
    result.sign = !result.sign;
    if (result.isZero()) result.sign = false;
    try vm.stack.push(.{ .int = result });
}

fn op_inc(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.add(Int257.fromI64(1)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_dec(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.sub(Int257.fromI64(1)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_mul(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const result = a.mul(b) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_abs(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try (try vm.stack.pop()).asInt();
    var result = a;
    result.sign = false;
    try vm.stack.push(.{ .int = result });
}

fn op_div_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();

    switch (sub) {
        0x04 => {
            // DIVMOD: push quotient then remainder
            const qr = a.divmod(b) catch return error.DivisionByZero;
            try vm.stack.push(.{ .int = qr[0] });
            try vm.stack.push(.{ .int = qr[1] });
        },
        0x08 => {
            // DIV
            const qr = a.divmod(b) catch return error.DivisionByZero;
            try vm.stack.push(.{ .int = qr[0] });
        },
        0x0C => {
            // MOD
            const qr = a.divmod(b) catch return error.DivisionByZero;
            try vm.stack.push(.{ .int = qr[1] });
        },
        else => {
            // Other division modes — simplified, treat as DIVMOD
            const qr = a.divmod(b) catch return error.DivisionByZero;
            try vm.stack.push(.{ .int = qr[0] });
            try vm.stack.push(.{ .int = qr[1] });
        },
    }
}

fn op_addconst(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.add(Int257.fromI64(c)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_mulconst(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.mul(Int257.fromI64(c)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_lshift(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n = try vm.fetchUint(8);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.shl(@intCast(n + 1)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_rshift(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n = try vm.fetchUint(8);
    const a = try (try vm.stack.pop()).asInt();
    const result = a.shr(@intCast(n + 1));
    try vm.stack.push(.{ .int = result });
}

fn op_lshift_var(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n_val = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const n = n_val.toI64();
    if (n < 0 or n > 256) return error.IntegerOutOfRange;
    const result = a.shl(@intCast(n)) catch return error.IntegerOverflow;
    try vm.stack.push(.{ .int = result });
}

fn op_rshift_var(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const n_val = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const n = n_val.toI64();
    if (n < 0 or n > 256) return error.IntegerOutOfRange;
    const result = a.shr(@intCast(n));
    try vm.stack.push(.{ .int = result });
}

// ── Comparison ─────────────────────────────────────────────────────────

fn op_sgn(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.isZero()) 0 else if (a.sign) -1 else 1;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_less(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(b) == .lt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_equal(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(b) == .eq) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_leq(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(b) != .gt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_greater(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(b) == .gt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_geq(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(b) != .lt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_cmp(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const b = try (try vm.stack.pop()).asInt();
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = switch (a.cmp(b)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_logic_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    switch (sub) {
        0x00 => {
            // AND
            const b = try (try vm.stack.pop()).asInt();
            const a = try (try vm.stack.pop()).asInt();
            try vm.stack.push(.{ .int = a.bitAnd(b) });
        },
        0x01 => {
            // OR
            const b = try (try vm.stack.pop()).asInt();
            const a = try (try vm.stack.pop()).asInt();
            try vm.stack.push(.{ .int = a.bitOr(b) });
        },
        0x02 => {
            // XOR
            const b = try (try vm.stack.pop()).asInt();
            const a = try (try vm.stack.pop()).asInt();
            try vm.stack.push(.{ .int = a.bitXor(b) });
        },
        0x03 => {
            // NOT
            const a = try (try vm.stack.pop()).asInt();
            try vm.stack.push(.{ .int = a.bitNot() });
        },
        0x08 => {
            // FITS n+1
            const n = try vm.fetchUint(8);
            const a = try (try vm.stack.pop()).asInt();
            _ = a;
            _ = n;
            // Check if value fits in n+1 bits (simplified — just pass through)
            try vm.stack.push(.{ .int = Int257.fromI64(-1) });
        },
        0x09 => {
            // UFITS n+1
            const n = try vm.fetchUint(8);
            const a = try (try vm.stack.pop()).asInt();
            _ = a;
            _ = n;
            try vm.stack.push(.{ .int = Int257.fromI64(-1) });
        },
        else => return error.InvalidOpcode,
    }
}

fn op_eqint(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(Int257.fromI64(c)) == .eq) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_lessint(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(Int257.fromI64(c)) == .lt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_gtint(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(Int257.fromI64(c)) == .gt) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

fn op_neqint(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try vm.fetchInt(8);
    const a = try (try vm.stack.pop()).asInt();
    const r: i64 = if (a.cmp(Int257.fromI64(c)) != .eq) -1 else 0;
    try vm.stack.push(.{ .int = Int257.fromI64(r) });
}

// ── Cell Operations ────────────────────────────────────────────────────

fn op_newc(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    try vm.stack.push(.{ .builder = Builder.init() });
}

fn op_endc(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    var b = try (try vm.stack.pop()).asBuilder();
    const c = b.finalize(vm.cell_arena) catch return error.CellOverflow;
    try vm.stack.push(.{ .cell = c });
}

fn op_sti_stu(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const is_signed = (sub & 0x01) == 0;
    const bits: u16 = @intCast((sub >> 1) & 0x7F);
    const actual_bits = bits + 1;

    var b = try (try vm.stack.pop()).asBuilder();
    const val = try (try vm.stack.pop()).asInt();

    if (is_signed) {
        b.storeInt(val, actual_bits) catch return error.CellOverflow;
    } else {
        b.storeUint(val.limbs[0], actual_bits) catch return error.CellOverflow;
    }
    try vm.stack.push(.{ .builder = b });
}

fn op_stref(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    var b = try (try vm.stack.pop()).asBuilder();
    const c = try (try vm.stack.pop()).asCell();
    b.storeRef(c) catch return error.CellOverflow;
    try vm.stack.push(.{ .builder = b });
}

fn op_stslice(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    var b = try (try vm.stack.pop()).asBuilder();
    var s = try (try vm.stack.pop()).asSlice();
    b.storeSlice(&s) catch return error.CellOverflow;
    try vm.stack.push(.{ .builder = b });
}

fn op_stix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const is_signed = (sub & 0x01) == 0;
    _ = is_signed;

    const bits_val = try (try vm.stack.pop()).asInt();
    const bits: u16 = @intCast(bits_val.toI64());
    var b = try (try vm.stack.pop()).asBuilder();
    const val = try (try vm.stack.pop()).asInt();

    b.storeInt(val, bits) catch return error.CellOverflow;
    try vm.stack.push(.{ .builder = b });
}

fn op_ctos(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const c = try (try vm.stack.pop()).asCell();
    try vm.stack.push(.{ .slice = Slice.fromCell(c) });
}

fn op_ldi_ldu(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const is_signed = (sub & 0x01) == 0;
    const bits: u16 = @intCast((sub >> 1) & 0x7F);
    const actual_bits = bits + 1;

    var s = try (try vm.stack.pop()).asSlice();
    if (is_signed) {
        const val = s.loadInt(actual_bits) catch return error.CellUnderflow;
        try vm.stack.push(.{ .int = Int257.fromI64(val) });
    } else {
        const val = s.loadUint(actual_bits) catch return error.CellUnderflow;
        try vm.stack.push(.{ .int = Int257.fromI64(@intCast(val)) });
    }
    try vm.stack.push(.{ .slice = s });
}

fn op_ldix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const is_signed = (sub & 0x01) == 0;
    _ = is_signed;

    const bits_val = try (try vm.stack.pop()).asInt();
    const bits: u16 = @intCast(bits_val.toI64());
    var s = try (try vm.stack.pop()).asSlice();
    const val = s.loadInt(bits) catch return error.CellUnderflow;
    try vm.stack.push(.{ .int = Int257.fromI64(val) });
    try vm.stack.push(.{ .slice = s });
}

fn op_ldref(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    var s = try (try vm.stack.pop()).asSlice();
    const c = s.loadRef() catch return error.CellUnderflow;
    try vm.stack.push(.{ .cell = c });
    try vm.stack.push(.{ .slice = s });
}

fn op_ldslice(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const nbits = try vm.fetchUint(8);
    const bits: u16 = @intCast((nbits + 1) * 8);
    var s = try (try vm.stack.pop()).asSlice();
    // Create a sub-slice
    if (s.remainingBits() < bits) return error.CellUnderflow;
    // Skip bits in source, push the sub-slice as a new cell's slice
    const c = try vm.cell_arena.alloc();
    var k: u16 = 0;
    while (k < bits) {
        const chunk = @min(bits - k, 8);
        const val: u8 = @intCast(s.loadUint(chunk) catch return error.CellUnderflow);
        c.data[k / 8] = val;
        k += chunk;
    }
    c.bit_len = bits;
    try vm.stack.push(.{ .slice = Slice.fromCell(c) });
    try vm.stack.push(.{ .slice = s });
}

fn op_cell_query(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    switch (sub) {
        0x18 => {
            // SBITS: push remaining bits count
            const s = try (try vm.stack.pop()).asSlice();
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(s.remainingBits())) });
        },
        0x19 => {
            // SREFS: push remaining refs count
            const s = try (try vm.stack.pop()).asSlice();
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(s.remainingRefs())) });
        },
        0x10 => {
            // SBITREFS: push bits and refs
            const s = try (try vm.stack.pop()).asSlice();
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(s.remainingBits())) });
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(s.remainingRefs())) });
        },
        0x36 => {
            // BBITS: remaining builder bits capacity
            const b = try (try vm.stack.pop()).asBuilder();
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(1023 - b.bit_len)) });
        },
        0x37 => {
            // BREFS: remaining builder refs capacity
            const b = try (try vm.stack.pop()).asBuilder();
            try vm.stack.push(.{ .int = Int257.fromI64(@intCast(4 - b.ref_count)) });
        },
        else => return error.InvalidOpcode,
    }
}

// ── Control Flow ───────────────────────────────────────────────────────

fn op_execute(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    vm.callCont(cont);
}

fn op_jmpx(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    vm.jumpToCont(cont);
}

fn op_callx_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    _ = sub;
    // CALLXARGS / JMPXARGS etc — simplified: just execute
    const cont = try (try vm.stack.pop()).asCont();
    vm.callCont(cont);
}

fn op_control_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    switch (sub) {
        0x30 => {
            // RET / RETTRUE
            try vm.doRet();
        },
        0x31 => {
            // RETALT / RETFALSE
            try vm.doRetAlt();
        },
        0x32, 0x34 => {
            // RETBOOL
            const flag = try (try vm.stack.pop()).asInt();
            if (!flag.isZero()) {
                try vm.doRet();
            } else {
                try vm.doRetAlt();
            }
        },
        0x39 => {
            // SETEXITALT
            try vm.doRet();
        },
        0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57 => {
            // PUSHCTRi: push control register i
            const i = sub & 0x07;
            if (vm.cr[i]) |val| {
                try vm.stack.push(val);
            } else {
                try vm.stack.push(.null);
            }
        },
        0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F => {
            // POPCTRi: pop into control register i
            const i = sub & 0x07;
            const val = try vm.stack.pop();
            vm.cr[i] = val;
        },
        0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67 => {
            // SETCONTCTRi
            const i = sub & 0x07;
            const val = try vm.stack.pop();
            var cont = try (try vm.stack.pop()).asCont();
            // Convert Value to SavedReg (only int supported)
            cont.savelist[i] = switch (val) {
                .int => |v| .{ .int_val = v },
                else => .none,
            };
            try vm.stack.push(.{ .cont = cont });
        },
        else => return error.InvalidOpcode,
    }
}

fn op_if(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    const flag = try (try vm.stack.pop()).asInt();
    if (!flag.isZero()) {
        vm.callCont(cont);
    }
}

fn op_ifnot(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    const flag = try (try vm.stack.pop()).asInt();
    if (flag.isZero()) {
        vm.callCont(cont);
    }
}

fn op_ifjmp(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    const flag = try (try vm.stack.pop()).asInt();
    if (!flag.isZero()) {
        vm.jumpToCont(cont);
    }
}

fn op_ifnotjmp(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont = try (try vm.stack.pop()).asCont();
    const flag = try (try vm.stack.pop()).asInt();
    if (flag.isZero()) {
        vm.jumpToCont(cont);
    }
}

fn op_ifelse(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const cont_false = try (try vm.stack.pop()).asCont();
    const cont_true = try (try vm.stack.pop()).asCont();
    const flag = try (try vm.stack.pop()).asInt();
    if (!flag.isZero()) {
        vm.callCont(cont_true);
    } else {
        vm.callCont(cont_false);
    }
}

fn op_repeat(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const body = try (try vm.stack.pop()).asCont();
    const n_val = try (try vm.stack.pop()).asInt();
    const n = n_val.toI64();

    if (n <= 0) return; // Skip if count is 0 or negative

    var i: i64 = 0;
    while (i < n) : (i += 1) {
        // Save current state, execute body
        const saved_cc = vm.cc;
        vm.cc = body;
        vm.cc.code = body.code; // Reset code pointer for each iteration

        // Run the body inline
        while (vm.cc.code.remainingBits() > 0 and vm.running) {
            const byte0 = vm.cc.code.loadUint(8) catch break;
            dispatch(vm, @intCast(byte0)) catch |e| {
                vm.handleError(e);
                return;
            };
        }
        vm.cc = saved_cc;
    }
}

fn op_until(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const body = try (try vm.stack.pop()).asCont();

    while (vm.running) {
        const saved_cc = vm.cc;
        vm.cc = body;
        vm.cc.code = body.code;

        while (vm.cc.code.remainingBits() > 0 and vm.running) {
            const byte0 = vm.cc.code.loadUint(8) catch break;
            dispatch(vm, @intCast(byte0)) catch |e| {
                vm.handleError(e);
                return;
            };
        }
        vm.cc = saved_cc;

        // Check flag on stack
        const flag = (try vm.stack.pop()).asInt() catch return;
        if (!flag.isZero()) break;
    }
}

fn op_while(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const body = try (try vm.stack.pop()).asCont();
    const cond = try (try vm.stack.pop()).asCont();

    while (vm.running) {
        // Execute condition
        const saved_cc = vm.cc;
        vm.cc = cond;
        vm.cc.code = cond.code;

        while (vm.cc.code.remainingBits() > 0 and vm.running) {
            const byte0 = vm.cc.code.loadUint(8) catch break;
            dispatch(vm, @intCast(byte0)) catch |e| {
                vm.handleError(e);
                return;
            };
        }
        vm.cc = saved_cc;

        const flag = (try vm.stack.pop()).asInt() catch return;
        if (flag.isZero()) break;

        // Execute body
        const saved_cc2 = vm.cc;
        vm.cc = body;
        vm.cc.code = body.code;

        while (vm.cc.code.remainingBits() > 0 and vm.running) {
            const byte0 = vm.cc.code.loadUint(8) catch break;
            dispatch(vm, @intCast(byte0)) catch |e| {
                vm.handleError(e);
                return;
            };
        }
        vm.cc = saved_cc2;
    }
}

fn op_again(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const body = try (try vm.stack.pop()).asCont();

    while (vm.running) {
        const saved_cc = vm.cc;
        vm.cc = body;
        vm.cc.code = body.code;

        while (vm.cc.code.remainingBits() > 0 and vm.running) {
            const byte0 = vm.cc.code.loadUint(8) catch break;
            dispatch(vm, @intCast(byte0)) catch |e| {
                vm.handleError(e);
                return;
            };
        }
        vm.cc = saved_cc;
    }
}

fn op_cont_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    switch (sub) {
        0x00 => {
            // SETCONTARGS: pop n, set continuation nargs
            const n_val = try (try vm.stack.pop()).asInt();
            var cont = try (try vm.stack.pop()).asCont();
            cont.nargs = @intCast(n_val.toI64());
            try vm.stack.push(.{ .cont = cont });
        },
        0xF0 => {
            // CALLCC
            var cont: Continuation = vm.cc;
            if (vm.cr[0]) |c0| {
                cont.savelist[0] = switch (c0) {
                    .int => |v| .{ .int_val = v },
                    else => .none,
                };
            }
            try vm.stack.push(.{ .cont = cont });
        },
        else => return error.InvalidOpcode,
    }
}

// ── Dictionary ops (stubs) ─────────────────────────────────────────────

fn op_dict_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    switch (sub) {
        0x00, 0x01 => {
            // NEWDICT — push null/empty slice
            try vm.stack.push(.null);
        },
        0x4A => {
            // DICTGET (simplified stub)
            _ = try vm.stack.pop(); // key
            _ = try vm.stack.pop(); // dict
            _ = try vm.stack.pop(); // key len
            try vm.stack.push(.null);
            try vm.stack.push(.{ .int = Int257.fromI64(0) }); // not found
        },
        else => return error.InvalidOpcode,
    }
}

// ── Exception handling ─────────────────────────────────────────────────

fn op_throw_prefix(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    const hi = (sub >> 4) & 0x0F;
    const lo = sub & 0x0F;

    switch (hi) {
        0x2 => {
            // THROW 0-63
            const excno: i32 = @intCast(lo * 4 + (try vm.fetchUint(2)));
            _ = excno;
            return error.Halted; // simplified: throw causes halt
        },
        0x6 => {
            // THROWIF
            const excno: i32 = @intCast(lo * 4 + (try vm.fetchUint(2)));
            const flag = try (try vm.stack.pop()).asInt();
            if (!flag.isZero()) {
                _ = excno;
                return error.Halted;
            }
        },
        0xA => {
            // THROWIFNOT
            const excno: i32 = @intCast(lo * 4 + (try vm.fetchUint(2)));
            const flag = try (try vm.stack.pop()).asInt();
            if (flag.isZero()) {
                _ = excno;
                return error.Halted;
            }
        },
        0xC => {
            // THROW long (11-bit exception number)
            const n = try vm.fetchUint(8);
            const excno: i32 = @intCast(lo * 256 + n);
            _ = excno;
            return error.Halted;
        },
        0xF => {
            if (lo == 0x0) {
                // TRY
                const handler = try (try vm.stack.pop()).asCont();
                const body = try (try vm.stack.pop()).asCont();
                // Set exception handler
                vm.cr[2] = .{ .cont = handler };
                vm.callCont(body);
            } else if (lo == 0xF) {
                // TRYARGS
                _ = try vm.fetchUint(8); // nargs, pargs
                const handler = try (try vm.stack.pop()).asCont();
                const body = try (try vm.stack.pop()).asCont();
                vm.cr[2] = .{ .cont = handler };
                vm.callCont(body);
            } else {
                return error.InvalidOpcode;
            }
        },
        else => return error.InvalidOpcode,
    }
}

// ── Debug / SETCP ──────────────────────────────────────────────────────

fn op_debug(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    // Debug ops are NOPs in release
    if (sub == 0x00) {
        // DUMPSTK — print stack (debug only)
        // In production: NOP
    }
}

fn op_setcp_special(vm: *TVM, _: u32) TvmError!void {
    try vm.charge(26);
    const sub = try vm.fetchUint(8);
    if (sub == 0xFF) {
        // SETCP0: set codepage to 0
        vm.cp = 0;
    } else if (sub == 0xF0) {
        // SETCP with next byte
        vm.cp = @intCast(try vm.fetchUint(16));
    } else {
        // Implicit exit
        vm.exit_code = 0;
        vm.running = false;
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

test "dispatch NOP" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 10000;
    try dispatch(&vm, 0x00);
    try std.testing.expectEqual(@as(i64, 10000 - 26), vm.gas_remaining);
}

test "dispatch PUSH PUSHINT" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 100000;

    // Build a code cell with: PUSHINT_tiny 5 (0x75), PUSHINT_tiny 3 (0x73), ADD (0xA0)
    const c = try arena.alloc();
    c.data[0] = 0x75; // push 5
    c.data[1] = 0x73; // push 3
    c.data[2] = 0xA0; // ADD
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 8), result.toI64());
}

test "dispatch arithmetic SUB" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 100000;

    const c = try arena.alloc();
    c.data[0] = 0x7A; // push 10
    c.data[1] = 0x73; // push 3
    c.data[2] = 0xA1; // SUB
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 7), result.toI64());
}

test "dispatch XCHG" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 100000;

    const c = try arena.alloc();
    c.data[0] = 0x71; // push 1
    c.data[1] = 0x72; // push 2
    c.data[2] = 0x01; // XCHG s0, s1 (swap)
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 2), vm.stack.depth);
    const top = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 1), top.toI64());
}

test "dispatch comparison" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 100000;

    const c = try arena.alloc();
    c.data[0] = 0x73; // push 3
    c.data[1] = 0x75; // push 5
    c.data[2] = 0xB1; // LESS: 3 < 5 = -1 (true)
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, -1), result.toI64());
}

test "dispatch MUL" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.gas_remaining = 100000;

    const c = try arena.alloc();
    c.data[0] = 0x76; // push 6
    c.data[1] = 0x77; // push 7
    c.data[2] = 0xA6; // MUL
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 42), result.toI64());
}

const CellArena = cell.CellArena;
