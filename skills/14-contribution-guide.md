# 14 — Contribution Guide

## Overview

This guide covers the end-to-end process for contributing to AscendNPU-IR: from picking up an issue to getting code merged. Following this process ensures high-quality contributions and a smooth review experience.

---

## Before You Start

1. **Read the existing code**: Before contributing a new feature, read at least three existing similar features end-to-end (op definition, implementation, test, documentation).

2. **Discuss significant changes first**: For features that modify the public API, change a pass pipeline, or introduce a new dialect, open an issue or start an SIG discussion before writing code. This avoids wasted effort from wrong-direction implementations.

3. **Understand the test requirements**: Every contribution must include tests. Read [08 — Testing & Validation](./08-testing-and-validation.md) before writing any code.

---

## Development Workflow

### 1. Set Up Your Environment
```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/Ascend/AscendNPU-IR.git
cd AscendNPU-IR

# Build the Docker dev environment (recommended)
docker build -t ascendnpu-ir-dev docker/
docker run --rm -it -v $(pwd):/workspace ascendnpu-ir-dev bash

# Build with assertions and debug info
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -B build
cmake --build build -j$(nproc)
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/my-new-op
```

### 3. Make Changes (Incremental Commits)
- Make small, logically coherent commits.
- Each commit should build and pass tests independently.
- Commit message format:
  ```
  [Dialect/Area] Short imperative summary (< 72 chars)

  Optional longer explanation of why this change is needed,
  and what design decisions were made.

  Fixes #<issue-number>
  ```

### 4. Run Quality Checks Locally
```bash
# Format
git diff --name-only main | grep '\.[ch]pp$' | xargs clang-format -i

# Lint
clang-tidy path/to/changed/files.cpp -p build/compile_commands.json

# Build
cmake --build build -j$(nproc)

# Run all tests
cmake --build build --target check-bishengir
cmake --build build --target check-bishengir-unit
```

### 5. Open a Pull Request
- Title format: `[Area] Short description of the change`
- Fill in the PR template:
  - **What**: Describe what the PR does
  - **Why**: Explain the motivation
  - **How**: Key design decisions
  - **Testing**: What tests were added/modified
  - **Documentation**: What docs were updated

---

## Commit Message Reference

| Area Tag | Use for |
|---|---|
| `[HFusion]` | HFusion dialect changes |
| `[HIVM]` | HIVM dialect changes |
| `[Conversion]` | Conversion pass changes |
| `[Transforms]` | Transform pass changes |
| `[Build]` | CMake / build system changes |
| `[Test]` | Test-only changes |
| `[Docs]` | Documentation-only changes |
| `[CI]` | GitHub Actions workflow changes |
| `[Python]` | Python bindings changes |
| `[CAPI]` | C API changes |

---

## Code Review Expectations

### For Authors
- The PR must pass all CI checks before requesting review.
- Address **all** review comments — either fix the code or explain in a comment why you disagree.
- Do not force-push after review starts (use additional commits). Squash at merge time.
- Ping reviewers after addressing feedback to re-request review.

### For Reviewers
- Review within 48 hours of assignment.
- Use the standard comment categories:
  - **Blocker**: Must be fixed before merge (correctness, security, API stability)
  - **Suggestion**: Recommended improvement but not required
  - **Nit**: Minor style issue
- Approve only when you are confident the change is correct and complete.

### Code Ownership (CODEOWNERS)
The `CODEOWNERS` file assigns mandatory reviewers to different directory areas. PRs that touch owned directories require approval from the corresponding owner. Check `CODEOWNERS` before assigning reviewers.

---

## Merge Criteria

A PR is ready to merge when:
- [ ] All CI checks pass (build, format, lint, unit tests, integration tests)
- [ ] All reviewer comments are resolved
- [ ] At least one CODEOWNER approval for each touched area
- [ ] Documentation updated (if user-visible change)
- [ ] CHANGELOG or release notes updated (if applicable)

---

## Common PR Pitfalls

| Pitfall | How to Avoid |
|---|---|
| CI fails on clang-format | Run `clang-format -i` on all changed files before pushing |
| CI fails on clang-tidy | Run `clang-tidy` locally; address all warnings in changed files |
| Missing `DEPENDS` in CMakeLists.txt | After adding a new library, build from scratch (`rm -rf build/`) to catch missing deps |
| Test fails on edge case | Always test with zero-size tensors, scalar inputs, and non-divisible tile sizes |
| TableGen `description` missing | Fill in `let description = [{ ... }]` for every new op |
| Force push after review | Use `git commit --fixup` and `git rebase -i` only before review starts |

---

## Documentation Requirements

Every user-visible change must update the documentation:

| Change Type | Doc Update Required |
|---|---|
| New op | TableGen `summary` + `description` (mandatory); `docs/` page (recommended) |
| New pass | `--help` description string (mandatory); `docs/` usage guide (recommended) |
| New dialect | Full `docs/` section covering ops, types, and usage examples |
| New Python API | Docstring (mandatory); `docs/` Python API reference update |
| Changed CLI flag | `--help` string (mandatory) |
| Bug fix | No doc update unless fix changes user-visible behaviour |

---

## Raising Issues

When filing a bug or feature request:

1. **Bug reports** must include:
   - Minimal reproducing MLIR IR (smallest `.mlir` file that triggers the bug)
   - Expected vs actual pass output
   - `bishengir-opt --version` output
   - CANN / hardware version (if E2E issue)

2. **Feature requests** must include:
   - Use case / motivation
   - Proposed API or IR changes
   - Impact on existing functionality

---

## Community & Resources

- **SIG (Special Interest Group)**: [Etherpad SIG-AscendNPU-IR](https://etherpad.ascend.osinfra.cn/p/sig-AscendNPU-IR)
- **Documentation**: [ascendnpu-ir.readthedocs.io](https://ascendnpu-ir.readthedocs.io)
- **Issue tracker**: [GitHub Issues](https://github.com/Ascend/AscendNPU-IR/issues)
- **MLIR upstream docs**: [mlir.llvm.org](https://mlir.llvm.org)
- **CANN documentation**: [hiascend.com/document](https://www.hiascend.com/document)
