# AscendNPU-IR Comprehensive Skillbook for Cursor AI

This skillbook is a practical, end-to-end knowledge base for developing on `Ascend/AscendNPU-IR`.
It is optimized for **real task execution**: where to edit, how to validate, and how to avoid common mistakes.

## 1) High-level architecture (mental model)

AscendNPU-IR is an MLIR-based compiler stack for Ascend NPU operator compilation.

Core abstraction layers:

1. **Framework/DSL entry**: Torch-MLIR, Triton, TileLang, and framework-origin IR.
2. **General tensor layer**: standard MLIR tensor/linalg/math-style representations.
3. **HFusion layer**: fusion + scheduling + hardware-aware optimization.
4. **HIVM layer**: low-level instruction/memory/pipeline/sync abstraction for Ascend.
5. **Backend handoff**: lower-level representation for downstream codegen/binary stages.

Supporting dialects and metadata:

- **HACC**: host/device role and execution metadata.
- **Annotation / Scope / Symbol**: hints, scoping, symbol-related metadata utilities.
- **MathExt / MemRefExt and others**: extension capabilities for optimization/lowering.

## 2) Repository ownership map

## Root-level ownership

- `CMakeLists.txt`: top-level build graph and project options.
- `build-tools/`: scripted build flow (`build.sh`, `apply_patches.sh`, `build_wheel.sh`).
- `docs/`: Sphinx documentation project (English + Chinese).
- `third-party/`: dependency source trees (llvm-project, torch-mlir).

## `bishengir/` ownership

- `bishengir/include/bishengir/**`
  - Public API declarations.
  - `.td` (TableGen) definitions.
  - Dialect/conversion/pass interfaces.
- `bishengir/lib/**`
  - C++ implementations for dialects, conversions, passes, transforms, and support logic.
- `bishengir/tools/**`
  - CLI tools:
    - `bishengir-compile`
    - `bishengir-opt`
    - tablegen utilities and support generators.
- `bishengir/test/**`
  - lit test suites by domain:
    - `Dialect`, `Conversion`, `Pass`, `Transforms`, tool-specific tests, integration tests.
- `bishengir/python/**`
  - Python bindings and wheel packaging support.
- `bishengir/unittests/**`
  - C++ unit test targets.

## 3) Active domain inventory (important for task routing)

## Dialect implementation domains (`bishengir/lib/Dialect`)

Major dialect/extension domains include:

- `Analysis`
- `Annotation`
- `Arith`
- `AscendDPX`
- `Bufferization`
- `HACC`
- `HFusion`
- `HIVM`
- `HIVMAVE`
- `HIVMRegbaseIntrins`
- `LLVMIR`
- `Linalg`
- `Math`
- `MemRef`
- `MemRefExt`
- `SCF`
- `Scope`
- `Symbol`
- `Tensor`
- `Torch`
- `Triton`
- `TritonExt`
- `Utils`
- `Vector`

## Conversion domains (`bishengir/lib/Conversion`)

Major conversion families include:

- `ArithToAffine`
- `ArithToHFusion`
- `ArithToHIVMAVE`
- `ArithToHIVMLLVM`
- `AscendDPXToHIVMRegbaseIntrins`
- `FixCallUnknownLoc`
- `GPUToDPX`
- `GPUToHFusion`
- `HACCToLLVM`
- `HFusionToHIVM`
- `HFusionToVector`
- `HIVMAVEToAVEIntrin`
- `HIVMAVEToStandard`
- `HIVMToStandard`
- `HIVMToTritonGPU`
- `LinalgToHFusion`
- `LowerMemRefExt`
- `MathToHFusion`
- `ProtonAscendGPUToLLVM`
- `TensorToHFusion`
- `TensorToHIVM`
- `TorchToHFusion`
- `TorchToSymbol`
- `TritonAscendGPUToLLVM`
- `VectorToHIVMAVE`

This inventory helps Cursor quickly classify and route implementation work.

## 4) Task-to-file matrix (what to edit for each request type)

## A) New or modified dialect op semantics

Edit sequence:

1. Definition/API layer:
   - `bishengir/include/bishengir/Dialect/<Dialect>/**`
2. Implementation layer:
   - `bishengir/lib/Dialect/<Dialect>/**`
3. Registration/build hooks:
   - relevant CMake/registration files in the same domain
4. Tests:
   - `bishengir/test/Dialect/**` and affected pass/tool tests
5. Docs:
   - `docs/source/en/developer_guide/dialects/**`

## B) New lowering/conversion behavior

Edit sequence:

1. Declare interfaces in `include/bishengir/Conversion/<Flow>/**`
2. Implement patterns/passes in `lib/Conversion/<Flow>/**`
3. Wire pipeline behavior where needed (often `tools/bishengir-compile/**`)
4. Add tests in `bishengir/test/Conversion/**` and tool tests if option-driven
5. Update docs:
   - `docs/source/en/developer_guide/conversion/**`

## C) New or changed optimization pass

Edit sequence:

1. Pass declarations/registration in include-side pass/transform headers
2. Implementation in:
   - `bishengir/lib/Pass/**`, or
   - `bishengir/lib/Dialect/<Dialect>/Transforms/**`
3. Pass tests:
   - `bishengir/test/Pass/**` and/or domain-specific test folders
4. Docs:
   - `docs/source/en/developer_guide/passes/**`

## D) Command-line option or compile pipeline behavior

Edit sequence:

1. `bishengir/tools/bishengir-compile/**` (and/or `bishengir-opt` if relevant)
2. Option parsing + pipeline gate wiring + defaults
3. Tool tests:
   - `bishengir/test/bishengir-compile/**`
   - `bishengir/test/bishengir-opt/**`
4. User docs:
   - `docs/source/en/user_guide/compile_option.md`

## E) Custom operator feature work

Core location: HIVM custom op path.

Key responsibilities:

- validate op attributes and metadata
- ensure lowering path resolves builtin vs user-provided implementations
- validate interactions with:
  - flatten/layout transforms
  - memory planning
  - synchronization-related passes

Documentation reference path:

- `docs/source/en/developer_guide/features/CustomOp/CustomOp.md`

## 5) Build and validation playbook

## Requirements

- CMake >= 3.28
- Ninja >= 1.12.0
- Clang recommended
- CANN environment required for device/runtime scenarios

## Build workflow

1. Initialize dependencies:
   - `git submodule update --init --recursive`
2. First build:
   - `./build-tools/build.sh -o ./build --build-type Release --apply-patches`
3. Incremental build:
   - `./build-tools/build.sh -o ./build --build-type Release`
4. Rebuild:
   - `./build-tools/build.sh -o ./build --build-type Release -r`

## Test workflow

- Main:
  - `ninja check-bishengir`
  - or `cmake --build . --target "check-mlir;check-bishengir"`
- Focused:
  - `./bin/llvm-lit ../bishengir/test/<subpath>`

Recommended execution order:

1. run focused tests for touched areas
2. run broader checks for confidence before finalizing

## 6) Debugging and diagnostics playbook

## Pass-level debugging

Use `bishengir-opt` for isolated pass reasoning:

- `bishengir-opt input.mlir --<pass-name>`

## Pipeline IR boundary inspection

Use `bishengir-compile` print options:

- `--bishengir-print-ir-before=<pass>`
- `--bishengir-print-ir-after=<pass>`

## Runtime value inspection

- HFusion-level debug prints
- HIVM-level debug operations

## Runtime and performance tools

- runtime diagnostics and checks via environment-based debug controls where applicable
- performance path via `msprof` and MindStudio profile analysis flow

## 7) Feature-focused implementation playbooks

## A) HFusion AutoSchedule

Primary code areas:

- `bishengir/include/bishengir/Dialect/HFusion/Transforms/AutoSchedule/**`
- `bishengir/lib/Dialect/HFusion/Transforms/AutoSchedule/**`

Checklist:

1. identify fusion kind and selected strategy path
2. verify tiling legality/alignment constraints
3. verify transform-ops realization into intended loop/cache/tile changes
4. add representative schedule tests

## B) CV optimization / CVPipeline

Checklist:

1. verify cube/vector dependency graph legality
2. verify synchronization semantics
3. evaluate buffering overhead from pipelining
4. test with representative mixed-kernel patterns

## C) CustomOp

Checklist:

1. ensure required attrs and metadata are validated
2. ensure symbol resolution behavior is deterministic and explicit
3. ensure pass interaction safety (layout/memory/sync)
4. add both positive and negative tests

## D) Option-driven pipeline extension

Checklist:

1. add option with clear default semantics
2. bind option to exactly intended pass gates
3. add command-line behavior tests
4. update compile options documentation

## 8) Documentation update matrix

When behavior changes, update the right docs:

- architecture/mental model:
  - `docs/source/en/introduction/architecture.md`
- compile options:
  - `docs/source/en/user_guide/compile_option.md`
- debug guidance:
  - `docs/source/en/user_guide/debug_option.md`
- developer internals:
  - `docs/source/en/developer_guide/**`
- contribution/testing expectations:
  - `docs/source/en/contributing_guide/contribute.md`

If required by project convention, mirror in `docs/source/zh_cn/**`.

## 9) Cursor execution protocol (for autonomous coding sessions)

For each incoming task:

1. classify task type (op/conversion/pass/tool/doc/perf/debug)
2. map to owning files using this skillbook
3. implement minimal coherent changes across declaration + implementation + tests
4. run focused validation first
5. update user/developer docs for user-visible behavior changes
6. avoid unrelated cleanup/refactor in the same change

## 10) Safety and quality constraints

- preserve behavior outside requested scope
- avoid invasive unrelated refactoring
- keep test coverage close to changed behavior
- keep compatibility constraints explicit in code and docs
- follow LLVM style and existing repository conventions

## 11) Companion Cursor rules in this repository

- `.cursor/rules/ascendnpu-ir-developer.mdc`
- `.cursor/rules/ascendnpu-ir-dialects-conversions.mdc`
- `.cursor/rules/ascendnpu-ir-testing-debug.mdc`
- `.cursor/rules/ascendnpu-ir-feature-playbooks.mdc`
