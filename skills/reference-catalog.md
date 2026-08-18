# Upstream reference catalog

This catalog records stable names discovered in the AscendNPU-IR master branch.
Use `rg` and the checked-out revision to confirm signatures and newly added
entries before editing.

## Submodules and optional features

`.gitmodules` pins the Ascend LLVM fork (LLVM 19.1.7), Torch-MLIR, and `shmem`.
Initialize them recursively before configuring. Torch conversion, Triton,
Python bindings, shared-memory templates, and execution-engine behavior are
feature-gated; a missing feature usually means a configuration issue rather
than a source bug.

## Tools

- `bishengir-opt`: MLIR optimizer/test driver; registers upstream and project
  dialects, passes, and extensions.
- `bishengir-compile`: end-to-end compiler driver and compile-pipeline entry.
- `bishengir-lsp-server`: MLIR language-server integration.
- `bishengir-options-tblgen`: generates compiler option declarations.
- `bishengir-target-spec-tblgen`: generates target specification data.
- `bishengir-hfusion-ods-gen`: generates HFusion named structured operations
  from `HFusionNamedStructuredOps.yaml`.

Start tool registration investigations at:
`bishengir/include/bishengir/InitAllDialects.h`,
`bishengir/include/bishengir/InitAllPasses.h`, and the corresponding tool
`main`/CMake files.

## Conversion pass catalog

The authoritative declarations are in
`bishengir/include/bishengir/Conversion/Passes.td`; implementations are under
`bishengir/lib/Conversion/`.

| Pass | Direction or role |
| --- | --- |
| `convert-arith-to-affine` | arith → affine |
| `convert-arith-to-hfusion` | arith → HFusion |
| `convert-math-to-hfusion` | math → HFusion |
| `convert-linalg-to-hfusion` | linalg → HFusion |
| `convert-gpu-to-hfusion` | gpu → HFusion |
| `convert-hfusion-to-hivm` | HFusion → HIVM |
| `convert-hfusion-to-vector` | HFusion → vector |
| `convert-hivm-to-std` | HIVM → func/memref/scf/LLVM |
| `convert-hivm-to-tritongpu` | HIVM → TritonGPU |
| `convert-vector-to-hivmave` | vector → HIVMAVE |
| `convert-hivmave-to-std` | HIVMAVE → standard/LLVM |
| `convert-hivmave-to-ave-intrin` | HIVMAVE → AVE intrinsics |
| `convert-ascend-dpx-to-hivmregbaseintrins` | AscendDPX → regbase intrinsics |
| `convert-arith-to-hivmave` | arith → HIVMAVE |
| `lower-memref-ext` | MemRefExt → memref |
| `convert-hacc-to-llvm` | HACC → LLVM |
| `convert-torch-to-hfusion` | Torch → linalg/HFusion |
| `convert-torch-to-symbol` | Torch symbolic integers → Symbol |
| `convert-triton-ascend-gpu-to-llvm` | Triton Ascend GPU → LLVM |
| `convert-proton-ascend-gpu-to-llvm` | Proton GPU → LLVM |
| `allocate-proton-ascend-global-scratch-buffer` | Proton scratch-buffer metadata |
| `fix-call-unknown-loc` | call-location normalization |

Related target-specific entries include `convert-arith-to-hivm-llvm` and
`convert-gpu-to-dpx`. Pass options are defined by ODS; inspect `--help` on the
built tool instead of guessing spelling.

## Pipeline registrations

Search these registrations when a pass runs too early, too late, or not at all:

- `registerBiShengIRCompilePass`
- `registerLowerHIVMPipelines`
- `registerConvertToHIVMPipelines`
- `registerLowerHFusionPipelines`
- `registerTorchToHFusionPipelines`
- `registerLowerTritonPipeline`

Dialect-local pass groups are registered by functions such as
`registerHFusionPasses`, `registerHIVMPasses`, `registerAVEPasses`,
`registerHACCPasses`, and `registerBiShengIRTransformPasses`.

## Test feature gates

`bishengir/test/lit.cfg.py` exposes `asserts`/`noasserts`,
`execution-engine`, `bishengir_published`, `enable-lir-compile`, `hivmc`,
`shmem`, and Triton-related features. Use `REQUIRES:`/`UNSUPPORTED:` in tests
when a dependency is genuinely optional; do not hide a regression with an
overly broad skip.
