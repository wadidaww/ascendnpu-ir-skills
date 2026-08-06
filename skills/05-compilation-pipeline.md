# 05 — Compilation Pipeline

## Overview

The AscendNPU-IR compilation pipeline transforms high-level AI framework computation into an executable Ascend NPU binary through a sequence of well-defined passes. Understanding the complete pipeline is essential for diagnosing failures, adding new passes, and optimising performance.

---

## Pipeline Stages

```
Framework IR (Arith / Linalg / Torch / Triton)
         │
         │  Frontend conversion passes
         ▼
    HFusion IR
         │
         │  HFusion optimisation passes
         ▼
    HFusion IR (optimised, tiled, scheduled)
         │
         │  HFusion → HIVM lowering passes
         ▼
     HIVM IR
         │
         │  HIVM lowering + bufferization
         ▼
  HIVM IR (bufferized, memory allocated)
         │
         │  Backend code generation
         ▼
  Ascend NPU binary (.bin / kernel object)
```

---

## Stage 1 — Frontend Conversion

**Input**: Framework dialect IR (arith, linalg, tensor, torch, triton)
**Output**: HFusion dialect IR

### Key Passes

| Pass | Description |
|---|---|
| `convert-linalg-to-hfusion` | Lower `linalg.generic` into HFusion elementwise/reduction/matmul ops |
| `convert-arith-to-hfusion` | Map scalar `arith` ops into HFusion elementwise equivalents |
| `convert-torch-to-hfusion` | PyTorch ATen ops → HFusion (via torch-mlir integration) |
| `convert-triton-to-hfusion` | Triton kernel dialect → HFusion (in `bishengir/triton/`) |
| `hfusion-normalize` | Canonicalize shapes, types, and op forms post-conversion |

### Tips
- Framework conversion is the most common location for new operator coverage gaps.
- When a framework op has no lowering, `convert-*-to-hfusion` passes emit a `hfusion.op_unsupported` placeholder that blocks compilation with a clear error.
- Test frontend conversions with small, isolated FileCheck tests that verify the exact HFusion IR produced.

---

## Stage 2 — HFusion Optimisation

**Input**: Normalised HFusion IR
**Output**: Optimised, tiled, and scheduled HFusion IR

### Key Passes (ordered)

| Pass | Description |
|---|---|
| `hfusion-canonicalize` | Fold constants, apply algebraic simplifications |
| `hfusion-shape-inference` | Propagate static shape information |
| `hfusion-type-promotion` | Promote types for numerical stability (e.g., fp16 → fp32 accumulation) |
| `hfusion-fusion` | Identify and merge fusible op clusters |
| `hfusion-tiling` | Apply tile-and-loop-generate transformation via `TilingInterface` |
| `hfusion-scheduling` | Assign parallelism and vectorisation schedule annotations |
| `hfusion-layout-opt` | Optimise memory layout for the target memory hierarchy |

### Pass Ordering Rules
- **Fusion before tiling**: Fuse ops at the tensor-level before tiling; tiling fused ops together avoids redundant memory transfers.
- **Shape inference before fusion**: Fusion eligibility checks depend on known shapes.
- **Scheduling after tiling**: Schedule annotations reference tiled loop structure.
- **Canonicalization first and last**: Run canonicalization at the start to simplify input and at the end to clean up artefacts.

---

## Stage 3 — HFusion → HIVM Lowering

**Input**: Scheduled HFusion IR
**Output**: HIVM IR (hardware-specific, no tensors)

### Key Passes

| Pass | Description |
|---|---|
| `convert-hfusion-to-hivm` | Main dialect conversion: maps HFusion ops to HIVM compute and DMA ops |
| `hfusion-bufferize` | Tensor → memref conversion (one-shot bufferization) |
| `hivm-alloc-buffers` | Allocate on-chip buffers for each tiled slice |
| `hivm-insert-dma` | Insert DMA ops for each on-chip buffer fill and drain |
| `hivm-insert-barriers` | Insert `dma_wait` and `pipe_barrier` ops |
| `hivm-pipeline-transform` | Transform double-buffered loops into ping-pong pipeline form |

### Common Failure Points
1. **Bufferization failure**: Type mismatch between tensor and memref shapes — check that shapes are fully resolved before bufferization.
2. **Missing DMA insertion**: HFusion op uses data from global memory but the lowering forgets to insert DMA — always run `hivm-verify` after lowering to catch missing ops.
3. **Wrong barrier placement**: Barriers inserted after the compute that needed them — use `--mlir-print-ir-after-all` to trace barrier insertion.

---

## Stage 4 — HIVM Backend

**Input**: HIVM IR with explicit memory, DMA, and synchronisation
**Output**: Ascend NPU binary

This stage is handled by the CANN backend (outside the open-source scope of AscendNPU-IR). The HIVM IR is serialised and passed to the Ascend binary compiler.

---

## Running the Pipeline

### Using `bishengir-opt` (development / testing)
```bash
# Run the full compilation pipeline
bishengir-opt \
  --pass-pipeline="builtin.module(
    convert-linalg-to-hfusion,
    hfusion-normalize,
    hfusion-canonicalize,
    hfusion-shape-inference,
    hfusion-fusion,
    hfusion-tiling{tile-sizes=32,32},
    hfusion-scheduling,
    hfusion-bufferize,
    convert-hfusion-to-hivm,
    hivm-alloc-buffers,
    hivm-insert-dma,
    hivm-insert-barriers,
    hivm-pipeline-transform
  )" \
  input.mlir -o output.mlir
```

### Inspecting Intermediate IR
```bash
# Print IR after every pass — essential for debugging
bishengir-opt --mlir-print-ir-after-all --pass-pipeline="..." input.mlir 2>&1 | less
```

### Verifying at Each Stage
```bash
# Verify HIVM IR correctness
bishengir-opt --hivm-verify output.mlir
```

---

## Pipeline Debugging Checklist

When a pass fails or produces wrong output:

1. **Isolate the failing pass**: Bisect the pass pipeline — remove later passes and check if the earlier output is correct.
2. **Dump IR before the failing pass**: Use `--mlir-print-ir-before=<pass-name>` to see what the pass receives.
3. **Run the verifier**: Add `--verify-each` to validate IR after every pass — catches IR corruption early.
4. **Check op legality**: Dialect conversion passes have legality tables; illegal ops cause generic "no conversion" errors. Print the legality tables with `--debug-only=dialect-conversion`.
5. **Look for missed patterns**: Conversion/rewrite patterns are selected by root op type. If an op is not being lowered, verify the pattern is registered with the correct op class.

---

## Adding a New Pass to the Pipeline

1. Define the pass in a `.td` file under `include/bishengir/Pass/`.
2. Implement in `lib/Pass/` or the relevant `lib/Transforms/` subdirectory.
3. Register the pass with `mlir::registerPass()` in the pass library's `CMakeLists.txt` dependency chain.
4. Add the pass to the default pipeline in the appropriate pipeline builder.
5. Write a FileCheck test covering: nominal case, edge cases (empty tensor, zero tile size), and verifier-failure cases.
