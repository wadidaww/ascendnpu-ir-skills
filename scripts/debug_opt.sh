#!/usr/bin/env bash
#
# debug_opt.sh — Debugging type A: run `bishengir-opt` on an MLIR input with
# debug/print options, log everything, and optionally split per-pass IR dumps.
#
# bishengir-opt is a standard MLIR opt driver (MlirOptMain), so it accepts all
# the usual --mlir-print-ir-* / --debug flags plus AscendNPU-IR passes and
# --target=.
#
# Usage:
#   scripts/debug_opt.sh [options] INPUT.mlir [-- RAW_OPT_ARGS ...]
#
# Options:
#   -b, --bin PATH          Path to bishengir-opt (else auto-resolved; see below).
#   -p, --pass "ARGS"       Pass/pipeline args, e.g. "--your-pass" or
#                           "-pass-pipeline=builtin.module(...)". Repeatable.
#       --target T          Pass --target=T (routes to bishengir-opt-a5 for A5 targets).
#
#   Debug/print presets (map to standard MLIR flags):
#       --print-after-all   --mlir-print-ir-after-all
#       --print-before-all  --mlir-print-ir-before-all
#       --print-after PASS  --mlir-print-ir-after=PASS
#       --print-before PASS --mlir-print-ir-before=PASS
#       --around PASS       print IR both before and after PASS
#       --print-after-change    --mlir-print-ir-after-change
#       --print-after-failure   --mlir-print-ir-after-failure
#       --debug             --debug (all llvm debug output)
#       --debug-only X      --debug-only=X (comma-separated DEBUG_TYPEs)
#       --verify-each       --verify-each
#       --keep-threading    do NOT add --mlir-disable-threading
#                           (threading is disabled by default when printing IR,
#                            so dumps stay ordered)
#
#   --split-dumps DIR       After the run, split per-pass IR dumps into DIR/ via
#                           split_ir_dump.py (one .mlir per pass boundary).
#   -o, --output FILE       Write bishengir-opt's transformed IR (stdout) here.
#   -l, --log FILE          Log file (default: logs/debug_opt_<input>_<ts>.log).
#       --dry-run           Print the command; run nothing.
#   -h, --help              Show this help.
#
# Binary resolution order: --bin, $BISHENGIR_OPT, $ASCENDNPU_IR_BIN/bishengir-opt,
#   bishengir-output/bin, build/install/bin, build/bin, then PATH.
#
# Examples:
#   scripts/debug_opt.sh kernel.mlir -p "--hfusion-outline" --around HFusionOutline
#   scripts/debug_opt.sh in.mlir -p "-pass-pipeline=builtin.module(cse)" --print-after-all \
#       --split-dumps ir_dumps/
#   scripts/debug_opt.sh in.mlir --debug-only=hivm --target Ascend910B -- --mlir-timing
#
set -uo pipefail

bin=""
input=""
output=""
log=""
target=""
split_dir=""
dry_run=0
keep_threading=0
declare -a passes=()
declare -a dbg=()       # assembled debug/print flags
declare -a raw=()       # pass-through after --
printing=0

die() { echo "debug_opt: $*" >&2; exit 2; }

resolve_bin() {
  local name="bishengir-opt"
  [[ -n "$bin" ]] && { echo "$bin"; return; }
  [[ -n "${BISHENGIR_OPT:-}" ]] && { echo "$BISHENGIR_OPT"; return; }
  local cands=(
    "${ASCENDNPU_IR_BIN:-}/$name"
    "bishengir-output/bin/$name"
    "build/install/bin/$name"
    "build/bin/$name"
  )
  for c in "${cands[@]}"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return; }
  done
  command -v "$name" 2>/dev/null && return
  echo "$name"   # last resort; will fail loudly if missing
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bin)             bin="${2:?}"; shift 2 ;;
    -p|--pass)            passes+=("${2:?}"); shift 2 ;;
    --target)             target="${2:?}"; shift 2 ;;
    --print-after-all)    dbg+=(--mlir-print-ir-after-all); printing=1; shift ;;
    --print-before-all)   dbg+=(--mlir-print-ir-before-all); printing=1; shift ;;
    --print-after)        dbg+=("--mlir-print-ir-after=${2:?}"); printing=1; shift 2 ;;
    --print-before)       dbg+=("--mlir-print-ir-before=${2:?}"); printing=1; shift 2 ;;
    --around)             dbg+=("--mlir-print-ir-before=${2:?}" "--mlir-print-ir-after=${2:?}"); printing=1; shift 2 ;;
    --print-after-change) dbg+=(--mlir-print-ir-after-change); printing=1; shift ;;
    --print-after-failure)dbg+=(--mlir-print-ir-after-failure); printing=1; shift ;;
    --debug)              dbg+=(--debug); shift ;;
    --debug-only)         dbg+=("--debug-only=${2:?}"); shift 2 ;;
    --verify-each)        dbg+=(--verify-each); shift ;;
    --keep-threading)     keep_threading=1; shift ;;
    --split-dumps)        split_dir="${2:?}"; shift 2 ;;
    -o|--output)          output="${2:?}"; shift 2 ;;
    -l|--log)             log="${2:?}"; shift 2 ;;
    --dry-run)            dry_run=1; shift ;;
    -h|--help)            sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)                   shift; raw=("$@"); break ;;
    -*)                   die "unknown option: $1" ;;
    *)                    if [[ -z "$input" ]]; then input="$1"; else raw+=("$1"); fi; shift ;;
  esac
done

[[ -n "$input" ]] || die "no INPUT.mlir given"
[[ "$dry_run" -eq 1 || -f "$input" ]] || die "input not found: $input"

opt_bin="$(resolve_bin)"

# Disable threading when printing IR so the dump order is deterministic.
if [[ "$printing" -eq 1 && "$keep_threading" -eq 0 ]]; then
  dbg+=(--mlir-disable-threading)
fi

declare -a cmd=("$opt_bin")
[[ -n "$target" ]] && cmd+=("--target=$target")
for p in "${passes[@]}"; do
  # allow a single --pass value to contain multiple space-separated flags
  # shellcheck disable=SC2206
  arr=($p); cmd+=("${arr[@]}")
done
[[ ${#dbg[@]} -gt 0 ]] && cmd+=("${dbg[@]}")
[[ ${#raw[@]} -gt 0 ]] && cmd+=("${raw[@]}")
cmd+=("$input")

if [[ -z "$log" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  safe="$(basename "$input" | sed 's/[^A-Za-z0-9._-]/_/g')"
  log="logs/debug_opt_${safe}_${ts}.log"
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'DRY: '; printf '%q ' "${cmd[@]}"
  [[ -n "$output" ]] && printf '> %q' "$output"
  echo
  [[ -n "$split_dir" ]] && echo "DRY: then split_ir_dump.py -i $log -o $split_dir"
  exit 0
fi

[[ -x "$opt_bin" ]] || command -v "$opt_bin" >/dev/null 2>&1 || die "bishengir-opt not found/executable: $opt_bin (use --bin or set \$BISHENGIR_OPT)"
mkdir -p "$(dirname "$log")"

echo "debug_opt: bin=$opt_bin" >&2
echo "debug_opt: logging to $log" >&2
{
  echo "# command : ${cmd[*]}"
  echo "# started : $(date -Is)"
  echo "# --------------------------------------------------------------"
} > "$log"

# stdout (transformed IR) -> optional --output; stderr (IR dumps/debug) -> log.
# Both are also mirrored into the log so the full picture is in one file.
if [[ -n "$output" ]]; then
  "${cmd[@]}" > >(tee "$output" >>"$log") 2> >(tee -a "$log" >&2)
  rc=${PIPESTATUS[0]}
else
  "${cmd[@]}" >>"$log" 2> >(tee -a "$log" >&2)
  rc=${PIPESTATUS[0]}
fi

{
  echo "# --------------------------------------------------------------"
  echo "# finished: $(date -Is)"
  echo "EXIT CODE: $rc"
} >> "$log"
echo "EXIT CODE: $rc  (log: $log)" >&2

if [[ -n "$split_dir" ]]; then
  python3 "$(dirname "$0")/split_ir_dump.py" -i "$log" -o "$split_dir" || \
    echo "debug_opt: split_ir_dump failed (no IR markers? add --print-after-all/-before-all)" >&2
fi

exit "$rc"
