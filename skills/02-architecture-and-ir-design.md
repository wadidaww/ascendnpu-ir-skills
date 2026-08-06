# 02 — Architecture & IR Design

## Overview

AscendNPU-IR is a **multi-level IR** sitting between AI-framework computation graphs and Ascend NPU hardware instructions. It inherits MLIR's progressive-lowering philosophy and organises abstractions into three tiers:

```
┌─────────────────────────────────────────────────────────┐
│  Framework Tier  (Arith, Linalg, Torch, Triton dialects) │  High-level semantics
├─────────────────────────────────────────────────────────┤
│  HFusion Tier    (HFusion dialect)                       │  Fusion + scheduling
├─────────────────────────────────────────────────────────┤
│  HIVM Tier       (HIVM dialect)                          │  Hardware mapping
└─────────────────────────────────────────────────────────┘
           ▼ compilation + lowering
      Ascend NPU binary
```

---

## MLIR Foundations (Must Know)

AscendNPU-IR is built on MLIR. Developers **must** be fluent in these MLIR concepts:

| MLIR Concept | Relevance to AscendNPU-IR |
|---|---|
| `Operation` / `Op` | Every computation is an `Op` — even dialect-specific ones |
| `Region` / `Block` | Control flow and structured ops (loops, functions) |
| `Type` | Tensor, memref, and custom HIVM types |
| `Attribute` | Compile-time constants, hardware config, tiling parameters |
| `Dialect` | Namespaced op/type/attribute collections (HFusion, HIVM) |
| `PatternRewrite` | Transformation via `RewritePattern` / `ConversionPattern` |
| `Pass` | Unit of transformation; composed into pipelines |
| `Interface` | Abstract op behaviour contracts (e.g., `TilingInterface`) |
| `TableGen` `.td` | Declarative op/type definitions, auto-generates C++ boilerplate |
| `DialectConversion` | Structured framework for dialect-to-dialect lowering |
| `Bufferization` | Tensor → memref lowering; critical for memory layout |

---

## The Three-Tier Dialect Architecture

### Tier 1 — Framework Dialects (Input)

These are **upstream MLIR dialects** or custom frontends:

- `arith` — scalar arithmetic
- `linalg` — generic tensor algebra
- `tensor` / `memref` — buffer and tensor types
- `torch` — PyTorch frontend via torch-mlir
- Triton kernel dialect (in `bishengir/triton/`)

Developers generally do **not** modify these; they write conversion passes that lower them into HFusion.

### Tier 2 — HFusion Dialect (Mid-Level)

**Purpose**: Represent Ascend-aware fused computations with hardware-agnostic semantics.

Key responsibilities:
- Operator fusion (elementwise, broadcast, reduction fusion)
- Pattern matching for fusible op clusters
- Tiling and scheduling annotations
- Layout and data-flow optimisation

**Design principle**: HFusion ops have well-defined tile-and-schedule semantics. They implement `TilingInterface` so the tiling pass can query and apply tile strategies uniformly.

### Tier 3 — HIVM Dialect (Hardware-Level)

**Purpose**: Directly model Ascend hardware resources and instructions.

Key responsibilities:
- Explicit on-chip memory management (GM, L1, L0, UB memory spaces)
- DMA data-movement ops
- Vector and Cube (matrix) compute ops
- Pipeline synchronisation (`BarrierOp`, ping-pong buffer management)
- Hardware-specific type system (e.g., half-precision, integer quantisation types)

---

## Key Architectural Principles

### 1. Progressive Lowering
Every lowering step is a well-defined pass. No single pass does too much. Each step should:
- Preserve semantic correctness
- Be independently testable with FileCheck
- Not assume knowledge of subsequent passes

### 2. Separation of Concerns
- **What to compute** → HFusion
- **How to compute on hardware** → HIVM
- **How to move data** → DMA ops in HIVM
- **When to synchronise** → barrier/pipeline ops in HIVM

### 3. Hardware-Aware but Not Hardware-Locked
HFusion is intentionally hardware-agnostic. Hardware-specific decisions are deferred to the HFusion → HIVM lowering. This means a single HFusion representation can target different Ascend hardware generations by swapping the HIVM lowering pass.

### 4. Open Interface Design
Public interfaces (`include/bishengir/`) expose stable abstractions. Internal implementation details (`lib/`) are not part of the public API. External integrators (frameworks, tools) consume the public API only.

### 5. Composable Pass Pipelines
Passes are small and composable. Complex transformations are expressed as ordered pass pipelines, not monolithic transforms. This makes it easy to:
- Add or remove optimisation stages
- Run partial pipelines for testing
- Parallelise independent passes

---

## IR Design Checklist (When Adding a New Op or Dialect)

- [ ] Is the op at the right abstraction level (HFusion vs HIVM)?
- [ ] Does the op have a precise, documented semantic contract?
- [ ] Are all type constraints expressed in TableGen?
- [ ] Does the op implement the relevant `Interface`s (`TilingInterface`, etc.)?
- [ ] Is there a `verify()` method that catches malformed ops at IR construction time?
- [ ] Are there FileCheck tests for the op's textual IR form?
- [ ] Are there lowering tests that verify the op is correctly lowered to the next tier?
- [ ] Are edge cases (zero-sized tensors, broadcasting, type promotion) handled?

---

## Memory Hierarchy Reference

Understanding Ascend's memory hierarchy is essential for HIVM-level work:

```
┌────────────────────────────────────────────────────────┐
│  Global Memory (GM / DDR / HBM)  — large, slow         │
│                                                        │
│   ┌─────────────────────────────────────────────────┐  │
│   │  L1 Buffer  — on-chip, large, configurable      │  │
│   │   ┌───────────────┐  ┌───────────────────────┐  │  │
│   │   │  L0A (input)  │  │  L0B (weight/input2)  │  │  │
│   │   │  L0C (output) │  │  UB (unified buffer)  │  │  │
│   │   └───────────────┘  └───────────────────────┘  │  │
│   └─────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

Each memory space has different bandwidth and latency characteristics. DMA ops must explicitly move data between levels. Incorrect memory placement is a primary source of both correctness bugs and performance regressions.
