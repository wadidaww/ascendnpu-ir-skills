#!/usr/bin/env bash
#
# run_pytest.sh — Run pytest on a file or directory and record output (incl. errors) to a log file.
#
# Usage:
#   scripts/run_pytest.sh [options] [TARGET] [-- EXTRA_PYTEST_ARGS ...]
#
# TARGET: a test file or directory (default: current directory).
#
# Options:
#   -l, --log FILE      Log file path. Default: logs/pytest_<target>_<timestamp>.log
#   -k, --filter EXPR   Only run tests matching EXPR (pytest -k).
#   -m, --mark EXPR     Only run tests matching marker EXPR (pytest -m).
#   -x, --exitfirst     Stop after the first failure.
#   -v, --verbose       Verbose output (-vv passed to pytest).
#   -j, --jobs N        Run in parallel with N workers (needs pytest-xdist).
#       --no-tee        Do not echo to the terminal; write only to the log file.
#       --dry-run       Print the pytest command instead of running it.
#   -h, --help          Show this help.
#
# The full stdout+stderr is captured to the log file. Both the console and the
# log also get a trailing "EXIT CODE: N" line so failures are easy to find.
# The script exits with pytest's own exit code.
#
# Examples:
#   scripts/run_pytest.sh tests/test_lowering.py
#   scripts/run_pytest.sh tests/ -k hivm -x -l logs/hivm.log
#   scripts/run_pytest.sh tests/ -- --maxfail=3 --tb=short
#
set -uo pipefail

target="."
log=""
filter=""
mark=""
exitfirst=0
verbose=0
jobs=""
tee_out=1
dry_run=0
declare -a extra=()

die() { echo "run_pytest: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--log)       log="${2:?}"; shift 2 ;;
    -k|--filter)    filter="${2:?}"; shift 2 ;;
    -m|--mark)      mark="${2:?}"; shift 2 ;;
    -x|--exitfirst) exitfirst=1; shift ;;
    -v|--verbose)   verbose=1; shift ;;
    -j|--jobs)      jobs="${2:?}"; shift 2 ;;
    --no-tee)       tee_out=0; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)             shift; extra+=("$@"); break ;;
    -*)             die "unknown option: $1" ;;
    *)              target="$1"; shift ;;
  esac
done

[[ -e "$target" ]] || die "target does not exist: $target"

# Default log path: logs/pytest_<sanitized-target>_<timestamp>.log
if [[ -z "$log" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  safe="$(printf '%s' "$target" | sed 's#[/.]#_#g; s#^_*##; s#_*$##')"
  [[ -z "$safe" ]] && safe="all"
  log="logs/pytest_${safe}_${ts}.log"
fi
mkdir -p "$(dirname "$log")"

# Pick a pytest invocation that works with or without a console entry point.
if command -v pytest >/dev/null 2>&1; then
  declare -a pytest=(pytest)
else
  declare -a pytest=(python -m pytest)
fi

declare -a cmd=("${pytest[@]}" -ra)
[[ "$verbose" -eq 1 ]] && cmd+=(-vv)
[[ "$exitfirst" -eq 1 ]] && cmd+=(-x)
[[ -n "$filter" ]] && cmd+=(-k "$filter")
[[ -n "$mark" ]] && cmd+=(-m "$mark")
[[ -n "$jobs" ]] && cmd+=(-n "$jobs")
[[ ${#extra[@]} -gt 0 ]] && cmd+=("${extra[@]}")
cmd+=("$target")

if [[ "$dry_run" -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

{
  echo "# command : ${cmd[*]}"
  echo "# started : $(date -Is)"
  echo "# target  : $target"
  echo "# ----------------------------------------------------------------"
} > "$log"

echo "run_pytest: logging to $log" >&2

# Run, capturing combined stdout+stderr. Use PIPESTATUS to recover pytest's code.
if [[ "$tee_out" -eq 1 ]]; then
  "${cmd[@]}" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
else
  "${cmd[@]}" >> "$log" 2>&1
  rc=$?
fi

{
  echo "# ----------------------------------------------------------------"
  echo "# finished: $(date -Is)"
  echo "EXIT CODE: $rc"
} >> "$log"

echo "EXIT CODE: $rc  (log: $log)" >&2
exit "$rc"
