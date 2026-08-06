# 13 — Developer Roles & Responsibilities

## Overview

The AscendNPU-IR project requires expertise across multiple disciplines. This document defines the key developer roles, their responsibilities, required skills, and the areas of the codebase they primarily own. An excellent developer understands their primary role deeply and has working knowledge of adjacent roles.

---

## Role 1 — Compiler Infrastructure Engineer

### Primary Focus
MLIR pass infrastructure, pass pipelines, build system, and toolchain.

### Responsibilities
- Design and implement reusable pass infrastructure
- Maintain and extend the pass pipeline for new hardware generations
- Own the CMake build system and CI configuration
- Manage the LLVM/MLIR submodule version upgrades
- Maintain backward compatibility of the CAPI

### Required Skills
- Deep MLIR pass framework knowledge (`Pass`, `PassManager`, `AnalysisManager`)
- LLVM/MLIR build system (CMake, TableGen code generation)
- C++17 proficiency
- Understanding of the full compilation pipeline from HFusion to HIVM

### Codebase Ownership
```
bishengir/lib/Pass/
bishengir/cmake/
CMakeLists.txt (root)
.github/workflows/
build-tools/
```

### Excellence Markers
- Pass pipelines are composable, orthogonal, and fast
- CI is green, fast, and provides clear failure messages
- Build system changes are backward-compatible and well-documented

---

## Role 2 — Dialect Designer

### Primary Focus
Designing and implementing new dialects, ops, types, and interfaces.

### Responsibilities
- Define new op semantics with precise mathematical contracts
- Implement `verify()`, `fold()`, `getCanonicalizationPatterns()` for all new ops
- Design and implement `OpInterface`s for shared abstract behaviours
- Keep TableGen definitions clean, consistent, and well-documented
- Ensure new ops integrate with the existing lowering pipeline

### Required Skills
- Deep TableGen knowledge (ops, types, attributes, interfaces, constraints)
- MLIR type system (ranked/unranked tensors, memrefs, custom types)
- IR design principles (immutability, SSA form, use-def chains)
- Familiarity with MLIR's canonicalization and folding infrastructure

### Codebase Ownership
```
bishengir/include/bishengir/Dialect/
bishengir/lib/Dialect/
bishengir/test/Dialect/
```

### Excellence Markers
- Every op has a complete `description` in TableGen
- `verify()` catches all malformed IR at construction time, not silently at compile time
- Op interfaces enable passes to work uniformly across op types
- Zero ambiguous semantics — every edge case is documented or tested

---

## Role 3 — Operator Developer

### Primary Focus
Implementing high-performance compute operators for the Ascend NPU.

### Responsibilities
- Implement new operators from mathematical specification to HIVM IR
- Write HFusion-level operator definitions and their HIVM lowering
- Tune tiling parameters and on-chip buffer layout for performance
- Validate operator correctness against CPU reference implementations
- Write E2E tests that validate operators on hardware or simulator

### Required Skills
- Understanding of Ascend hardware (Vector unit, Cube unit, DMA engine, memory hierarchy)
- HFusion and HIVM dialect op semantics
- Numerical analysis (floating-point precision, quantisation)
- Performance analysis (profiling tools, pipeline utilisation)
- MLIR bufferization and memref layout

### Codebase Ownership
```
bishengir/lib/Dialect/HFusion/        (new op implementations)
bishengir/lib/Conversion/HFusionToHIVM/
bishengir/lib/Template/               (reusable kernel templates)
bishengir/test/Integration/           (E2E kernel tests)
```

### Excellence Markers
- New operators achieve ≥ 80% peak AI Core utilisation on target hardware
- Numerical accuracy is validated against a high-precision reference
- All edge cases (zero-size, non-aligned shapes, mixed precision) are tested
- Operators are correctly fused by the HFusion fusion pass

---

## Role 4 — Framework Integration Engineer

### Primary Focus
Connecting AI frameworks (PyTorch, Triton) to the AscendNPU-IR compilation pipeline.

### Responsibilities
- Implement conversion passes that lower framework IR to HFusion
- Maintain op coverage tables for each supported framework
- Track upstream framework changes and update conversion patterns
- Provide Python API entry points for framework-driven compilation
- Write integration tests with real framework models

### Required Skills
- Deep knowledge of the target framework's IR (Torch dialect, Triton IR)
- MLIR dialect conversion framework
- Python and pybind11 (for Python bindings)
- The AscendNPU-IR type system and how it maps to framework types

### Codebase Ownership
```
bishengir/lib/Conversion/TorchToHFusion/
bishengir/triton/
bishengir/lib/Bindings/
bishengir/python/
bishengir/lib/CAPI/
bishengir/include/bishengir-c/
```

### Excellence Markers
- Conversion is op-complete for the target workload class (no unsupported op fallbacks in normal models)
- Conversion output is idiomatic HFusion (no leftover framework-specific constructs)
- Python API is documented with usage examples
- Framework version changes are tracked and compatibility maintained

---

## Role 5 — Performance Engineer

### Primary Focus
Maximising compute efficiency on Ascend hardware through tiling, scheduling, and pipeline optimisation.

### Responsibilities
- Develop and tune tiling strategies for different op types and hardware generations
- Implement scheduling passes that maximise DMA/compute overlap
- Implement and validate the ping-pong pipeline transformation
- Benchmark kernel performance and track regressions
- Identify and fix performance bottlenecks in the compilation pipeline

### Required Skills
- Ascend hardware microarchitecture (pipeline depth, DRAM latency, on-chip memory bandwidth)
- Polyhedral model and affine loop transformations
- MLIR tiling infrastructure (`TilingInterface`, `scf.forall`)
- Hardware profiling tools (CANN profiling, hardware performance counters)
- Statistical benchmarking methodology

### Codebase Ownership
```
bishengir/lib/Transforms/           (tiling, scheduling transforms)
bishengir/lib/Dialect/HFusion/Transforms/  (HFusion-specific opts)
bishengir/lib/Dialect/HIVM/Transforms/     (HIVM-specific opts)
```

### Excellence Markers
- Kernels achieve theoretical peak performance for memory-bound or compute-bound cases
- DMA and compute are fully overlapped with ping-pong pipeline
- Performance regressions are caught in CI before merge

---

## Role 6 — Test & Quality Engineer

### Primary Focus
Test infrastructure, correctness validation, and quality gates.

### Responsibilities
- Maintain the `lit` test infrastructure and FileCheck test runner
- Design and implement randomised / fuzz testing for passes and dialects
- Maintain numerical validation tooling for E2E tests
- Enforce test coverage requirements in code review
- Track and triage test failures in CI

### Required Skills
- LLVM `lit` test framework and FileCheck patterns
- Google Test (unit test framework)
- Python scripting (for test automation and validators)
- Understanding of all pipeline stages (to write effective integration tests)

### Codebase Ownership
```
bishengir/test/
bishengir/unittests/
build-tools/  (test scripts)
```

### Excellence Markers
- Every new feature has test coverage before merge
- Flaky tests are identified and fixed promptly
- Test suite runs in < 5 minutes on a standard build machine

---

## Role Overlap & Collaboration

Excellence requires awareness beyond your primary role:

| I am a... | I also need to understand... |
|---|---|
| Compiler Infrastructure Engineer | All dialects (to build correct pipelines) |
| Dialect Designer | The compilation pipeline (to know where ops are used) |
| Operator Developer | Performance profiling (to validate efficiency) |
| Framework Integration Engineer | HFusion semantics (to write correct conversion patterns) |
| Performance Engineer | Dialect semantics (to know what transforms are valid) |
| Test Engineer | All roles (to write meaningful tests for each layer) |
