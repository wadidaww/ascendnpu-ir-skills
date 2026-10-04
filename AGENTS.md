# AGENTS.md — AscendNPU-IR development

Guidance for AI coding agents (Cursor and compatible) working in this repo.
The detailed, always-applied version lives in
[`.cursor/rules/ascendnpu-ir-dev.mdc`](.cursor/rules/ascendnpu-ir-dev.mdc);
this file is the short, portable summary.

## What this project is

**AscendNPU-IR** (aka **BiShengIR**) is an MLIR-based intermediate
representation for compiling operators to Huawei Ascend NPUs.

- Canonical: https://gitcode.com/Ascend/AscendNPU-IR
- Mirror: https://github.com/Ascend/AscendNPU-IR
- License: Apache-2.0

## Layout

- `bishengir/` — source. `include/bishengir/` (headers + TableGen `.td`),
  `lib/` (mirrors include), `test/` (lit/FileCheck tests + `test/Integration/`),
  `tools/` (`bishengir-opt`, `bishengir-compile`).
- `build-tools/` — `build.sh` and patches.
- `third-party/` — `llvm-project`, `torch-mlir` (git submodules).
- In-house dialects: **HFusion, HIVM, HACC, Annotation, Scope** (+ extensions).

## Setup

```bash
git submodule update --init --recursive
source ${PATH_TO_CANN}/cann/set_env.sh    # or ascend-toolkit/set_env.sh (older CANN)
```

## Build

Use the `build-bishengir` skill to get a runnable `bishengir-compile`:

```bash
scripts/build_bishengir.sh --source . -j 64 --enable-assertion   # verifies + logs the binary
scripts/build_bishengir.sh --clone --mirror -o ./build -j 64     # clone first if needed
```

Or call the repo script directly:

```bash
./build-tools/build.sh -o ./build --build-type Debug --build-test --enable-assertion -j 64
./build-tools/build.sh -r -o ./build          # -r reconfigures from scratch
```

`bishengir-compile` is a default target; install (which `--collect-binary` uses)
runs only when NEITHER `--build-test` NOR `--fast-build` is set.

## Test (always run before declaring done)

```bash
cmake --build ./build --target "check-mlir;check-bishengir"   # lit regression
./build/bin/llvm-lit bishengir/test                            # or a single .mlir file
scripts/run_pytest.sh <file-or-dir> -l logs/run.log           # Python tests
```

Pass = exit 0, no failures; PASS/UNSUPPORTED/XFAIL are all fine.

## Debugging

Three flows (see the `debug-*` skills):

- **A — `bishengir-opt`:** `scripts/debug_opt.sh in.mlir -p "--your-pass" --around YourPass`
- **B — `bishengir-compile`:** `scripts/debug_compile.sh kernel.mlir --cmd "<flags>" --split-dumps ir_dumps/`
  (adds `--mlir-print-ir-before-all --mlir-print-ir-after-all`)
- **C — end-to-end:** `scripts/debug_e2e.sh --config my-e2e.env --all`
  (push built binaries → run remote test → extract kernel.mlir + compile cmd →
  pull → re-compile locally with IR trace). Copy `docs/e2e.env.example` first.

## Conventions

- LLVM/MLIR style; `clang-format` with the repo config.
- Ops live in ODS/TableGen `.td`; never hand-edit generated `*.inc`.
- Keep `include/` and `lib/` trees in lockstep and update `CMakeLists.txt`.
- Don't modify `third-party/` unless the task is a submodule bump/patch.
- Report real build/test results; never skip or weaken tests to go green.
- Don't open a PR unless asked.

## Helper skills (in `.cursor/rules/` + `scripts/`)

| Task | Skill rule | Script |
|------|-----------|--------|
| Build AscendNPU-IR → `bishengir-compile` | `build-bishengir` | `scripts/build_bishengir.sh` |
| Debug `bishengir-opt` (type A) | `debug-bishengir-opt` | `scripts/debug_opt.sh` |
| Debug `bishengir-compile` (type B) | `debug-bishengir-compile` | `scripts/debug_compile.sh` |
| End-to-end debugging (type C) | `debug-e2e` | `scripts/debug_e2e.sh` |
| SSH to a server | `ssh-remote` | `scripts/ssh_run.sh` |
| SCP a src→dst path | `scp-transfer` | `scripts/scp_transfer.sh` |
| Run pytest + log | `pytest-runner` | `scripts/run_pytest.sh` |
| Find files | `find-files` | `scripts/find_files.sh` |
| Grep contents | `grep-search` | `scripts/grep_search.sh` |

Run any script with `-h` for full usage.
