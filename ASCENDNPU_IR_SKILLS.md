# AscendNPU-IR Skillbook for Cursor AI

This file is a complete practical knowledge map for building, modifying, and extending `Ascend/AscendNPU-IR`.

## 1. Project purpose and architecture

- AscendNPU-IR is MLIR-based IR for Ascend NPU operator compilation.
- Main in-house dialect roles:
  - **HFusion**: high-level fusion, schedule, and hardware-aware optimizations.
  - **HIVM**: low-level mapping to NPU compute/memory/sync primitives.
  - **HACC**: heterogeneous hardware abstraction and function role metadata.
  - **Annotation/Scope/Symbol/MathExt/MemRefExt**: hints, scoping, symbol and utility extensions.

Logical flow:

1. Framework/DSL input (Torch-MLIR, Triton, TileLang, etc.)
2. Linalg/Tensor-level representation
3. HFusion optimization and fusion
4. HIVM lowering and hardware-detail optimization
5. downstream lowering/binary generation

## 2. Repository map (what each part owns)

### Root-level

- `CMakeLists.txt`: top-level build graph and options; LLVM/MLIR integration.
- `build-tools/`: scripted build/patch/wheel workflows.
- `docs/`: Sphinx documentation with English/Chinese trees.
- `third-party/`: llvm-project and torch-mlir submodule dependencies.

### `bishengir/`

- `include/bishengir/`
  - Public headers and TableGen definitions.
  - Conversion declarations, dialect interfaces, pass registration declarations.
- `lib/`
  - `Dialect/`: dialect op implementations and transforms.
  - `Conversion/`: dialect-to-dialect lowering pipelines.
  - `Pass/`, `Transforms/`, `ExecutionEngine/`, etc.
- `tools/`
  - `bishengir-compile`: production compile driver.
  - `bishengir-opt`: pass-level IR debug/transform tool.
  - tablegen helpers and other support tools.
- `test/`
  - lit-based tests for dialect/transform/conversion/tool behavior.
  - `Integration/` for E2E scenarios.
- `python/`
  - Python bindings and wheel packaging flow.
- `unittests/`
  - C++ unit test targets.

## 3. Core development entry points

### A) Add/modify a dialect op

Change areas:

1. `include/bishengir/Dialect/<Dialect>/...` (`.td` + API headers)
2. `lib/Dialect/<Dialect>/...` (C++ op implementation, verifier/canonicalization/lowering helpers)
3. Update tests in `bishengir/test/Dialect/...`
4. Register/update docs in `docs/source/en/developer_guide/dialects/*.md`

### B) Add/modify a conversion pipeline

Change areas:

1. `include/bishengir/Conversion/<Flow>/...`
2. `lib/Conversion/<Flow>/...`
3. Tool pipeline wiring if needed (`bishengir-compile`)
4. Tests in `bishengir/test/Conversion/...`
5. Docs in `developer_guide/conversion/*`

### C) Add/modify a pass

Change areas:

1. Pass declaration/registration in `include/bishengir/Pass` or dialect transform headers
2. Implementation in `lib/Pass` or `lib/Dialect/<Dialect>/Transforms`
3. lit tests in `bishengir/test/Pass` (or per-dialect test directories)
4. Docs in `docs/source/en/developer_guide/passes/*.md`

### D) Extend compiler options and pipeline toggles

Change areas:

1. `bishengir/tools/bishengir-compile/**`
2. Pipeline registration/invocation code and option plumbing
3. Tests in `bishengir/test/bishengir-compile/**`
4. Update docs `docs/source/en/user_guide/compile_option.md`

### E) Custom operator workflow

Key knowledge:

- Custom op path is in HIVM (`hivm.hir.custom` / custom macro variants).
- Required metadata can include core type, pipe info, symbol, alignment/iterator/index mapping, extra buffers, and side-effect flags.
- Lowering path eventually links to builtins or user-provided implementation symbols.
- Validate interactions with flatten/layout/memory planning/sync-related passes.

## 4. Build and test playbook

## Requirements

- CMake >= 3.28
- Ninja >= 1.12.0
- Clang recommended
- CANN required for device/runtime and E2E device scenarios

## Build commands

1. Submodules:
   - `git submodule update --init --recursive`
2. First build:
   - `./build-tools/build.sh -o ./build --build-type Release --apply-patches`
3. Incremental build:
   - `./build-tools/build.sh -o ./build --build-type Release`
4. Rebuild:
   - `./build-tools/build.sh -o ./build --build-type Release -r`

## Test commands

- `ninja check-bishengir`
- or `cmake --build . --target "check-mlir;check-bishengir"`
- targeted debug: `./bin/llvm-lit ../bishengir/test/<path>`

## 5. Debug and performance workflow

- Pass-level IR verification:
  - `bishengir-opt input.mlir --<pass>`
- IR dump around pass:
  - `bishengir-compile ... --bishengir-print-ir-before=<pass> --bishengir-print-ir-after=<pass>`
- Debug ops:
  - HFusion `print` op for higher-level tensor checks.
  - HIVM `debug` op for low-level kernel value checks.
- Triton-side runtime debug:
  - `TRITON_DEVICE_PRINT=1`, `TRITON_DEBUG=1` where needed.
- Performance diagnosis:
  - `msprof`, MindStudio profiler flows.

## 6. Feature-area map (where advanced logic lives)

- HFusion AutoSchedule:
  - `include/bishengir/Dialect/HFusion/Transforms/AutoSchedule/`
  - `lib/Dialect/HFusion/Transforms/AutoSchedule/`
  - Focus: fusion-kind strategy selection, tiling legality, align constraints, transform dialect application.
- CV / CVPipeline / subtiling:
  - HIVM feature docs and pass pipeline; verify cube/vector dependency correctness and buffering costs.
- Debug/DFX and memory planning:
  - feature docs under `docs/source/en/developer_guide/features/*`.

## 7. Cursor operating protocol for new tasks

When Cursor gets a new task on AscendNPU-IR, follow this sequence:

1. Classify: dialect op vs conversion vs pass vs tool option vs docs.
2. Locate owning directories from this skillbook.
3. Implement smallest coherent change across include/lib/tool/test.
4. Add or update lit tests nearest to the changed behavior.
5. Run `check-bishengir` (or targeted lit first, then full check as possible).
6. Update user/developer docs when behavior or options change.
7. Keep PR scope narrow and avoid unrelated cleanup.

## 8. Contribution constraints to remember

- Follow LLVM coding style and repository formatting rules.
- For upstream contribution flow:
  - issue first, implementation second, PR after self-test.
  - expected review policy includes multi-review approval.
- Keep commit history focused; avoid unrelated modifications.
