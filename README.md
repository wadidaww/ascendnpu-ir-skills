# AscendNPU-IR Skills Repository

A comprehensive knowledge base for AI developers working with the [AscendNPU-IR](https://github.com/Ascend/AscendNPU-IR) (BiShengIR) project — an MLIR-based compiler framework targeting Huawei Ascend NPUs.

This repository equips developers with the deep understanding, best practices, and role-specific skills required to contribute at an expert level: zero bugs, optimal system design, and production-quality code.

---

## 📖 Table of Contents

| Document | Description |
|---|---|
| [01 — Repository Overview](./skills/01-repository-overview.md) | Codebase structure, key directories, and orientation guide |
| [02 — Architecture & IR Design](./skills/02-architecture-and-ir-design.md) | Three-tier dialect hierarchy, MLIR foundations, and design principles |
| [03 — HIVM Dialect](./skills/03-hivm-dialect.md) | Hardware-level IR: memory, DMA, vector/cube ops, synchronization |
| [04 — HFusion Dialect](./skills/04-hfusion-dialect.md) | High-level fusion dialect: operator fusion, tiling, scheduling |
| [05 — Compilation Pipeline](./skills/05-compilation-pipeline.md) | End-to-end lowering: frontend → HFusion → HIVM → hardware binary |
| [06 — Operator Development](./skills/06-operator-development.md) | Authoring new operators with TableGen, C++ patterns, and best practices |
| [07 — Build System & Toolchain](./skills/07-build-system-and-toolchain.md) | CMake build, Docker setup, CI integration, and build flags |
| [08 — Testing & Validation](./skills/08-testing-and-validation.md) | Unit tests, FileCheck/lit integration tests, E2E validation |
| [09 — Debugging & Profiling](./skills/09-debugging-and-profiling.md) | IR dumps, pass-level debugging, performance analysis techniques |
| [10 — Best Practices & Code Quality](./skills/10-best-practices-and-code-quality.md) | C++ coding standards, MLIR idioms, clang-tidy/format, review checklist |
| [11 — System Design Patterns](./skills/11-system-design-patterns.md) | Extensibility, abstraction layers, dialect interfaces, pass pipelines |
| [12 — Framework Integration](./skills/12-framework-integration.md) | Connecting PyTorch, Triton, and other frontends to AscendNPU-IR |
| [13 — Developer Roles & Responsibilities](./skills/13-developer-roles.md) | Compiler engineer, dialect designer, operator dev, framework integrator |
| [14 — Contribution Guide](./skills/14-contribution-guide.md) | PR workflow, commit conventions, code-review checklist, ownership model |

---

## 🎯 Target Audience

These skills apply to every contributor role:

- **Compiler Infrastructure Engineers** — pass pipeline, lowering, bufferization
- **Dialect Designers** — TableGen, op semantics, interfaces, type systems
- **Operator Developers** — high-level and fine-grained NPU kernel authoring
- **Framework Integration Engineers** — frontend dialect conversion, ecosystem glue
- **Performance Engineers** — tiling, scheduling, memory hierarchy optimisation
- **Test & Quality Engineers** — FileCheck tests, fuzzing, correctness validation

---

## 🔗 Key External References

- **Source repo**: <https://github.com/Ascend/AscendNPU-IR>
- **Documentation**: <https://ascendnpu-ir.readthedocs.io>
- **CANN commercial docs**: <https://www.hiascend.com/document>
- **MLIR upstream**: <https://mlir.llvm.org>
- **EuroLLVM 2026 talk — HIVM dialect**: <https://llvm.swoogo.com/2026eurollvm/session/3943100>
