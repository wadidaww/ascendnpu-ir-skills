# AscendNPU-IR Cursor skills

This repository is a focused knowledge base for working on the `Ascend/AscendNPU-IR`
master branch (the GitHub mirror of
[gitcode.com/Ascend/AscendNPU-IR](https://gitcode.com/Ascend/AscendNPU-IR)).
It is intended to be loaded by Cursor as project context, not as a replacement
for the upstream source or its documentation.

## Contents

- `.cursor/rules/ascendnpu-ir.mdc` — always-on operating rules for an AI agent.
- `skills/architecture.md` — repository map, dependency boundaries, and data flow.
- `skills/code-navigation.md` — how to locate definitions, generated code, and
  owning CMake targets.
- `skills/dialects-and-passes.md` — dialect/pass implementation and registration
  playbooks.
- `skills/reference-catalog.md` — upstream submodules, tools, conversion passes,
  pipelines, and test feature gates.
- `skills/build-test-debug.md` — build configuration, lit/unit/integration tests,
  diagnostics, and debugging workflows.
- `skills/llvm-mlir-practices.md` — LLVM/MLIR conventions and review checklist.

## How to use

Open this repository together with an AscendNPU-IR checkout, or copy the
`.cursor/rules` file and `skills/` directory into the checkout. Always verify
paths and options against the checked-out revision: upstream is actively
developed and generated TableGen files are not authoritative source files.

The upstream repository is large and changes frequently. The documents
deliberately describe stable ownership patterns and discovery commands rather
than pretending to enumerate every generated symbol.