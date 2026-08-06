# 01 — Repository Overview

## Purpose

AscendNPU-IR (internally called **BiShengIR**) is an MLIR-based compiler framework that targets Huawei Ascend NPU hardware. It sits inside the CANN (Compute Architecture for Neural Networks) software stack and bridges high-level AI frameworks (PyTorch, Triton, TensorFlow) to the low-level Ascend AI processor instruction set.

Understanding the repository layout is the first prerequisite for effective contribution.

---

## Top-Level Directory Structure

```
AscendNPU-IR/
├── bishengir/           ← ALL source code lives here
│   ├── cmake/           ← CMake helper modules
│   ├── include/         ← Public C++ and C headers
│   │   ├── bishengir/   ← C++ dialect/pass/analysis headers
│   │   └── bishengir-c/ ← Stable C API headers (CAPI)
│   ├── lib/             ← Implementation (.cpp files)
│   │   ├── Analysis/    ← Analysis passes (liveness, alias, etc.)
│   │   ├── Bindings/    ← Python bindings (pybind11)
│   │   ├── CAPI/        ← C API implementation
│   │   ├── Conversion/  ← Dialect-to-dialect conversion passes
│   │   ├── Dialect/     ← Dialect definitions (HFusion, HIVM, …)
│   │   ├── ExecutionEngine/ ← JIT execution engine
│   │   ├── Pass/        ← Pass pipeline infrastructure
│   │   ├── Template/    ← Operator template library
│   │   ├── Tools/       ← Support utilities for binary tools
│   │   └── Transforms/  ← Rewrite/optimization transforms
│   ├── python/          ← Python package and bindings glue
│   ├── test/            ← FileCheck/lit integration tests
│   │   └── Integration/ ← End-to-end (E2E) kernel tests
│   ├── tools/           ← Standalone binary tool sources
│   ├── triton/          ← Triton frontend integration
│   └── unittests/       ← Google Test unit tests
├── build-tools/         ← Shell scripts for build automation
├── cmake/               ← Top-level CMake module overrides
├── docker/              ← Dockerfile for reproducible build env
├── docs/                ← Sphinx documentation (EN + ZH)
├── CMakeLists.txt       ← Root build file
├── .clang-format        ← Code-style config (BasedOnStyle: LLVM)
├── .clang-tidy          ← Static analysis config
└── .gitmodules          ← MLIR/LLVM as git submodule
```

---

## Critical Files to Read First

| File | Why it matters |
|---|---|
| `CMakeLists.txt` | Understand build targets, MLIR integration, compile flags |
| `.clang-format` | Coding style baseline (LLVM style) |
| `.clang-tidy` | Enabled checkers — read before writing any C++ |
| `bishengir/include/bishengir/` | Canonical API surface — dialects, passes, interfaces |
| `bishengir/lib/Dialect/` | Dialect implementation patterns to follow |
| `bishengir/test/` | Every new feature **must** have a corresponding FileCheck test |
| `docs/source/en/` | Authoritative technical documentation |

---

## Key Concepts at a Glance

| Concept | Location | Summary |
|---|---|---|
| HFusion dialect | `lib/Dialect/HFusion/` | High-level, hardware-agnostic fusion IR |
| HIVM dialect | `lib/Dialect/HIVM/` | Hardware-specific memory, DMA, vector ops |
| Conversion passes | `lib/Conversion/` | HFusion → HIVM and framework → HFusion |
| Analysis | `lib/Analysis/` | Liveness, alias, and dominator analyses |
| Transforms | `lib/Transforms/` | Canonicalization, tiling, loop transforms |
| Templates | `lib/Template/` | Prebuilt operator patterns for common kernels |
| Python bindings | `lib/Bindings/`, `python/` | pybind11-based Python API |
| C API | `lib/CAPI/`, `include/bishengir-c/` | Stable C interface for external integrators |
| E2E tests | `test/Integration/` | Real hardware or simulated kernel validation |

---

## Navigation Tips

1. **Start with the headers** (`include/bishengir/`) to understand what abstractions exist before reading implementation files.
2. **Follow `CMakeLists.txt` files** at each directory level — they document which libraries and targets exist.
3. **Read the tests** (`bishengir/test/`) to understand the expected IR shape at each pipeline stage.
4. **Run `mlir-opt --help`** (after building) to enumerate all registered passes and options.
5. **Grep for `TableGen` `.td` files** in `include/bishengir/` — they are the authoritative op/type/interface definitions.

---

## Submodule Awareness

AscendNPU-IR uses MLIR/LLVM as a git submodule. When checking out:

```bash
git clone --recurse-submodules <repo-url>
# or after cloning:
git submodule update --init --recursive
```

The submodule SHA is intentionally pinned. **Never update the LLVM submodule SHA without coordinating with the maintainers**, as it affects the entire toolchain ABI.
