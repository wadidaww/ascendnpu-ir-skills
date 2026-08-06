# 08 — Testing & Validation

## Overview

AscendNPU-IR uses a layered testing strategy:

| Layer | Tool | Purpose |
|---|---|---|
| Unit tests | Google Test | Test individual C++ functions and classes in isolation |
| Integration tests | LLVM `lit` + `FileCheck` | Validate IR transformations end-to-end at the IR level |
| E2E (hardware) tests | Custom runner | Execute compiled kernels on hardware/simulator and check outputs |

All three layers must be exercised for new features. The project will not accept PRs that add functionality without corresponding tests.

---

## Unit Tests (Google Test)

### Location
```
bishengir/unittests/
```

### Running
```bash
# Build and run all unit tests
cmake --build build --target check-bishengir-unit

# Run a specific test binary
./build/bin/MLIRBiShengIRHFusionTests --gtest_filter="HFusionOpTest.*"
```

### Writing Unit Tests
```cpp
// bishengir/unittests/Dialect/HFusion/HFusionOpTest.cpp
#include "bishengir/Dialect/HFusion/IR/HFusionDialect.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "gtest/gtest.h"

TEST(HFusionOpTest, VerifyRejectsWrongRank) {
  MLIRContext ctx;
  ctx.loadDialect<HFusion::HFusionDialect>();

  // Build an intentionally invalid op
  OpBuilder builder(&ctx);
  auto loc = builder.getUnknownLoc();
  auto scalarTy = RankedTensorType::get({}, builder.getF16Type());

  // Expect verify() to return failure for scalar input
  // ... (use MLIR's verifier test utilities)
}
```

**Rules for unit tests:**
- Test only the smallest unit of logic — one function or one op behaviour at a time.
- Use `EXPECT_TRUE(succeeded(...))` / `EXPECT_TRUE(failed(...))` for MLIR `LogicalResult`.
- Do not load unnecessary dialects in the `MLIRContext` — keep context setup minimal.
- Every `verify()` negative path must have a corresponding unit test.

---

## Integration Tests (FileCheck / lit)

### Location
```
bishengir/test/
├── Dialect/
│   ├── HFusion/     ← Tests for HFusion ops (round-trip, verify, fold)
│   └── HIVM/        ← Tests for HIVM ops
├── Conversion/
│   ├── HFusionToHIVM/   ← Tests for conversion passes
│   └── LinalgToHFusion/ ← Tests for frontend conversions
├── Transforms/          ← Tests for transforms (tiling, fusion, etc.)
└── Integration/         ← E2E tests
```

### Running
```bash
# Run all integration tests
cmake --build build --target check-bishengir

# Run a specific test directory
llvm-lit bishengir/test/Dialect/HFusion/ -v

# Run a single test file
llvm-lit bishengir/test/Dialect/HFusion/elemwise.mlir -v
```

### FileCheck Test Structure

```mlir
// RUN: bishengir-opt %s --hfusion-fusion | FileCheck %s
// RUN: bishengir-opt %s --hfusion-fusion | bishengir-opt | FileCheck %s --check-prefix=ROUNDTRIP

// Test that the fusion pass merges an add and a relu into one cluster
// CHECK-LABEL: func.func @test_fuse_add_relu
func.func @test_fuse_add_relu(%a: tensor<1024xf16>, %b: tensor<1024xf16>)
    -> tensor<1024xf16> {
  %add = hfusion.elemwise(%a, %b) {op_kind = "add"} :
      (tensor<1024xf16>, tensor<1024xf16>) -> tensor<1024xf16>
  %relu = hfusion.elemwise(%add) {op_kind = "relu"} :
      (tensor<1024xf16>) -> tensor<1024xf16>
  return %relu : tensor<1024xf16>
}
// CHECK: hfusion.fusion_cluster
// CHECK-NOT: hfusion.elemwise
// CHECK: hfusion.elemwise{{.*}}op_kind = "add"
// CHECK: hfusion.elemwise{{.*}}op_kind = "relu"

// ROUNDTRIP-LABEL: func.func @test_fuse_add_relu
```

### FileCheck Best Practices

1. **Test the transformation, not the printer format**: Use `CHECK` patterns that focus on semantically important IR features, not exact whitespace or arbitrary attribute ordering.

2. **Use `CHECK-LABEL` for function-scoped tests**: This anchors the check to a named function and makes the test independent of other functions in the file.

3. **Use `CHECK-NOT` to assert absence**: Verify that original ops are erased after lowering.

4. **Use `CHECK-DAG` for unordered matches**: When pass output order is non-deterministic (e.g., parallel canonicalization), use `CHECK-DAG` to match any order.

5. **Add `// expected-error` annotations for verifier tests**:
```mlir
// RUN: bishengir-opt %s --verify-diagnostics

func.func @invalid(%a: tensor<1xf16>) -> tensor<2xf16> {
  // expected-error@+1 {{input and output shapes must match}}
  %out = hfusion.my_op(%a) : (tensor<1xf16>) -> tensor<2xf16>
  return %out : tensor<2xf16>
}
```

6. **Always add a round-trip test**: Verify that the textual IR can be printed and re-parsed without changes.

---

## E2E Integration Tests

### Location
```
bishengir/test/Integration/
├── README.md
└── HIVM/
    └── VecAdd/
        ├── README.md
        ├── VecAdd.mlir
        └── run.sh
```

### Structure of an E2E Test
```bash
# run.sh
set -e
# 1. Compile the kernel
bishengir-opt VecAdd.mlir \
  --pass-pipeline="..." \
  -o VecAdd_hivm.mlir

# 2. Run on hardware or simulator
bishengir-runner --kernel=VecAdd_hivm.mlir \
  --input="random:1024xf16" \
  --input="random:1024xf16" \
  --output="output.bin"

# 3. Validate output (compare against reference)
python3 validate.py output.bin expected.bin --rtol=1e-3 --atol=1e-4
```

### Numerical Validation
For floating-point kernels, always use relative + absolute tolerance comparisons. Never use exact equality for floating-point output.

Recommended tolerances:
| Precision | rtol | atol |
|---|---|---|
| fp32 | 1e-5 | 1e-6 |
| fp16 | 1e-3 | 1e-4 |
| bf16 | 1e-2 | 1e-3 |
| int8 | 0 | 0 (exact) |

---

## Test Coverage Requirements

When adding a new feature, the minimum required test coverage is:

| Feature Type | Required Tests |
|---|---|
| New op (TableGen) | Round-trip FileCheck, verifier positive + negative |
| New pass | Nominal case, no-op case (no applicable ops), composability with other passes |
| New lowering pattern | Every type variant, edge-case tensor shapes |
| New E2E kernel | Correctness validation against CPU reference, multiple input sizes |
| Bug fix | Regression test that reproduces the bug and confirms the fix |

---

## Debugging Failing Tests

```bash
# Re-run a single failing lit test with verbose output
llvm-lit bishengir/test/path/to/test.mlir -v --show-all

# Check what command lit is running
llvm-lit bishengir/test/path/to/test.mlir -v --show-all 2>&1 | head -30

# Run the failing command manually (copy from lit output, replace %s with the actual file path)
bishengir-opt bishengir/test/path/to/test.mlir --some-pass | FileCheck bishengir/test/path/to/test.mlir
```
