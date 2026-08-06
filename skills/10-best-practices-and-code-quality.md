# 10 — Best Practices & Code Quality

## Overview

This document defines the coding standards, MLIR-specific idioms, and quality gates that all AscendNPU-IR contributors must follow. Adhering to these practices produces code that is correct, maintainable, and performant — with zero production bugs.

---

## C++ Standards

### Language Version
- C++17 throughout. C++20 features are not yet permitted until the LLVM submodule is updated.
- Use `std::optional`, `std::string_view`, structured bindings, `if constexpr`.

### Naming Conventions

| Entity | Convention | Example |
|---|---|---|
| Types / Classes | `UpperCamelCase` | `HFusionFusionPass` |
| Functions / Methods | `lowerCamelCase` | `getIterationDomain()` |
| Variables | `lowerCamelCase` | `inputBuffer` |
| Constants | `kUpperCamelCase` | `kMaxTileSize` |
| Macros | `UPPER_SNAKE_CASE` | `BISHENGIR_ASSERT` |
| Files | `UpperCamelCase.cpp` / `.h` | `HFusionOps.cpp` |

### The Most Important C++ Rules

1. **No raw owning pointers**: Use `std::unique_ptr`, `std::shared_ptr`, or MLIR's value-owned data structures (`SmallVector`, `DenseMap`).

2. **Prefer `const` everywhere**: Every function parameter that is not mutated should be `const`. Every member function that does not modify state should be `const`.

3. **Never use `assert()` in library code**: Use MLIR's `verify()` methods or `emitOpError()`/`signalPassFailure()` for recoverable errors. Use `report_fatal_error()` only for truly unrecoverable programming errors.

4. **No silent truncation or overflow**: Explicit cast assertions or use `llvm::checkedAdd` / `llvm::checkedMul` for size arithmetic.

5. **RAII everywhere**: Every resource acquisition (buffer allocation, file handle, lock) must be wrapped in an RAII object.

6. **`[[nodiscard]]` on `LogicalResult`-returning functions**: Callers must not ignore failure returns.

---

## MLIR-Specific Idioms

### Correct Way to Check Type
```cpp
// BAD: isa<> predicate used without extracting the typed value
if (isa<RankedTensorType>(value.getType())) {
  // still have to cast separately — redundant check
  auto tensorType = cast<RankedTensorType>(value.getType());
}

// GOOD: assert-style cast (use when you know it must succeed)
auto tensorType = cast<RankedTensorType>(value.getType());

// GOOD: returns nullptr on failure (use when checking is needed)
auto tensorType = dyn_cast<RankedTensorType>(value.getType());
if (!tensorType) return emitOpError("expected ranked tensor type");

// GOOD: predicate only
if (!isa<RankedTensorType>(value.getType())) { ... }
```

### Correct Way to Build Ops
```cpp
// Always use OpBuilder; never construct ops with raw constructors
OpBuilder builder(op);
builder.setInsertionPointAfter(op);
auto newOp = builder.create<HFusion::MyOp>(op.getLoc(), resultType, operands);
```

### Correct Way to Modify IR in a Pass
```cpp
// In a ConversionPattern, use ConversionPatternRewriter
struct MyPattern : public OpConversionPattern<HFusion::MyOp> {
  LogicalResult matchAndRewrite(HFusion::MyOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<HIVM::Equivalent>(op, /* args */);
    return success();
  }
};

// In a RewritePattern (transform pass), use PatternRewriter
struct MyRewrite : public OpRewritePattern<HFusion::MyOp> {
  LogicalResult matchAndRewrite(HFusion::MyOp op,
                                PatternRewriter &rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};
```

### Never Access Operation Results After Replacing the Op
```cpp
// BAD: result is invalid after replaceOp
Value result = op.getResult(0);
rewriter.replaceOp(op, newOp);
use(result);  // USE AFTER REPLACE — UB

// GOOD: capture needed values before replacing
Value result = op.getResult(0);
auto users = llvm::to_vector(result.getUsers());  // capture users first
rewriter.replaceOp(op, newOp);
// now work with users
```

---

## Code Review Checklist

Use this checklist when reviewing or submitting code:

### Correctness
- [ ] Does the code handle all valid inputs, including edge cases (zero-size, scalars, large shapes)?
- [ ] Are all error paths handled with proper `emitOpError` / `signalPassFailure`?
- [ ] Does `verify()` catch all forms of malformed IR?
- [ ] Are DMA barriers placed correctly (DMA precedes compute, barrier between them)?
- [ ] Is memory freed after every allocation (on-chip buffers, external allocations)?

### MLIR Idioms
- [ ] All type checks use `isa<>` / `dyn_cast<>` / `cast<>` correctly?
- [ ] `OpBuilder` used for all op creation?
- [ ] `PatternRewriter` or `ConversionPatternRewriter` used for IR mutation?
- [ ] No use of raw MLIR `Operation*` pointer arithmetic?
- [ ] `[[nodiscard]]` on all `LogicalResult`-returning functions?

### Testing
- [ ] Is there a FileCheck round-trip test?
- [ ] Are negative verifier tests present?
- [ ] Are edge cases tested?
- [ ] If this is a bug fix, is there a regression test?

### Documentation
- [ ] TableGen `summary` and `description` fields filled in?
- [ ] Public header functions documented with Doxygen-style comments?
- [ ] User-visible changes reflected in `docs/`?

### Build
- [ ] `CMakeLists.txt` correctly declares all `DEPENDS` and `LINK_LIBS`?
- [ ] All new source files added to the corresponding `CMakeLists.txt`?
- [ ] No new compiler warnings (build with `-Wall -Wextra`)?
- [ ] `clang-format` applied?
- [ ] `clang-tidy` clean?

---

## Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Correct Alternative |
|---|---|---|
| Using `llvm_unreachable` in library code | Silent crash with no diagnostic | `report_fatal_error` or `emitOpError` |
| Returning `nullptr` from `Type`-returning functions | Propagates invalid state silently | Return `LogicalResult` failure or use `Optional<Type>` |
| Modifying the use-def chain outside a rewriter | Corrupts the IR | Use `PatternRewriter` or `ConversionPatternRewriter` |
| Storing `Operation*` across rewrite steps | Pointer may be invalidated | Work directly on local scope; re-query after rewrites |
| `SmallVector` with no size hint | Unnecessary heap allocation for small sizes | `SmallVector<Type, 4>` with appropriate hint |
| `std::map` for IR-adjacent data | High overhead for pointer-keyed maps | `DenseMap<Value, ...>` or `DenseSet<Operation *>` |
| `dynamic_cast` on MLIR types | RTTI is disabled in LLVM builds | Use MLIR's `isa<>` / `dyn_cast<>` system |

---

## Memory Management in MLIR

- `MLIRContext` owns all `Type`, `Attribute`, and `Identifier` objects. Never `delete` them.
- `Operation` objects are owned by their parent `Block`. Use `op->erase()` or a rewriter to remove them.
- `Block` objects are owned by their parent `Region`. Use `block->erase()` or a rewriter.
- `Region` objects are owned by their parent `Operation`.
- `Value` (SSA values) are lightweight view objects; they are valid as long as the owning `Operation` or `Block` exists.

When in doubt: **do not manage memory manually in MLIR IR code.** Let the IR ownership hierarchy handle it, and use a `PatternRewriter` for all modifications.
