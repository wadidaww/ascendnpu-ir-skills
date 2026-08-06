# 11 — System Design Patterns

## Overview

This document captures the key system design patterns used in AscendNPU-IR and the principles that underpin them. Understanding these patterns enables developers to design new subsystems that integrate cleanly with the existing architecture and scale well.

---

## Pattern 1 — Dialect Layering

**Problem**: A compiler for a complex hardware target needs multiple levels of abstraction, from framework semantics to hardware instructions.

**Solution**: Organise abstractions into named dialects. Each dialect owns its op namespace, types, and attributes. Lowering between dialects is explicit and testable.

**In AscendNPU-IR**:
```
Framework dialects → HFusion dialect → HIVM dialect → binary
```

**Design Rules**:
- A higher-level dialect **must not** reference types or ops from a lower-level dialect.
- Lowering passes are **unidirectional**: they go from higher to lower, never in reverse.
- Each dialect is independently loadable into an `MLIRContext` — no implicit cross-dialect dependencies at load time.
- Dialect loading order in production pipelines must be explicit (`context.loadDialect<...>()`).

---

## Pattern 2 — Interface-Based Extensibility

**Problem**: The tiling pass needs to tile many different op types, but adding a switch-case over every op type creates a maintenance nightmare and violates the Open/Closed Principle.

**Solution**: Define an `OpInterface` that each tileable op implements. The pass operates on the interface, not on concrete op types.

**In AscendNPU-IR**:
```cpp
// Interface definition (TableGen)
def TilingInterface : OpInterface<"TilingInterface"> {
  let methods = [
    InterfaceMethod<"Get iteration domain", "SmallVector<Range>", "getIterationDomain", ...>,
    InterfaceMethod<"Get tiled implementation", "FailureOr<TilingResult>", "getTiledImplementation", ...>
  ];
}

// Pass operates on the interface
for (auto op : func.getOps()) {
  if (auto tileable = dyn_cast<TilingInterface>(op)) {
    auto tiledResult = tileable.getTiledImplementation(rewriter, tileSizes);
    // ...
  }
}
```

**When to define a new interface**:
- When 3+ op types share the same abstract behaviour.
- When the behaviour must be queryable by a pass that should not depend on concrete op types.
- When external dialects might want to implement the same behaviour.

**Never** use a `TypeSwitch` or `if/else if` chain over op types inside a pass — this is an anti-pattern that breaks extensibility.

---

## Pattern 3 — Conversion Framework (Dialect Lowering)

**Problem**: Lowering every possible HFusion op type to HIVM requires matching many specific op types and applying type-specific transformations.

**Solution**: MLIR's `DialectConversion` framework. Define a legality predicate and register one `ConversionPattern` per source op. The framework orchestrates the matching and rewriting.

**Key Components**:
```cpp
// 1. ConversionTarget: defines what is legal after conversion
ConversionTarget target(ctx);
target.addLegalDialect<HIVM::HIVMDialect>();
target.addIllegalDialect<HFusion::HFusionDialect>();

// 2. TypeConverter: maps HFusion types to HIVM types
TypeConverter typeConverter;
typeConverter.addConversion([](RankedTensorType t) -> MemRefType {
  return MemRefType::get(t.getShape(), t.getElementType());
});

// 3. Patterns: one per source op
RewritePatternSet patterns(&ctx);
patterns.add<MyOpLowering>(typeConverter, &ctx);

// 4. Apply conversion
if (failed(applyFullConversion(func, target, std::move(patterns))))
  return signalPassFailure();
```

**Rules**:
- Always prefer `applyFullConversion` (all ops must be legal after) over `applyPartialConversion` (allows illegal ops to remain). Partial conversion is only appropriate for incremental multi-step lowering.
- The `ConversionTarget` is the source of truth for what is allowed at each pipeline stage.
- TypeConverters must be deterministic and bijective (for types used in both directions).

---

## Pattern 4 — Rewrite Pattern Priority

**Problem**: Multiple patterns may match the same op. Without careful ordering, lower-quality patterns may fire before better ones.

**Solution**: MLIR's pattern rewriting framework uses a benefit score. Higher benefit = higher priority.

```cpp
struct BetterFusionPattern : public OpRewritePattern<HFusion::ElemwiseOp> {
  BetterFusionPattern(MLIRContext *ctx)
      : OpRewritePattern(ctx, /*benefit=*/10) {}  // Higher priority
  // ...
};

struct GenericFusionPattern : public OpRewritePattern<HFusion::ElemwiseOp> {
  GenericFusionPattern(MLIRContext *ctx)
      : OpRewritePattern(ctx, /*benefit=*/1) {}   // Lower priority
  // ...
};
```

**Rules**:
- Default benefit is 1. Only increase it when a pattern is strictly more specific or better than a competing pattern.
- Do not rely on pattern registration order for determinism — use benefit instead.
- Patterns should be **convergent**: repeated application should not produce infinite rewrite loops. The framework detects non-convergence and terminates, but only after wasted work.

---

## Pattern 5 — Analysis Infrastructure

**Problem**: Multiple passes need the same information (e.g., which ops are live, what are the memory aliasing relationships). Recomputing per pass is wasteful and error-prone.

**Solution**: Implement analyses as `Analysis` classes that are cached by the `AnalysisManager`.

```cpp
// Define the analysis
struct BufferLivenessAnalysis {
  BufferLivenessAnalysis(Operation *op) {
    // Compute liveness for all ops in the region
  }
  bool isLive(Value v) const { return liveValues.contains(v); }
private:
  DenseSet<Value> liveValues;
};

// Use in a pass
void MyPass::runOnOperation() {
  auto &analysis = getAnalysis<BufferLivenessAnalysis>();
  if (analysis.isLive(someValue)) { ... }
}
```

**Rules**:
- Analyses are **immutable** once computed — they must not modify the IR.
- Mark analyses as `preserved` when a pass does not invalidate them:
  ```cpp
  markAnalysesPreserved<BufferLivenessAnalysis>();
  ```
- Invalidate analyses conservatively — when in doubt, do not preserve. Stale analyses cause silent correctness bugs.

---

## Pattern 6 — Bufferization

**Problem**: HFusion IR operates on tensors (value semantics). HIVM IR operates on memrefs (buffer semantics). The transition must not lose performance by copying data unnecessarily.

**Solution**: One-Shot Bufferization (`mlir::bufferization::runOneShotBufferize`) assigns each tensor operation to a buffer with precise aliasing and in-place analysis.

**Key principle**: Prefer in-place bufferization (reuse the input buffer for the output) when the input has no other uses after this op. This eliminates copies.

**Rules for op authors**:
- Implement `BufferizableOpInterface` for any HFusion op that has tensor operands.
- In `bufferize()`, create buffers using `bufferization::getBuffer()`, not raw `memref.alloc`.
- Use `analysis.aliasesOnly()` to check if an in-place buffer assignment is safe.
- Never allocate buffers in `bufferize()` unless the op genuinely needs new storage.

---

## System Design Checklist (New Subsystem)

Before implementing a new subsystem (dialect, pass, analysis, or tool):

- [ ] Is the abstraction level clearly defined and documented?
- [ ] Does it introduce a new dialect, or extend an existing one? (Prefer extending.)
- [ ] Are shared behaviours extracted into interfaces rather than hard-coded in the subsystem?
- [ ] Is the subsystem independently buildable and testable?
- [ ] Does it interact with the existing pass pipeline through the standard conversion framework?
- [ ] Are analyses separated from transforms?
- [ ] Is the public API minimal and stable? (Fewer public symbols = less maintenance burden.)
- [ ] Is the subsystem documented in `docs/` with its design rationale?
