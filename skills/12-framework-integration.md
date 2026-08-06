# 12 — Framework Integration

## Overview

AscendNPU-IR is designed to be the compilation backend for multiple AI frameworks. This document explains how frontend frameworks connect to the AscendNPU-IR compilation pipeline and the patterns used for each integration.

---

## Integration Architecture

```
PyTorch (eager/FX)         Triton kernels         TensorFlow / JAX
       │                        │                        │
  torch-mlir                bishengir/triton/      (future/custom)
  (Torch dialect)           (Triton dialect)
       │                        │                        │
       └────────────────────────┴────────────────────────┘
                                │
                      Frontend Conversion Pass
                  (convert-torch-to-hfusion, etc.)
                                │
                          HFusion IR
                                │
                    (rest of the pipeline)
```

---

## PyTorch Integration (via torch-mlir)

### Overview
PyTorch models reach AscendNPU-IR through [torch-mlir](https://github.com/llvm/torch-mlir), which converts PyTorch FX graphs or `torch.export` output into the `torch` dialect (ATen ops).

AscendNPU-IR then provides a `convert-torch-to-hfusion` pass that lowers the `torch` dialect to HFusion.

### Key Files
```
bishengir/lib/Conversion/TorchToHFusion/
bishengir/include/bishengir/Conversion/TorchToHFusion/
```

### Adding a New Torch Op Lowering
1. Identify the `torch` dialect op (e.g., `torch.aten.relu`).
2. Find the mathematical semantics in PyTorch documentation.
3. Write a `ConversionPattern` that maps `torch.aten.relu` to `hfusion.elemwise {op_kind = "relu"}`.
4. Register the pattern in `TorchToHFusionPass.cpp`.
5. Add a FileCheck test in `bishengir/test/Conversion/TorchToHFusion/`.

### Type Mapping: Torch → HFusion
| Torch Type | HFusion Type |
|---|---|
| `!torch.vtensor<[N,M], f32>` | `tensor<NxMxf32>` |
| `!torch.vtensor<[?,?], f16>` | `tensor<?x?xf16>` |
| `!torch.int` | `i64` |
| `!torch.float` | `f64` |
| `!torch.bool` | `i1` |

---

## Triton Integration

### Overview
[Triton](https://triton-lang.org) provides a Python DSL for writing GPU/NPU kernels. AscendNPU-IR includes Triton frontend support in `bishengir/triton/`, which converts Triton's IR into HFusion.

### Key Directories
```
bishengir/triton/
├── include/    ← Triton-specific HFusion extensions
├── lib/        ← Triton → HFusion conversion
└── test/       ← Triton integration tests
```

### Triton Workflow
```
Python Triton kernel
  → Triton IR (TTIR)
  → Triton GPU IR (TTGIR)
  → bishengir triton lowering pass
  → HFusion IR
  → (standard AscendNPU-IR pipeline)
  → Ascend NPU binary
```

### Key Differences from PyTorch
- Triton kernels are explicit about tiling and shared memory. The conversion must honour the explicit tile structure.
- Triton's `tl.load` / `tl.store` map to HIVM DMA ops, not to HFusion tensor ops.
- `tl.dot` maps to `hfusion.matmul`.

---

## Python Bindings (CAPI-Based)

AscendNPU-IR exposes a Python API via pybind11 bindings that wrap the stable C API (CAPI). This allows Python tools and frameworks to:
- Construct and manipulate MLIR IR programmatically
- Invoke the compilation pipeline
- Register custom dialects

### Key Files
```
bishengir/include/bishengir-c/     ← Stable C API headers
bishengir/lib/CAPI/                ← C API implementation
bishengir/lib/Bindings/            ← Python bindings (pybind11)
bishengir/python/                  ← Python package init + helpers
```

### C API Stability Contract
The C API (`bishengir-c/`) is the **stability boundary**. Changes to C++ internals are allowed freely, but C API changes require:
1. A deprecation period (old symbol kept working for one major release).
2. Documentation of the migration path.
3. CI tests that exercise the C API.

### Building Python Bindings
```bash
cmake -DBISHENGIR_ENABLE_PYTHON_BINDINGS=ON ...
cmake --build build --target BishengirPythonModules

# Install the Python package
pip install -e build/tools/bishengir/python_packages/bishengir_core/
```

### Python API Example
```python
import bishengir
from bishengir.dialects import hfusion
from mlir.ir import Context, Module

with Context() as ctx:
    bishengir.register_dialects(ctx)
    module = Module.parse("""
        func.func @my_op(%a: tensor<1024xf16>) -> tensor<1024xf16> {
          %out = hfusion.elemwise(%a) {op_kind = "relu"} : ... 
          return %out : tensor<1024xf16>
        }
    """)
    # Apply passes via Python
    pm = PassManager.parse("hfusion-fusion,convert-hfusion-to-hivm")
    pm.run(module.operation)
```

---

## Adding a New Frontend Integration

To integrate a new AI framework (e.g., JAX, ONNX):

1. **Define a conversion entry point**: A new pass or pass pipeline that converts the framework's IR into HFusion.

2. **Implement type conversion**: Define how the framework's types map to HFusion tensor types. Use `TypeConverter` in the dialect conversion framework.

3. **Cover op by op**: Each framework op needs a `ConversionPattern`. Start with the most common ops (element-wise, matmul, softmax, convolution) and add more over time.

4. **Handle control flow**: Framework control flow ops (if/for/while) must be converted to `scf.if` / `scf.for` before HFusion conversion, or handled explicitly.

5. **Test coverage**: Every supported op needs a FileCheck test demonstrating the conversion output.

6. **Document coverage**: Maintain a table in the documentation listing which framework ops are supported and which are not.

---

## Framework Integration Checklist

- [ ] Type converter handles all commonly-used framework types
- [ ] Conversion patterns cover the top 20 ops for the target workload class
- [ ] Unknown ops emit `hfusion.op_unsupported` with a helpful error message
- [ ] Control flow is lowered before HFusion conversion
- [ ] FileCheck tests for all implemented op conversions
- [ ] C API or Python API entry point for triggering the conversion pipeline
- [ ] Documentation table listing supported/unsupported ops
- [ ] Integration test with a real framework model (e.g., ResNet-50 forward pass)
