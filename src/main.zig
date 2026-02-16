const std = @import("std");
const cell = @import("cell.zig");
const tvm_mod = @import("tvm.zig");
const ops = @import("ops.zig");

const Cell = cell.Cell;
const CellArena = cell.CellArena;
const Slice = cell.Slice;
const Builder = cell.Builder;
const Int257 = cell.Int257;
const TVM = tvm_mod.TVM;
const Value = tvm_mod.Value;
const Continuation = tvm_mod.Continuation;

// ── BOC Deserialization ────────────────────────────────────────────────

const BocError = error{
    InvalidMagic,
    InvalidFormat,
    TooManyCells,
    InvalidRef,
    OutOfMemory,
    CellOverflow,
    CellUnderflow,
};

const BOC_MAGIC: u32 = 0xB5EE9C72;

fn deserializeBoc(data: []const u8, arena: *CellArena) BocError!*Cell {
    if (data.len < 4) return error.InvalidFormat;

    const magic = std.mem.readInt(u32, data[0..4], .big);
    if (magic != BOC_MAGIC) return error.InvalidMagic;

    // Parse header
    const flags_byte = data[4];
    const ref_size: u8 = flags_byte & 0x07;
    const off_size = data[5];

    var pos: usize = 6;

    // Read cell count, root count, absent count
    const cell_count = readIntN(data, &pos, ref_size);
    const root_count = readIntN(data, &pos, ref_size);
    _ = readIntN(data, &pos, ref_size); // absent
    _ = readIntN(data, &pos, off_size); // data_size

    if (root_count == 0 or cell_count == 0) return error.InvalidFormat;

    // Read root index
    const root_idx = readIntN(data, &pos, ref_size);

    // Allocate cells
    var cells: [1024]*Cell = undefined;
    if (cell_count > 1024) return error.TooManyCells;

    for (0..cell_count) |i| {
        cells[i] = arena.alloc() catch return error.OutOfMemory;
    }

    // Deserialize each cell
    for (0..cell_count) |i| {
        if (pos >= data.len) return error.InvalidFormat;

        const d1 = data[pos];
        pos += 1;
        const d2 = data[pos];
        pos += 1;

        const refs_cnt: u8 = d1 & 0x07;

        const data_bytes: usize = (d2 + 1) / 2;
        const data_bits: u16 = @as(u16, d2) * 4;

        // Copy cell data
        if (pos + data_bytes > data.len) return error.InvalidFormat;
        @memcpy(cells[i].data[0..data_bytes], data[pos .. pos + data_bytes]);
        pos += data_bytes;

        cells[i].bit_len = data_bits;

        // Read refs
        cells[i].ref_count = refs_cnt;
        for (0..refs_cnt) |r| {
            const ref_idx = readIntN(data, &pos, ref_size);
            if (ref_idx >= cell_count) return error.InvalidRef;
            cells[i].refs[r] = cells[ref_idx];
        }
    }

    return cells[root_idx];
}

fn readIntN(data: []const u8, pos: *usize, n: u8) usize {
    var result: usize = 0;
    for (0..n) |_| {
        if (pos.* >= data.len) return 0;
        result = (result << 8) | @as(usize, data[pos.*]);
        pos.* += 1;
    }
    return result;
}

// ── CLI Entry Point ────────────────────────────────────────────────────

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var gas_limit: i64 = 1_000_000;
    var verbose = false;
    var boc_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--gas-limit") and i + 1 < args.len) {
            i += 1;
            gas_limit = std.fmt.parseInt(i64, args[i], 10) catch 1_000_000;
        } else if (std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            printUsage();
            return;
        } else {
            boc_file = args[i];
        }
    }

    if (boc_file == null) {
        printUsage();
        return;
    }

    // Read BOC file
    const file = std.fs.cwd().openFile(boc_file.?, .{}) catch |err| {
        std.debug.print("Error: cannot open '{s}': {}\n", .{ boc_file.?, err });
        std.process.exit(1);
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        std.debug.print("Error: cannot read file: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(data);

    // Initialize arena and TVM
    const arena_buf = try allocator.create(CellArena);
    arena_buf.* = CellArena.init();

    // Deserialize BOC
    const root_cell = deserializeBoc(data, arena_buf) catch |err| {
        std.debug.print("Error: BOC deserialization failed: {}\n", .{err});
        std.process.exit(1);
    };

    // Initialize TVM
    var vm = TVM.init(arena_buf);
    vm.setGas(gas_limit);
    vm.setCode(root_cell);

    if (verbose) {
        std.debug.print("TVM initialized: gas_limit={d}, code_bits={d}\n", .{ gas_limit, root_cell.bit_len });
    }

    // Run
    vm.run();

    // Output results
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("exit_code: {d}\n", .{vm.exit_code});
    try stdout.print("gas_used: {d}\n", .{gas_limit - vm.gas_remaining});

    if (vm.stack.depth > 0) {
        try stdout.print("stack_depth: {d}\n", .{vm.stack.depth});
        const top = vm.stack.peek(0) catch return;
        switch (top) {
            .int => |v| try stdout.print("result: {d}\n", .{v.toI64()}),
            .null => try stdout.print("result: null\n", .{}),
            else => try stdout.print("result: <{s}>\n", .{@tagName(top)}),
        }
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig-tvm [options] <boc-file>
        \\
        \\Options:
        \\  --gas-limit N    Set gas limit (default: 1000000)
        \\  --verbose        Enable verbose output
        \\  --help, -h       Show this help
        \\
    , .{});
}

// ── Tests ──────────────────────────────────────────────────────────────

test "simple bytecode execution: push 5 + push 3 + ADD" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x75; // push 5
    c.data[1] = 0x73; // push 3
    c.data[2] = 0xA0; // ADD
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(i32, 0), vm.exit_code);
    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 8), result.toI64());
}

test "push 6 * push 7 + MUL = 42" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x76; // push 6
    c.data[1] = 0x77; // push 7
    c.data[2] = 0xA6; // MUL
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(i32, 0), vm.exit_code);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 42), result.toI64());
}

test "comparison: 3 < 5 = true (-1)" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x73; // push 3
    c.data[1] = 0x75; // push 5
    c.data[2] = 0xB1; // LESS
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, -1), result.toI64());
}

test "NOP does nothing" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x71; // push 1
    c.data[1] = 0x00; // NOP
    c.bit_len = 16;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 1), vm.stack.depth);
    const result = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 1), result.toI64());
}

test "out of gas" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(25); // Not enough gas for even one instruction (costs 26)

    const c = try arena.alloc();
    c.data[0] = 0x71; // push 1
    c.bit_len = 8;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(i32, -14), vm.exit_code);
}

test "XCHG swap top two" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x71; // push 1
    c.data[1] = 0x72; // push 2
    c.data[2] = 0x01; // XCHG s0, s1
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    const top = try (try vm.stack.pop()).asInt();
    const bot = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 1), top.toI64());
    try std.testing.expectEqual(@as(i64, 2), bot.toI64());
}

test "DEPTH pushes stack depth" {
    var arena = CellArena.init();
    var vm = TVM.init(&arena);
    vm.setGas(100000);

    const c = try arena.alloc();
    c.data[0] = 0x71; // push 1
    c.data[1] = 0x72; // push 2
    c.data[2] = 0x60; // DEPTH
    c.bit_len = 24;

    vm.setCode(c);
    vm.run();

    try std.testing.expectEqual(@as(u32, 3), vm.stack.depth);
    const depth = try (try vm.stack.pop()).asInt();
    try std.testing.expectEqual(@as(i64, 2), depth.toI64());
}
