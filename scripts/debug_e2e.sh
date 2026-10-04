#!/usr/bin/env bash
#
# debug_e2e.sh — Debugging type C: drive the whole end-to-end compilation debug
# loop (Triton-Ascend / BiShengIR → AI compute) across a local build host and a
# remote E2E server.
#
# Phases (run one, several, or --all):
#   push     0. scp locally-built artifacts (bishengir-compile, hivmc, *.bc)
#               to the remote server.
#   run      1-3. ssh to the server, source set_env.sh, run the python test
#               (pytest or `python file.py`), and pull the run log back.
#   extract  4. parse the run log for the kernel.mlir path and the exact
#               bishengir-compile command.
#   pull     5. scp the kernel.mlir (the bishengir-compile input) back here.
#   compile  6. locally re-run bishengir-compile on it with
#               --mlir-print-ir-before-all/-after-all (via debug_compile.sh),
#               splitting per-pass IR so you can (7) debug a pass with debug_opt.sh.
#
# Usage:
#   scripts/debug_e2e.sh [--config FILE] [options] PHASE [PHASE ...]
#   scripts/debug_e2e.sh [--config FILE] [options] --all
#
# Config: all settings can come from a sourced --config FILE (shell vars below),
# from environment, or from CLI flags (CLI wins). Copy docs/e2e.env.example.
#
# Connection:
#   --server USER@HOST     E2E_SERVER       remote E2E server.
#   --port N               E2E_PORT         ssh port (default 22).
#   --identity FILE        E2E_IDENTITY     ssh key.
#   --jump HOST            E2E_JUMP         bastion/ProxyJump.
#   --set-env PATH         E2E_SET_ENV      remote path to set_env.sh (sourced).
#
# Artifacts (push):
#   --bin-dir DIR          E2E_ARTIFACT_BIN_DIR   local dir with bishengir-compile/hivmc
#                                                 (default: auto — bishengir-output/bin,
#                                                  build/install/bin, build/bin).
#   --lib-dir DIR          E2E_ARTIFACT_LIB_DIR   local dir with *.bc (optional).
#   --remote-bin DIR       E2E_REMOTE_BIN_DIR     remote dest for binaries
#                                                 (prepended to PATH when running).
#   --remote-lib DIR       E2E_REMOTE_LIB_DIR     remote dest for *.bc (optional).
#
# Test (run):
#   --test PATH            E2E_TEST         remote path to the python test.
#   --runner MODE          E2E_RUNNER       auto | pytest | python (default auto).
#   --workdir DIR          E2E_TEST_WORKDIR remote cwd for the test (default: test's dir).
#   --pytest-args "ARGS"   E2E_PYTEST_ARGS  extra args when runner=pytest.
#
# Extraction (extract):
#   --kernel-regex RE      E2E_KERNEL_REGEX ERE capturing the kernel .mlir path.
#   --cmd-regex RE         E2E_CMD_REGEX    ERE marking the bishengir-compile line.
#   --kernel PATH          E2E_KERNEL       skip extraction; use this remote .mlir path.
#
# Local output:
#   --local-dir DIR        E2E_LOCAL_DIR    local working dir for logs/kernel/dumps
#                                           (default: ./e2e-debug/<timestamp>).
#
#   --dry-run              print each remote/local command; change nothing.
#   -h, --help             show this help.
#
# Requires the sibling helpers: ssh_run.sh, scp_transfer.sh, debug_compile.sh,
# split_ir_dump.py (same scripts/ dir).
#
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
die() { echo "debug_e2e: $*" >&2; exit 2; }

# ---- defaults (overridable by --config, env, then CLI) --------------------
E2E_SERVER="${E2E_SERVER:-}"
E2E_PORT="${E2E_PORT:-22}"
E2E_IDENTITY="${E2E_IDENTITY:-}"
E2E_JUMP="${E2E_JUMP:-}"
E2E_SET_ENV="${E2E_SET_ENV:-}"
E2E_ARTIFACT_BIN_DIR="${E2E_ARTIFACT_BIN_DIR:-}"
E2E_ARTIFACT_LIB_DIR="${E2E_ARTIFACT_LIB_DIR:-}"
E2E_REMOTE_BIN_DIR="${E2E_REMOTE_BIN_DIR:-}"
E2E_REMOTE_LIB_DIR="${E2E_REMOTE_LIB_DIR:-}"
E2E_TEST="${E2E_TEST:-}"
E2E_RUNNER="${E2E_RUNNER:-auto}"
E2E_TEST_WORKDIR="${E2E_TEST_WORKDIR:-}"
E2E_PYTEST_ARGS="${E2E_PYTEST_ARGS:-}"
E2E_KERNEL_REGEX="${E2E_KERNEL_REGEX:-}"
E2E_CMD_REGEX="${E2E_CMD_REGEX:-bishengir-compile}"
E2E_KERNEL="${E2E_KERNEL:-}"
E2E_LOCAL_DIR="${E2E_LOCAL_DIR:-}"
dry_run=0
config=""
declare -a phases=()

# first pass: pull out --config so it loads before other flags override it
declare -a argv=("$@")
for ((i=0; i<${#argv[@]}; i++)); do
  if [[ "${argv[$i]}" == "--config" ]]; then config="${argv[$((i+1))]:-}"; fi
done
if [[ -n "$config" ]]; then
  [[ -f "$config" ]] || die "config not found: $config"
  # shellcheck disable=SC1090
  source "$config"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)       shift 2 ;;  # already handled
    --server)       E2E_SERVER="${2:?}"; shift 2 ;;
    --port)         E2E_PORT="${2:?}"; shift 2 ;;
    --identity)     E2E_IDENTITY="${2:?}"; shift 2 ;;
    --jump)         E2E_JUMP="${2:?}"; shift 2 ;;
    --set-env)      E2E_SET_ENV="${2:?}"; shift 2 ;;
    --bin-dir)      E2E_ARTIFACT_BIN_DIR="${2:?}"; shift 2 ;;
    --lib-dir)      E2E_ARTIFACT_LIB_DIR="${2:?}"; shift 2 ;;
    --remote-bin)   E2E_REMOTE_BIN_DIR="${2:?}"; shift 2 ;;
    --remote-lib)   E2E_REMOTE_LIB_DIR="${2:?}"; shift 2 ;;
    --test)         E2E_TEST="${2:?}"; shift 2 ;;
    --runner)       E2E_RUNNER="${2:?}"; shift 2 ;;
    --workdir)      E2E_TEST_WORKDIR="${2:?}"; shift 2 ;;
    --pytest-args)  E2E_PYTEST_ARGS="${2:?}"; shift 2 ;;
    --kernel-regex) E2E_KERNEL_REGEX="${2:?}"; shift 2 ;;
    --cmd-regex)    E2E_CMD_REGEX="${2:?}"; shift 2 ;;
    --kernel)       E2E_KERNEL="${2:?}"; shift 2 ;;
    --local-dir)    E2E_LOCAL_DIR="${2:?}"; shift 2 ;;
    --dry-run)      dry_run=1; shift ;;
    --all)          phases=(push run extract pull compile); shift ;;
    -h|--help)      sed -n '2,78p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    push|run|extract|pull|compile) phases+=("$1"); shift ;;
    -*)             die "unknown option: $1" ;;
    *)              die "unknown phase: $1 (use push|run|extract|pull|compile|--all)" ;;
  esac
done

[[ ${#phases[@]} -gt 0 ]] || die "no phase given (push|run|extract|pull|compile or --all)"

# ---- local working dir ----------------------------------------------------
if [[ -z "$E2E_LOCAL_DIR" ]]; then
  E2E_LOCAL_DIR="e2e-debug/$(date +%Y%m%d_%H%M%S)"
fi
run_log="$E2E_LOCAL_DIR/e2e_run.log"
kernel_local="$E2E_LOCAL_DIR/kernel.mlir"
cmd_file="$E2E_LOCAL_DIR/compile_cmd.txt"
kernel_remote_file="$E2E_LOCAL_DIR/kernel_remote_path.txt"
[[ "$dry_run" -eq 1 ]] || mkdir -p "$E2E_LOCAL_DIR"

say() { echo "debug_e2e: $*" >&2; }
need() { [[ -n "${!1}" ]] || die "missing required setting: $1 (set via --config, env, or flag)"; }

resolve_local_bin_dir() {
  [[ -n "$E2E_ARTIFACT_BIN_DIR" ]] && { echo "$E2E_ARTIFACT_BIN_DIR"; return; }
  for d in bishengir-output/bin build/install/bin build/bin; do
    [[ -x "$d/bishengir-compile" ]] && { echo "$d"; return; }
  done
  echo ""
}

# A ready-to-run ssh helper invocation (array) for the configured server.
ssh_base() {
  local -n _out=$1
  _out=("$here/ssh_run.sh" -H "$E2E_SERVER" -p "$E2E_PORT")
  [[ -n "$E2E_IDENTITY" ]] && _out+=(-i "$E2E_IDENTITY")
  [[ -n "$E2E_JUMP" ]] && _out+=(-J "$E2E_JUMP")
}

scp_to()   { # src dst
  local -a c=("$here/scp_transfer.sh" -H "$E2E_SERVER" -p "$E2E_PORT" --to-remote -s "$1" -d "$2")
  [[ -n "$E2E_IDENTITY" ]] && c+=(-i "$E2E_IDENTITY")
  [[ -n "$E2E_JUMP" ]] && c+=(-J "$E2E_JUMP")
  [[ "$dry_run" -eq 1 ]] && c+=(--dry-run)
  "${c[@]}"
}
scp_from() { # remote-src local-dst
  local -a c=("$here/scp_transfer.sh" -H "$E2E_SERVER" -p "$E2E_PORT" --from-remote -s "$1" -d "$2")
  [[ -n "$E2E_IDENTITY" ]] && c+=(-i "$E2E_IDENTITY")
  [[ -n "$E2E_JUMP" ]] && c+=(-J "$E2E_JUMP")
  [[ "$dry_run" -eq 1 ]] && c+=(--dry-run)
  "${c[@]}"
}

# ---- phase: push ----------------------------------------------------------
phase_push() {
  need E2E_SERVER; need E2E_REMOTE_BIN_DIR
  local bindir; bindir="$(resolve_local_bin_dir)"
  [[ -n "$bindir" ]] || die "no local bishengir-compile found; set --bin-dir or build first"
  say "push: binaries from $bindir -> $E2E_SERVER:$E2E_REMOTE_BIN_DIR"

  local -a sb; ssh_base sb
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY: ${sb[*]} -- mkdir -p $E2E_REMOTE_BIN_DIR"
  else
    "${sb[@]}" -- "mkdir -p '$E2E_REMOTE_BIN_DIR'" || die "remote mkdir failed"
  fi
  for b in bishengir-compile bishengir-opt hivmc hivmc-a5; do
    if [[ -e "$bindir/$b" ]]; then
      scp_to "$bindir/$b" "$E2E_REMOTE_BIN_DIR/$b" || die "scp $b failed"
    fi
  done

  if [[ -n "$E2E_ARTIFACT_LIB_DIR" && -n "$E2E_REMOTE_LIB_DIR" ]]; then
    say "push: *.bc from $E2E_ARTIFACT_LIB_DIR -> $E2E_SERVER:$E2E_REMOTE_LIB_DIR"
    if [[ "$dry_run" -eq 1 ]]; then
      echo "DRY: ${sb[*]} -- mkdir -p $E2E_REMOTE_LIB_DIR"
      echo "DRY: scp $E2E_ARTIFACT_LIB_DIR/*.bc -> $E2E_REMOTE_LIB_DIR/"
    else
      "${sb[@]}" -- "mkdir -p '$E2E_REMOTE_LIB_DIR'"
      shopt -s nullglob
      local any=0
      for bc in "$E2E_ARTIFACT_LIB_DIR"/*.bc; do
        scp_to "$bc" "$E2E_REMOTE_LIB_DIR/$(basename "$bc")" || die "scp $(basename "$bc") failed"
        any=1
      done
      shopt -u nullglob
      [[ "$any" -eq 1 ]] || say "push: no *.bc found in $E2E_ARTIFACT_LIB_DIR (skipped)"
    fi
  fi
  say "push: done"
}

# Build the remote command that sources env, sets PATH, cds, and runs the test.
remote_run_cmd() {
  need E2E_SET_ENV; need E2E_TEST
  local workdir="${E2E_TEST_WORKDIR:-$(dirname "$E2E_TEST")}"
  local runner="$E2E_RUNNER"
  local prolog="source '$E2E_SET_ENV'"
  [[ -n "$E2E_REMOTE_BIN_DIR" ]] && prolog="$prolog; export PATH='$E2E_REMOTE_BIN_DIR':\$PATH"
  prolog="$prolog; cd '$workdir'"

  if [[ "$runner" == "auto" ]]; then
    # decide remotely: python if the file has an __main__ guard, else pytest
    runner="__AUTO__"
  fi

  if [[ "$runner" == "pytest" ]]; then
    echo "$prolog; python -m pytest -ra -vv $E2E_PYTEST_ARGS '$E2E_TEST' 2>&1"
  elif [[ "$runner" == "python" ]]; then
    echo "$prolog; python '$E2E_TEST' 2>&1"
  else
    # __AUTO__: branch on the remote file contents
    echo "$prolog; if grep -q '__main__' '$E2E_TEST'; then echo '[debug_e2e] runner=python'; python '$E2E_TEST' 2>&1; else echo '[debug_e2e] runner=pytest'; python -m pytest -ra -vv $E2E_PYTEST_ARGS '$E2E_TEST' 2>&1; fi"
  fi
}

# ---- phase: run -----------------------------------------------------------
phase_run() {
  need E2E_SERVER
  local rcmd; rcmd="$(remote_run_cmd)"
  local -a sb; ssh_base sb
  say "run: on $E2E_SERVER -> log $run_log"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY: ${sb[*]} -- bash -lc \"$rcmd\"  | tee $run_log"
    return 0
  fi
  "${sb[@]}" -- "bash -lc \"$rcmd\"" 2>&1 | tee "$run_log"
  local rc=${PIPESTATUS[0]}
  echo "EXIT CODE: $rc" | tee -a "$run_log"
  say "run: finished (rc=$rc). log: $run_log"
  [[ $rc -ne 0 ]] && say "run: test exited nonzero — proceed to extract/pull/compile to debug"
  return 0
}

# ---- phase: extract -------------------------------------------------------
phase_extract() {
  [[ "$dry_run" -eq 1 ]] && { echo "DRY: parse $run_log for kernel .mlir + bishengir-compile cmd"; return 0; }
  [[ -f "$run_log" ]] || die "no run log at $run_log (run the 'run' phase first)"

  # Find the bishengir-compile invocation (last match wins).
  local cline
  cline="$(grep -aE "$E2E_CMD_REGEX" "$run_log" | grep -a 'bishengir-compile' | tail -n1)"

  local kernel=""
  if [[ -n "$E2E_KERNEL" ]]; then
    kernel="$E2E_KERNEL"
  elif [[ -n "$E2E_KERNEL_REGEX" ]]; then
    kernel="$(grep -aoE "$E2E_KERNEL_REGEX" "$run_log" | tail -n1)"
  elif [[ -n "$cline" ]]; then
    # the .mlir token on the compile command line
    kernel="$(grep -aoE '[^[:space:]]+\.mlir' <<<"$cline" | tail -n1)"
  fi
  # Fallback: any *.mlir path mentioned in the log.
  [[ -z "$kernel" ]] && kernel="$(grep -aoE '[^[:space:]]+\.mlir' "$run_log" | tail -n1)"

  # Compile flags = the compile line minus the leading binary and the .mlir arg.
  local flags=""
  if [[ -n "$cline" ]]; then
    flags="$(sed -E 's#.*bishengir-compile(\.exe)?##' <<<"$cline")"
    [[ -n "$kernel" ]] && flags="${flags//$kernel/}"
    flags="$(echo "$flags" | tr -s ' ' | sed 's/^ //; s/ $//')"
  fi

  echo "$kernel" > "$kernel_remote_file"
  printf '%s\n' "$flags" > "$cmd_file"
  say "extract: kernel.mlir (remote) = ${kernel:-<none found>}"
  say "extract: compile flags        = ${flags:-<none found>}  (saved: $cmd_file)"
  [[ -n "$kernel" ]] || say "extract: WARNING no kernel .mlir found — set --kernel or --kernel-regex"
}

# ---- phase: pull ----------------------------------------------------------
phase_pull() {
  need E2E_SERVER
  local kernel="$E2E_KERNEL"
  if [[ -z "$kernel" && -f "$kernel_remote_file" ]]; then
    kernel="$(cat "$kernel_remote_file")"
  fi
  if [[ -z "$kernel" ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      echo "DRY: scp <remote kernel.mlir from extract phase> -> $kernel_local"
      return 0
    fi
    die "no remote kernel path (run 'extract' or pass --kernel)"
  fi
  say "pull: $E2E_SERVER:$kernel -> $kernel_local"
  scp_from "$kernel" "$kernel_local" || die "scp kernel.mlir back failed"
  say "pull: done"
}

# ---- phase: compile (local re-run with full IR trace) ---------------------
phase_compile() {
  local -a c=("$here/debug_compile.sh")
  local kinput="$kernel_local"
  [[ "$dry_run" -eq 1 || -f "$kinput" ]] || die "no local kernel at $kinput (run 'pull' first)"
  c+=("$kinput")
  [[ -f "$cmd_file" ]] && c+=(--cmd-file "$cmd_file")
  c+=(--split-dumps "$E2E_LOCAL_DIR/ir_dumps" -l "$E2E_LOCAL_DIR/compile_debug.log")
  [[ "$dry_run" -eq 1 ]] && c+=(--dry-run)
  say "compile: local bishengir-compile with --mlir-print-ir-before/after-all"
  "${c[@]}"
  say "compile: per-pass IR in $E2E_LOCAL_DIR/ir_dumps — debug a pass with scripts/debug_opt.sh"
}

# ---- run requested phases in canonical order ------------------------------
say "local working dir: $E2E_LOCAL_DIR"
for want in push run extract pull compile; do
  for p in "${phases[@]}"; do
    if [[ "$p" == "$want" ]]; then
      case "$p" in
        push)    phase_push ;;
        run)     phase_run ;;
        extract) phase_extract ;;
        pull)    phase_pull ;;
        compile) phase_compile ;;
      esac
    fi
  done
done
say "done: $E2E_LOCAL_DIR"
