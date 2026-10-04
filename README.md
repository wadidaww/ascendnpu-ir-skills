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
  ascendnpu-ir-dev.mdc    always-applied AscendNPU-IR dev conventions/build/test
scripts/                  Portable shell helpers the skills call
  ssh_run.sh
  scp_transfer.sh
  run_pytest.sh
  find_files.sh
  grep_search.sh
  build_bishengir.sh
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

## AscendNPU-IR development

See [`AGENTS.md`](AGENTS.md) and
[`.cursor/rules/ascendnpu-ir-dev.mdc`](.cursor/rules/ascendnpu-ir-dev.mdc) for
the dialect map (HFusion/HIVM/HACC/Annotation/Scope), build commands
(`build-tools/build.sh`), and the lit/`check-bishengir` test workflow.

## Env var defaults

`ssh_run.sh` / `scp_transfer.sh` read `SSH_HOST`, `SSH_USER`, `SSH_PORT`,
`SSH_IDENTITY` as defaults, so you can set them once per session.
