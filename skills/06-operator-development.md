# 06 — Operator Development

## Overview

This guide covers the complete workflow for developing a new operator in AscendNPU-IR, from initial TableGen definition through C++ implementation, lowering, and testing. Following this workflow ensures correctness, hardware efficiency, and zero regressions.

---

## Development Workflow

```
1. Understand the operator semantics
2. Choose the right abstraction level (HFusion vs HIVM)
3. Define the op in TableGen (.td)
4. Implement C++ boilerplate (verify, fold, print/parse)
5. Implement the lowering pattern (ConversionPattern)
6. Write FileCheck tests
7. Write unit tests (if complex logic)
8. Profile and optimise (if performance-critical)
```

---

## Step 1 — Understand Operator Semantics

Before writing any code, document:
- **Mathematical definition**: What computation does the op perform?
- **Type constraints**: What input/output tensor types are valid?
- **Shape semantics**: How does the output shape relate to input shapes?
- **Edge cases**: What happens with zero-sized dimensions, scalar inputs, overflow?
- **Fusion compatibility**: Can this op fuse with elementwise, reduction, or matmul ops?

**Never implement an op whose semantics are ambiguous.** Ambiguous semantics lead to subtle correctness bugs that are very hard to find later.

---

## Step 2 — Choose the Abstraction Level

| Criteria | HFusion | HIVM |
|---|---|---|
| Hardware-agnostic semantics | ✅ | ❌ |
| Explicit on-chip memory management | ❌ | ✅ |
| Fusible with other ops | ✅ | ❌ |
| Models DMA movement | ❌ | ✅ |
| Tileble via TilingInterface | ✅ | — |

**Rule of thumb**: New compute ops go into HFusion. Only ops that model hardware resources (memory spaces, DMA engines, synchronisation) belong in HIVM.

---

## Step 3 — TableGen Definition

All ops are defined in `.td` files. The TableGen compiler generates C++ declarations automatically.

### File location
```
bishengir/include/bishengir/Dialect/HFusion/IR/HFusionOps.td  (for HFusion ops)
bishengir/include/bishengir/Dialect/HIVM/IR/HIVMOps.td        (for HIVM ops)
```

### Op Template
```tablegen
def HFusion_MyNewOp : HFusion_Op<"my_new_op",
    [Pure,                          // Has no side effects
     DeclareOpInterfaceMethods<TilingInterface>,
     DeclareOpInterfaceMethods<InferTypeOpInterface>]> {
  let summary = "One-line description of what this op does";
  let description = [{
    Detailed description with:
    - semantics
    - type constraints
    - examples of valid MLIR uses
  }];

  let arguments = (ins
    AnyRankedTensor:$input,          // Input tensor
    AnyRankedTensor:$weight,         // Second input
    DefaultValuedAttr<BoolAttr, "false">:$transpose  // Attribute with default
  );

  let results = (outs
    AnyRankedTensor:$output
  );

  let hasVerifier = 1;  // Enables custom verify() C++ method
  let hasFolder = 1;    // Enables fold() for constant folding
  let hasCanonicalizer = 1;  // Enables getCanonicalizationPatterns()
}
```

### Key TableGen Traits to Know

| Trait | Meaning |
|---|---|
| `Pure` | Op has no side effects; safe to CSE and DCE |
| `SameOperandsAndResultType` | All operands and results share the same type |
| `SameOperandsAndResultElementType` | Element types match, shapes may differ |
| `DeclareOpInterfaceMethods<X>` | Generate C++ stubs for interface X |
| `AttrSizedOperandSegments` | Operands have variable-length groups (needs segment sizes attr) |
| `NoMemoryEffect` | Alias for Pure in modern MLIR |

---

## Step 4 — C++ Implementation

### Verifier
```cpp
// bishengir/lib/Dialect/HFusion/IR/HFusionOps.cpp
LogicalResult HFusion::MyNewOp::verify() {
  auto inputType = cast<RankedTensorType>(getInput().getType());
  auto outputType = cast<RankedTensorType>(getOutput().getType());

  if (inputType.getRank() != 2)
    return emitOpError("expected 2D input tensor, got rank ")
           << inputType.getRank();

  if (inputType.getElementType() != outputType.getElementType())
    return emitOpError("input and output element types must match");

  return success();
}
```

### Shape Inference (InferTypeOpInterface)
```cpp
LogicalResult HFusion::MyNewOp::inferReturnTypes(
    MLIRContext *ctx, std::optional<Location> loc,
    ValueRange operands, DictionaryAttr attrs, OpaqueProperties props,
    RegionRange regions, SmallVectorImpl<Type> &inferredReturnTypes) {
  auto inputType = cast<RankedTensorType>(operands[0].getType());
  // Compute output shape from input shape and attributes
  inferredReturnTypes.push_back(
      RankedTensorType::get(computeOutputShape(inputType), inputType.getElementType()));
  return success();
}
```

### Constant Folding
```cpp
OpFoldResult HFusion::MyNewOp::fold(FoldAdaptor adaptor) {
  // If all inputs are constants, compute the result at compile time
  auto inputAttr = dyn_cast_or_null<DenseElementsAttr>(adaptor.getInput());
  if (!inputAttr) return {};
  // ... compute folded result ...
  return foldedResult;
}
```

---

## Step 5 — Lowering Pattern

### Define the Conversion Pattern
```cpp
// bishengir/lib/Conversion/HFusionToHIVM/MyNewOpLowering.cpp
struct MyNewOpLowering : public OpConversionPattern<HFusion::MyNewOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(
      HFusion::MyNewOp op,
      OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {
    auto loc = op.getLoc();

    // 1. Get converted (memref) operands
    Value inputBuf = adaptor.getInput();

    // 2. Allocate on-chip buffer
    auto ubBufType = MemRefType::get(
        cast<MemRefType>(inputBuf.getType()).getShape(),
        rewriter.getF16Type(),
        {}, HIVMMemSpaceAttr::get(rewriter.getContext(), HIVMMemSpace::UB));
    Value ubBuf = rewriter.create<HIVM::AllocBufferOp>(loc, ubBufType);

    // 3. Insert DMA from GM to UB
    rewriter.create<HIVM::DmaGm2UbOp>(loc, inputBuf, ubBuf, /* ... */);
    rewriter.create<HIVM::DmaWaitOp>(loc);

    // 4. Insert vector compute
    Value outBuf = /* allocate output buffer */;
    rewriter.create<HIVM::VMyComputeOp>(loc, ubBuf, outBuf);

    // 5. DMA result back to GM output
    rewriter.create<HIVM::DmaUb2GmOp>(loc, outBuf, adaptor.getOutput());

    // 6. Free on-chip buffers
    rewriter.create<HIVM::FreeBufferOp>(loc, ubBuf);
    rewriter.create<HIVM::FreeBufferOp>(loc, outBuf);

    rewriter.eraseOp(op);
    return success();
  }
};
```

### Register the Pattern
```cpp
void populateHFusionToHIVMConversionPatterns(RewritePatternSet &patterns,
                                              TypeConverter &typeConverter) {
  patterns.add<
    // ... existing patterns ...
    MyNewOpLowering
  >(typeConverter, patterns.getContext());
}
```

---

## Step 6 — FileCheck Tests

Every op must have at minimum two FileCheck test files:

### Op Definition Test (`test/Dialect/HFusion/my_new_op.mlir`)
```mlir
// RUN: bishengir-opt %s | FileCheck %s

// CHECK-LABEL: func.func @test_my_new_op
func.func @test_my_new_op(%input: tensor<32x64xf16>) -> tensor<32x64xf16> {
  // CHECK: hfusion.my_new_op
  %out = hfusion.my_new_op(%input) : (tensor<32x64xf16>) -> tensor<32x64xf16>
  return %out : tensor<32x64xf16>
}
```

### Lowering Test (`test/Conversion/HFusionToHIVM/my_new_op.mlir`)
```mlir
// RUN: bishengir-opt --convert-hfusion-to-hivm %s | FileCheck %s

// CHECK-LABEL: func.func @test_my_new_op_lowered
func.func @test_my_new_op_lowered(%input: memref<?xf16>) -> memref<?xf16> {
  // CHECK: hivm.dma_gm2ub
  // CHECK: hivm.dma_wait
  // CHECK: hivm.v{{.*}}
  // CHECK: hivm.dma_ub2gm
  %out = hfusion.my_new_op(%input) : (tensor<32x64xf16>) -> tensor<32x64xf16>
  return %out : tensor<32x64xf16>
}
```

---

## Step 7 — Operator Development Checklist

- [ ] Semantics fully documented in TableGen `description` field
- [ ] Type and shape constraints implemented in `verify()`
- [ ] Shape inference via `InferTypeOpInterface` (if output shape is derivable)
- [ ] Constant folding via `fold()` (if applicable)
- [ ] Canonicalization patterns (algebraic identities, no-op elimination)
- [ ] `TilingInterface` implemented for HFusion ops
- [ ] Lowering pattern covers all valid type combinations
- [ ] DMA, barrier, and buffer ops inserted correctly in lowering
- [ ] FileCheck test for op round-trip
- [ ] FileCheck test for lowering output
- [ ] Edge case tests (zero-size, scalar, large dimensions)
- [ ] Verifier negative tests (confirm that invalid IR is rejected)
- [ ] Documentation updated in `docs/`
