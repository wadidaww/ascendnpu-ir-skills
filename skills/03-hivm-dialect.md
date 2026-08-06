# 03 — HIVM Dialect

## Overview

HIVM (Hardware Intermediate Virtual Machine) is the lowest-level dialect in AscendNPU-IR. It models Ascend NPU hardware resources directly and is the final IR stage before hardware binary emission.

Source locations:
- Headers: `bishengir/include/bishengir/Dialect/HIVM/`
- Implementation: `bishengir/lib/Dialect/HIVM/`
- Tests: `bishengir/test/Dialect/HIVM/`

---

## Core Concepts

### Memory Spaces

HIVM assigns every buffer to a named memory space attribute:

| Memory Space | Symbol | Characteristics |
|---|---|---|
| Global Memory | `gm` | Off-chip DDR/HBM; large, highest latency |
| L1 Buffer | `l1` | On-chip; large, configurable partition |
| L0A Buffer | `l0a` | Input matrix operand buffer for Cube unit |
| L0B Buffer | `l0b` | Weight / second input for Cube unit |
| L0C Buffer | `l0c` | Accumulation buffer for Cube unit output |
| Unified Buffer | `ub` | On-chip; used by Vector unit for input/output |

Always declare the memory space in `memref` types explicitly:
```mlir
%buf = hivm.alloc_buffer() : memref<1024xf16, #hivm.mem_space<ub>>
```

### Compute Units

| Unit | Purpose | Ops |
|---|---|---|
| Vector Unit | Elementwise, reduction, transcendental | `VAddOp`, `VMulOp`, `VCmpOp`, `VCastOp`, `VReduceOp`, … |
| Cube Unit | Matrix multiplication (GEMM) | `MmadOp`, `MmadInitOp`, … |
| DMA Engine | Data movement between memory spaces | `DmaCopyOp`, `DmaGm2L1Op`, `DmaL0C2UbOp`, … |

---

## Key Op Categories

### 1. Buffer Allocation
```mlir
// Allocate on-chip buffer
%ub_buf = hivm.alloc_buffer() : memref<256xf16, #hivm.mem_space<ub>>
// Free when done
hivm.free_buffer %ub_buf : memref<256xf16, #hivm.mem_space<ub>>
```

### 2. DMA Data Movement
```mlir
// Move data from global memory to L1
hivm.dma_gm2l1 %src[%off] -> %dst[%doff], %len
    : (memref<?xf16, #hivm.mem_space<gm>>,
       memref<256xf16, #hivm.mem_space<l1>>) -> ()

// Move data from UB back to global memory
hivm.dma_ub2gm %src[%soff] -> %dst[%doff], %len
    : (memref<256xf16, #hivm.mem_space<ub>>,
       memref<?xf16, #hivm.mem_space<gm>>) -> ()
```

### 3. Vector Compute
```mlir
// Elementwise addition on UB
hivm.vadd %a, %b -> %c
    : (memref<256xf16, #hivm.mem_space<ub>>,
       memref<256xf16, #hivm.mem_space<ub>>,
       memref<256xf16, #hivm.mem_space<ub>>)
```

### 4. Cube (Matrix) Compute
```mlir
// GEMM: accumulate C += A * B
hivm.mmad %a : memref<16x16xf16, #hivm.mem_space<l0a>>,
              %b : memref<16x16xf16, #hivm.mem_space<l0b>>,
              %c : memref<16x16xf32, #hivm.mem_space<l0c>>
```

### 5. Synchronisation
```mlir
// Wait for all prior DMA ops to complete before computing
hivm.dma_wait
// Wait for vector compute to finish before next DMA
hivm.pipe_barrier {stages = ["vec", "dma"]}
```

### 6. Pipeline Annotations (Ping-Pong)
```mlir
// Double-buffer annotation: overlap compute and DMA
hivm.pipeline.begin {depth = 2}
  // ... tiled loop body ...
hivm.pipeline.end
```

---

## Critical Rules for HIVM Development

1. **Explicit memory spaces on every buffer**: Never use unqualified `memref` in HIVM code. The memory space determines which DMA path and which compute unit can access the buffer.

2. **Always insert barriers**: The Ascend NPU has asynchronous DMA and compute engines. Missing a `dma_wait` or `pipe_barrier` before accessing data that is being DMA-transferred causes data races and non-deterministic results.

3. **Align buffer sizes to hardware granularity**: Vector ops operate on 32-byte (or hardware-specific) aligned chunks. Buffers must satisfy alignment requirements defined in the target hardware spec.

4. **Never mix memory spaces in a single op**: Each vector/cube op has defined memory space requirements. Violating them generates incorrect code without necessarily triggering a compile error.

5. **Pipeline depth must match double-buffer count**: If `pipeline.begin {depth = 2}` is used, exactly two buffer sets must be allocated for the ping-pong pattern.

---

## HIVM Verifier Checks

The HIVM dialect's `verify()` methods enforce hardware constraints at compile time:
- Memory space compatibility with op requirements
- Buffer size alignment
- DMA transfer size limits
- Barrier ordering (DMA barriers before vector ops that use DMA-filled buffers)

Always run `--mlir-print-op-on-diagnostic` during development to get the exact op that fails verification.

---

## Debugging HIVM IR

```bash
# Dump IR after every pass in the HIVM lowering pipeline
bishengir-opt --pass-pipeline="..." \
  --mlir-print-ir-after-all \
  input.mlir

# Check a specific HIVM pass in isolation
bishengir-opt --hivm-lower-dma input.mlir | FileCheck test.mlir.check
```

When the HIVM IR looks wrong:
1. Check that all memory space attributes are correct.
2. Verify that DMA ops precede the compute ops that consume their results.
3. Verify barrier placement around every DMA/compute boundary.
4. Check alignment constraints for vector/cube buffer dimensions.

---

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Missing `dma_wait` | Non-deterministic output on hardware | Insert `hivm.dma_wait` after every DMA into UB before vector compute |
| Wrong memory space | Verifier error or hardware fault | Use correct `#hivm.mem_space<...>` on every memref |
| Buffer not freed | On-chip memory leak / compilation failure | Always pair `alloc_buffer` with `free_buffer` |
| Unaligned transfer size | Hardware DMA error | Round transfer sizes to hardware granularity (often 32 bytes) |
| Missing pipeline annotation | Sub-optimal performance (no DMA/compute overlap) | Wrap tiled loop with `pipeline.begin/end` |
