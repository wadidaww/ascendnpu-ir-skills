# ascendnpu-ir-skills

Cursor skills (reusable agent capabilities) and agent rules for working with
remote servers and for developing the
[AscendNPU-IR](https://gitcode.com/Ascend/AscendNPU-IR) MLIR compiler
([GitHub mirror](https://github.com/Ascend/AscendNPU-IR)).

## Layout

```
.cursor/rules/            Cursor agent rules (.mdc) — one per skill + the dev guide
  ssh-remote.mdc
  scp-transfer.mdc
  pytest-runner.mdc
  find-files.mdc
  grep-search.mdc
  build-bishengir.mdc     build AscendNPU-IR → runnable bishengir-compile
  debug-bishengir-opt.mdc      debug type A: bishengir-opt
  debug-bishengir-compile.mdc  debug type B: bishengir-compile
  debug-e2e.mdc                debug type C: end-to-end
  ascendnpu-ir-dev.mdc    always-applied AscendNPU-IR dev conventions/build/test
scripts/                  Portable shell helpers the skills call
  ssh_run.sh
  scp_transfer.sh
  run_pytest.sh
  find_files.sh
  grep_search.sh
  build_bishengir.sh
  debug_opt.sh
  debug_compile.sh
  debug_e2e.sh
  split_ir_dump.py        splits a pass IR dump into one file per pass
docs/
  e2e.env.example         config template for debug_e2e.sh
AGENTS.md                 Portable short-form agent guide for AscendNPU-IR
```

## How it works

- **Cursor rules** (`.cursor/rules/*.mdc`) are what the Cursor agent reads. Each
  skill rule has a `description` so Cursor can auto-attach it when the task
  matches (e.g. "ssh into the box", "run pytest", "grep for…"). The AscendNPU-IR
  rule is `alwaysApply: true`.
- **Scripts** (`scripts/*.sh`) do the actual work and are safe to run by hand
  too. Every script supports `--dry-run` and `-h/--help`.

## Skills

### Build AscendNPU-IR → runnable `bishengir-compile` — `scripts/build_bishengir.sh`
```bash
scripts/build_bishengir.sh --source . -j 64 --enable-assertion
scripts/build_bishengir.sh --clone --mirror -o ./build -j 64 --cann /usr/local/Ascend
```
Drives the repo's `build-tools/build.sh` with the flags that actually install and
collect the binary (omits `--build-test`/`--fast-build` so install runs; adds
`--collect-binary`), then locates and smoke-tests `bishengir-compile`. Supports
`--dry-run` to preview the exact build command. Output:
`<collect-dir>/bin/bishengir-compile` (default `<source>/bishengir-output/bin`).

### SSH to a server — `scripts/ssh_run.sh`
```bash
scripts/ssh_run.sh -H user@host                       # interactive
scripts/ssh_run.sh -H host -u dev -i ~/.ssh/k -- 'uname -a && npu-smi info'
```

### SCP a source path to a destination path — `scripts/scp_transfer.sh`
```bash
scripts/scp_transfer.sh -H dev@host --to-remote   -s ./model.mlir -d /work/in/model.mlir
scripts/scp_transfer.sh -H dev@host --from-remote -r -s /work/out  -d ./out
```

### Run pytest on a file/dir and log output+errors — `scripts/run_pytest.sh`
```bash
scripts/run_pytest.sh tests/test_lowering.py -x -v
scripts/run_pytest.sh tests/ -k hivm -l logs/hivm.log
```
Captures combined stdout+stderr to the log, appends `EXIT CODE: N`, and exits
with pytest's own code. Default log: `logs/pytest_<target>_<timestamp>.log`.

### Find files in a directory — `scripts/find_files.sh`
```bash
scripts/find_files.sh -e mlir bishengir/test
scripts/find_files.sh -n 'CMakeLists.txt' -d 3 .
```
Prunes `.git/`, `build/`, `third-party/` by default (`--exclude ''` to disable).

### Grep file contents — `scripts/grep_search.sh`
```bash
scripts/grep_search.sh -i 'HIVM' bishengir/lib
scripts/grep_search.sh -F 'createLowerToHACCPass' -g '*.cpp' -g '*.h'
```
Uses ripgrep when present, else `grep -r`; same default prunes.

## Debugging skills

Three debugging flows for the AscendNPU-IR compiler:

### A — `bishengir-opt` — `scripts/debug_opt.sh`
```bash
scripts/debug_opt.sh in.mlir -p "--your-pass" --around YourPass
scripts/debug_opt.sh in.mlir --print-after-all --split-dumps ir_dumps/
```
Runs `bishengir-opt` (standard MLIR opt driver) with `--debug`/`--mlir-print-ir-*`
flags, logs everything, and can split per-pass IR into one file each.

### B — `bishengir-compile` — `scripts/debug_compile.sh`
```bash
scripts/debug_compile.sh kernel.mlir --cmd "--enable-hivm-compile --target=Ascend910B" \
    --split-dumps ir_dumps/
```
Runs `bishengir-compile` with `--mlir-print-ir-before-all --mlir-print-ir-after-all`
(default on), so you reproduce a failing compile and get the IR before/after every
pass. Feed a wrong pass's `*_Before_*.mlir` into flow A to isolate it.

### C — end-to-end — `scripts/debug_e2e.sh`
```bash
cp docs/e2e.env.example my-e2e.env && $EDITOR my-e2e.env
scripts/debug_e2e.sh --config my-e2e.env --all --dry-run   # preview
scripts/debug_e2e.sh --config my-e2e.env --all             # run
```
Orchestrates the whole loop across a build host and a remote E2E server:
**push** built artifacts → **run** the remote python test (pytest or `python file.py`)
→ **extract** the `kernel.mlir` + `bishengir-compile` command from the log →
**pull** the kernel back → **compile** locally with full IR trace. Phases can run
individually (`run`, `extract pull compile`, …). Always `--dry-run` first.

## AscendNPU-IR development

See [`AGENTS.md`](AGENTS.md) and
[`.cursor/rules/ascendnpu-ir-dev.mdc`](.cursor/rules/ascendnpu-ir-dev.mdc) for
the dialect map (HFusion/HIVM/HACC/Annotation/Scope), build commands
(`build-tools/build.sh`), and the lit/`check-bishengir` test workflow.

## Env var defaults

`ssh_run.sh` / `scp_transfer.sh` read `SSH_HOST`, `SSH_USER`, `SSH_PORT`,
`SSH_IDENTITY` as defaults, so you can set them once per session.
