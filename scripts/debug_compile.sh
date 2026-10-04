#!/usr/bin/env bash
#
# debug_compile.sh — Debugging type B: run `bishengir-compile` on a kernel.mlir
# with full IR-dump tracing, log everything, and optionally split per-pass IR.
#
# By default it adds --mlir-print-ir-before-all --mlir-print-ir-after-all so you
# get the IR before and after every pass (the basis for analyzing a bad/failed
# pass, and for feeding individual stages into debug_opt.sh).
#
# Usage:
#   scripts/debug_compile.sh [options] KERNEL.mlir [-- RAW_COMPILE_ARGS ...]
#
# Options:
#   -b, --bin PATH          Path to bishengir-compile (else auto-resolved; see below).
#   -c, --cmd "ARGS"        Compile flags captured from an E2E run (string).
#                           These are the exact flags bishengir-compile was
#                           invoked with. Repeatable.
#       --cmd-file FILE     Read compile flags from FILE (whitespace/newline
#                           separated). Combined with any --cmd.
#
#   IR tracing (on by default):
#       --no-print-ir       Do NOT add the print-ir-before/after-all flags.
#       --save-temps DIR    Also pass --save-temps=DIR (intermediate results).
#       --verify-each       Pass --verify-each (verify IR after every pass).
#       --debug             Pass --debug.
#       --debug-only X      Pass --debug-only=X.
#       --keep-threading    Do NOT add --mlir-disable-threading (added by default
#                           while printing IR so dumps stay ordered).
#
#   --split-dumps DIR       After the run, split per-pass IR dumps into DIR/ via
#                           split_ir_dump.py (one .mlir per pass boundary) — this
#                           gives you "the IR before each pass".
#   -o, --output FILE       Write bishengir-compile's stdout artifact here.
#   -l, --log FILE          Log file (default: logs/debug_compile_<input>_<ts>.log).
#       --dry-run           Print the command; run nothing.
#   -h, --help              Show this help.
#
# Binary resolution order: --bin, $BISHENGIR_COMPILE, $ASCENDNPU_IR_BIN/bishengir-compile,
#   bishengir-output/bin, build/install/bin, build/bin, then PATH.
#
# Examples:
#   # Re-run the exact compile that failed in E2E, with full IR trace:
#   scripts/debug_compile.sh kernel.mlir --cmd "--enable-hivm-compile --target=Ascend910B" \
#       --split-dumps ir_dumps/
#   # Flags came from a file the E2E extractor wrote:
#   scripts/debug_compile.sh kernel.mlir --cmd-file compile_cmd.txt --save-temps temps/
#
set -uo pipefail

bin=""
input=""
output=""
log=""
save_temps=""
split_dir=""
cmd_file=""
dry_run=0
print_ir=1
keep_threading=0
declare -a cmdflags=()   # captured compile flags
declare -a dbg=()
declare -a raw=()

die() { echo "debug_compile: $*" >&2; exit 2; }

resolve_bin() {
  local name="bishengir-compile"
  [[ -n "$bin" ]] && { echo "$bin"; return; }
  [[ -n "${BISHENGIR_COMPILE:-}" ]] && { echo "$BISHENGIR_COMPILE"; return; }
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
  echo "$name"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bin)         bin="${2:?}"; shift 2 ;;
    -c|--cmd)         cmdflags+=("${2:?}"); shift 2 ;;
    --cmd-file)       cmd_file="${2:?}"; shift 2 ;;
    --no-print-ir)    print_ir=0; shift ;;
    --save-temps)     save_temps="${2:?}"; shift 2 ;;
    --verify-each)    dbg+=(--verify-each); shift ;;
    --debug)          dbg+=(--debug); shift ;;
    --debug-only)     dbg+=("--debug-only=${2:?}"); shift 2 ;;
    --keep-threading) keep_threading=1; shift ;;
    --split-dumps)    split_dir="${2:?}"; shift 2 ;;
    -o|--output)      output="${2:?}"; shift 2 ;;
    -l|--log)         log="${2:?}"; shift 2 ;;
    --dry-run)        dry_run=1; shift ;;
    -h|--help)        sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)               shift; raw=("$@"); break ;;
    -*)               die "unknown option: $1" ;;
    *)                if [[ -z "$input" ]]; then input="$1"; else raw+=("$1"); fi; shift ;;
  esac
done

[[ -n "$input" ]] || die "no KERNEL.mlir given"
[[ "$dry_run" -eq 1 || -f "$input" ]] || die "input not found: $input"

compile_bin="$(resolve_bin)"

# Fold compile flags from a file into the captured-flags list.
if [[ -n "$cmd_file" ]]; then
  [[ -f "$cmd_file" ]] || die "cmd-file not found: $cmd_file"
  # read all whitespace-separated tokens
  while read -r -a _toks; do cmdflags+=("${_toks[@]}"); done < "$cmd_file"
fi

# Expand captured flag strings (each --cmd may hold several space-separated flags).
declare -a captured=()
for c in "${cmdflags[@]}"; do
  # shellcheck disable=SC2206
  arr=($c); captured+=("${arr[@]}")
done

declare -a trace=()
if [[ "$print_ir" -eq 1 ]]; then
  trace+=(--mlir-print-ir-before-all --mlir-print-ir-after-all)
  [[ "$keep_threading" -eq 0 ]] && trace+=(--mlir-disable-threading)
fi
[[ -n "$save_temps" ]] && trace+=("--save-temps=$save_temps")

declare -a cmd=("$compile_bin")
[[ ${#captured[@]} -gt 0 ]] && cmd+=("${captured[@]}")
[[ ${#trace[@]} -gt 0 ]] && cmd+=("${trace[@]}")
[[ ${#dbg[@]} -gt 0 ]] && cmd+=("${dbg[@]}")
[[ ${#raw[@]} -gt 0 ]] && cmd+=("${raw[@]}")
cmd+=("$input")

if [[ -z "$log" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  safe="$(basename "$input" | sed 's/[^A-Za-z0-9._-]/_/g')"
  log="logs/debug_compile_${safe}_${ts}.log"
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'DRY: '; printf '%q ' "${cmd[@]}"
  [[ -n "$output" ]] && printf '> %q' "$output"
  echo
  [[ -n "$save_temps" ]] && echo "DRY: save-temps dir: $save_temps"
  [[ -n "$split_dir" ]] && echo "DRY: then split_ir_dump.py -i $log -o $split_dir"
  exit 0
fi

[[ -x "$compile_bin" ]] || command -v "$compile_bin" >/dev/null 2>&1 || die "bishengir-compile not found/executable: $compile_bin (use --bin or set \$BISHENGIR_COMPILE)"
mkdir -p "$(dirname "$log")"
[[ -n "$save_temps" ]] && mkdir -p "$save_temps"

echo "debug_compile: bin=$compile_bin" >&2
echo "debug_compile: logging to $log" >&2
{
  echo "# command : ${cmd[*]}"
  echo "# input   : $input"
  echo "# started : $(date -Is)"
  echo "# --------------------------------------------------------------"
} > "$log"

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
    echo "debug_compile: split_ir_dump failed (no IR markers found)" >&2
  echo "debug_compile: per-pass IR in $split_dir — inspect, then debug a pass with scripts/debug_opt.sh" >&2
fi

exit "$rc"
