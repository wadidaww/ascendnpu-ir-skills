# 07 — Build System & Toolchain

## Overview

AscendNPU-IR uses CMake as its build system, tightly integrated with LLVM/MLIR's own CMake infrastructure. Understanding the build system is critical for productive development, CI troubleshooting, and adding new library targets.

---

## Prerequisites

| Dependency | Version | Notes |
|---|---|---|
| CMake | ≥ 3.20 | `cmake --version` to check |
| Ninja | ≥ 1.10 | Strongly recommended over `make` |
| Clang / GCC | Clang ≥ 14 preferred | Must support C++17 |
| Python | ≥ 3.8 | Required for Python bindings and lit tests |
| CANN Toolkit | See version compat table | Hardware backend |

---

## Quick Build

```bash
# 1. Clone with submodules (LLVM/MLIR is a submodule)
git clone --recurse-submodules https://github.com/Ascend/AscendNPU-IR.git
cd AscendNPU-IR

# 2. Configure
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DLLVM_ENABLE_PROJECTS="mlir" \
  -DLLVM_TARGETS_TO_BUILD="host" \
  -B build

# 3. Build
cmake --build build --target bishengir-opt -- -j$(nproc)

# 4. Run tests
cmake --build build --target check-bishengir
```

---

## Docker Build (Recommended for CI parity)

```bash
# Build the Docker image (defined in docker/)
docker build -t ascendnpu-ir-dev docker/

# Run an interactive shell inside the container
docker run --rm -it -v $(pwd):/workspace ascendnpu-ir-dev bash

# Inside the container, follow the Quick Build steps above
```

The Dockerfile pins the exact CANN and OS versions used in CI. Always verify your local build against the Docker image before submitting a PR.

---

## Key CMake Variables

| Variable | Default | Description |
|---|---|---|
| `CMAKE_BUILD_TYPE` | `Debug` | Use `RelWithDebInfo` for performance, `Debug` for full debug info |
| `CMAKE_C_COMPILER` | system cc | Set to `clang` for LLVM-compatible builds |
| `CMAKE_CXX_COMPILER` | system c++ | Set to `clang++` |
| `LLVM_ENABLE_ASSERTIONS` | `ON` for Debug | Enable LLVM/MLIR runtime assertions |
| `BISHENGIR_ENABLE_PYTHON_BINDINGS` | `OFF` | Build Python pybind11 bindings |
| `BISHENGIR_ENABLE_TESTS` | `ON` | Build and register test targets |
| `LLVM_EXTERNAL_LIT` | auto-detected | Path to `lit` test runner |
| `BISHENGIR_INCLUDE_TESTS` | `ON` | Include test/ directories in build |

---

## Build Targets

| Target | Description |
|---|---|
| `bishengir-opt` | Main IR transformation tool (like `mlir-opt`) |
| `bishengir-translate` | IR serialization/deserialization tool |
| `bishengir-runner` | E2E kernel execution runner |
| `check-bishengir` | Run all lit integration tests |
| `check-bishengir-unit` | Run Google Test unit tests only |
| `MLIRBiShengIRHFusion` | HFusion dialect library |
| `MLIRBiShengIRHIVM` | HIVM dialect library |
| `MLIRBiShengIRConversion` | All conversion pass libraries |

---

## Adding a New Library Target

1. Create implementation files in the appropriate `lib/` subdirectory.
2. Add a `CMakeLists.txt` in the same directory:

```cmake
add_mlir_library(MLIRBiShengIRMyNewFeature
  MyNewFeature.cpp

  DEPENDS
    MLIRBiShengIRHFusionIncGen  # If depending on TableGen-generated headers

  LINK_LIBS PUBLIC
    MLIRBiShengIRHFusion        # Dialect library dep
    MLIRIR                      # Core MLIR IR library
    MLIRPass                    # Pass infrastructure
)
```

3. Add the new directory to the parent `CMakeLists.txt`:
```cmake
add_subdirectory(MyNewFeature)
```

4. Add the library to the `bishengir-opt` link line if it contains a pass that should be registered in the tool.

---

## TableGen Code Generation

TableGen definitions in `.td` files are processed by the CMake infrastructure automatically:

```cmake
mlir_tablegen(HFusionOps.h.inc -gen-op-decls)
mlir_tablegen(HFusionOps.cpp.inc -gen-op-defs)
mlir_tablegen(HFusionTypes.h.inc -gen-typedef-decls)
mlir_tablegen(HFusionTypes.cpp.inc -gen-typedef-defs)
mlir_tablegen(HFusionPasses.h.inc -gen-pass-decls -name HFusion)
add_public_tablegen_target(MLIRBiShengIRHFusionIncGen)
```

Always add `DEPENDS MLIRBiShengIRHFusionIncGen` (or the appropriate target) to any library that includes generated headers.

---

## Clang-Format & Clang-Tidy

The repository enforces automatic formatting and static analysis:

```bash
# Format a file
clang-format -i bishengir/lib/Dialect/HFusion/IR/HFusionOps.cpp

# Format all changed files (compared to main)
git diff --name-only main | grep '\.[ch]pp$' | xargs clang-format -i

# Run clang-tidy on a file
clang-tidy bishengir/lib/Dialect/HFusion/IR/HFusionOps.cpp \
  -p build/compile_commands.json

# Generate compile_commands.json (needed for clang-tidy)
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ...
```

CI will **fail** if `clang-format` or `clang-tidy` produce errors. Always run both before pushing.

---

## CI Integration

The project uses GitHub Actions. Key workflow files are in `.github/workflows/`. A typical PR must pass:

1. **Build check**: Full CMake build with assertions enabled
2. **Format check**: `clang-format --dry-run --Werror` on changed files
3. **Lint check**: `clang-tidy` on changed files
4. **Unit tests**: `check-bishengir-unit`
5. **Integration tests**: `check-bishengir`

If CI fails, use the GitHub Actions log viewer to identify the failing step. The most common failure categories:
- Incorrect `#include` order (clang-tidy `llvm-include-order`)
- Missing `DEPENDS` in `CMakeLists.txt` causing undefined symbol errors
- Failing FileCheck tests due to pass output format change
