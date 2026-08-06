# 04 — HFusion Dialect

## Overview

HFusion is the mid-level, hardware-agnostic dialect in AscendNPU-IR. It represents fused computations over tensors using abstractions that are independent of specific Ascend hardware generations. The HFusion dialect is the primary workhorse for operator fusion, tiling, and scheduling.

Source locations:
- Headers: `bishengir/include/bishengir/Dialect/HFusion/`
- Implementation: `bishengir/lib/Dialect/HFusion/`
- Tests: `bishengir/test/Dialect/HFusion/`

---

## Design Goals

1. **Hardware-agnostic**: HFusion ops have well-defined tensor algebra semantics; they do not reference on-chip memory addresses or DMA ops.
2. **Fusion-first**: Ops are designed to be fusible. The HFusion dialect provides fusion pattern infrastructure that identifies and merges eligible op clusters.
3. **Tileable**: Every compute op implements `TilingInterface` so the tiling pass can query tile sizes and generate tiled loops automatically.
4. **Scheduled**: HFusion carries scheduling annotations that control loop order, parallelism, and vectorisation hints.

---

## Key Op Categories

### Elementwise Ops
Operations that apply a scalar function element-by-element over tensors:
```mlir
%out = hfusion.elemwise(%a, %b) {op_kind = "add"} :
  (tensor<1024xf16>, tensor<1024xf16>) -> tensor<1024xf16>
```

### Broadcast Ops
Expand a lower-rank tensor to match a higher-rank tensor:
```mlir
%out = hfusion.broadcast(%a) {expand_dims = [0]} :
  (tensor<1024xf16>) -> tensor<32x1024xf16>
```

### Reduction Ops
Reduce along one or more axes:
```mlir
%out = hfusion.reduce(%a) {axes = [1], keep_dims = false, op_kind = "sum"} :
  (tensor<32x1024xf16>) -> tensor<32xf32>
```

### MatMul Ops
High-level matrix multiplication:
```mlir
%out = hfusion.matmul(%a, %b) {transpose_a = false, transpose_b = true} :
  (tensor<32x64xf16>, tensor<128x64xf16>) -> tensor<32x128xf32>
```

### Fusion Cluster (Region Op)
Groups a fusible cluster of ops into a single region for collective lowering:
```mlir
%out = hfusion.fusion_cluster(%a, %b) {
  // Fused sub-graph: add followed by relu
  %tmp = hfusion.elemwise(%a, %b) {op_kind = "add"} : ...
  %relu = hfusion.elemwise(%tmp) {op_kind = "relu"} : ...
  hfusion.yield %relu : tensor<1024xf16>
} : (tensor<1024xf16>, tensor<1024xf16>) -> tensor<1024xf16>
```

---

## Operator Fusion

### Fusion Eligibility Rules
Two ops are fusible when:
1. The producer's output is consumed only by the candidate consumer (no other uses).
2. Their combined memory footprint fits within the on-chip buffer budget.
3. The operations belong to compatible compute categories (elementwise–elementwise, elementwise–broadcast, etc.).
4. No control-flow boundary separates them.

### Fusion Pattern Infrastructure
```
bishengir/lib/Dialect/HFusion/Transforms/FusionPatterns.cpp
```
Each fusion pattern is a `RewritePattern` that:
1. Matches a pair (or cluster) of fusible ops.
2. Checks eligibility constraints (buffer budget, op compatibility).
3. Creates a new `hfusion.fusion_cluster` op containing the merged ops.
4. Erases the individual ops.

**Best practice**: Keep each fusion pattern small and single-purpose. Complex multi-step fusions should be decomposed into a sequence of simple two-op fusion patterns.

---

## Tiling

### TilingInterface
Every tileable HFusion op must implement `TilingInterface`:
```cpp
// In the .td file:
def MyOp : HFusion_Op<"my_op", [DeclareOpInterfaceMethods<TilingInterface>]> {
  ...
}
```

`TilingInterface` requires implementing:
- `getIterationDomain()` — returns iteration space dimensions
- `getTiledImplementation(...)` — returns the tiled sub-op and surrounding loop structure
- `getResultTilePosition(...)` — computes output tile position given input tile

### Tiling Pass
The tiling pass (`--hfusion-tiling`) queries `TilingInterface` for each op and generates:
- `scf.for` or `scf.forall` loops at the appropriate granularity
- Sliced tensor operations matching the tile size

**Key rule**: Always test tiling correctness with edge-case tile sizes (tile size equals full dimension, tile size larger than dimension, non-divisible tile sizes).

---

## Scheduling

Scheduling in HFusion is expressed as loop-level annotations on the enclosing `scf.for` ops or as attributes on the `hfusion.fusion_cluster`:

```mlir
hfusion.fusion_cluster {schedule = #hfusion.schedule<parallel_outer = 1, vector_inner = 32>} ...
```

Scheduling hints are consumed by the HFusion → HIVM lowering to:
- Map outer loops to AICore parallel threads
- Map inner loops to vector pipeline stages
- Enable ping-pong double buffering when depth ≥ 2

---

## Common Patterns

### Pattern: Elementwise Chain Fusion
```mlir
// Before fusion:
%add = hfusion.elemwise(%a, %b) {op_kind = "add"} : ...
%relu = hfusion.elemwise(%add)  {op_kind = "relu"} : ...
%out  = hfusion.elemwise(%relu, %c) {op_kind = "mul"} : ...

// After fusion (single cluster, one on-chip pass):
%out = hfusion.fusion_cluster(%a, %b, %c) {
  %t1 = hfusion.elemwise(%a, %b) {op_kind = "add"} : ...
  %t2 = hfusion.elemwise(%t1)    {op_kind = "relu"} : ...
  %r  = hfusion.elemwise(%t2, %c) {op_kind = "mul"} : ...
  hfusion.yield %r : tensor<...>
} : ...
```

### Pattern: Reduce with Pre-Fusion Elementwise
```mlir
// sqrt(sum(x^2)) — fuse the square into the reduction
%out = hfusion.fusion_cluster(%x) {
  %sq  = hfusion.elemwise(%x) {op_kind = "square"} : ...
  %sum = hfusion.reduce(%sq) {axes = [0], op_kind = "sum"} : ...
  %r   = hfusion.elemwise(%sum) {op_kind = "sqrt"} : ...
  hfusion.yield %r : tensor<...>
} : ...
```

---

## Verifier Checklist for HFusion Ops

- [ ] All tensor shapes are fully static or have dynamic-size constraints documented in `verify()`
- [ ] The fusion cluster's region has exactly one `hfusion.yield` terminator
- [ ] Ops inside a fusion cluster do not have external uses (only `hfusion.yield` escapes)
- [ ] `TilingInterface` is implemented and returns correct tile positions for all dynamic shapes
- [ ] Scheduling annotations are valid (parallel factor ≤ number of AIcores, vector width is a power of 2)
