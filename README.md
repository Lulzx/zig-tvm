# zig-tvm

A compact, table-driven implementation of the [TON Virtual Machine](https://docs.ton.org/tvm.pdf) (TVM) in Zig.

## Features

- 257-bit signed integer arithmetic (sign-magnitude, 4×u64 limbs)
- Cell/Slice/Builder for TVM data serialization (up to 1023 bits, 4 refs)
- Arena-allocated cells with free-list allocation
- Comptime-generated 256-entry dispatch table with 60+ opcode handlers
- Stack, arithmetic, cell, control flow, tuple, and exception instructions
- Gas accounting and continuation-based control flow
- BOC (Bag of Cells) deserialization

## Build

Requires Zig 0.15+.

```sh
zig build        # build executable
zig build test   # run all tests
```

## Usage

```sh
zig-tvm [options] <boc-file>

Options:
  --gas-limit N    Set gas limit (default: 1000000)
  --verbose        Enable verbose output
  --help, -h       Show this help
```

## Example

```sh
$ zig-tvm --verbose sample.boc
TVM initialized: gas_limit=1000000, code_bits=24
exit_code: 0
gas_used: 78
stack_depth: 1
result: 8
```

## Project Structure

```
src/
├── cell.zig   # Int257, Cell, CellArena, Slice, Builder
├── tvm.zig    # Stack, Value, Continuation, TVM exec loop
├── ops.zig    # Comptime dispatch tables, opcode handlers
└── main.zig   # CLI entry point, BOC deserialization
```
