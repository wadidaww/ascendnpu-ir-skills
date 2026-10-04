#!/usr/bin/env bash
#
# grep_search.sh — Search file contents for a pattern (ripgrep if available, else grep -r).
#
# Usage:
#   scripts/grep_search.sh [options] PATTERN [PATH ...]
#
# PATTERN: regex to search for. PATH: files/dirs to search (default: current directory).
#
# Options:
#   -i, --ignore-case      Case-insensitive match.
#   -w, --word             Match whole words only.
#   -F, --fixed            Treat PATTERN as a literal string, not a regex.
#   -l, --files            List only names of matching files.
#   -c, --count            Print only a count of matching lines per file.
#   -C, --context N        Show N lines of context around each match.
#   -g, --glob GLOB        Only search files matching GLOB (e.g. '*.cpp'). Repeatable.
#   -t, --type TYPE        ripgrep file type filter (e.g. cpp, python, cmake). Repeatable.
#       --hidden           Include hidden files.
#       --no-ignore        Do not honor .gitignore (ripgrep only).
#       --dry-run          Print the command instead of running it.
#   -h, --help             Show this help.
#
# By default .git/, build/, and third-party/ are excluded. Exit code is the
# search tool's own: 0 = matches found, 1 = no matches, 2 = error.
#
# Examples:
#   scripts/grep_search.sh -i 'HIVM' bishengir/lib
#   scripts/grep_search.sh -F 'createLowerToHACCPass' -g '*.cpp' -g '*.h'
#   scripts/grep_search.sh -l -t cmake 'add_mlir_dialect'
#
set -uo pipefail

ignore_case=0
word=0
fixed=0
files_only=0
count=0
context=""
hidden=0
no_ignore=0
dry_run=0
declare -a globs=()
declare -a types=()

die() { echo "grep_search: $*" >&2; exit 2; }

pattern=""
declare -a paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--ignore-case) ignore_case=1; shift ;;
    -w|--word)        word=1; shift ;;
    -F|--fixed)       fixed=1; shift ;;
    -l|--files)       files_only=1; shift ;;
    -c|--count)       count=1; shift ;;
    -C|--context)     context="${2:?}"; shift 2 ;;
    -g|--glob)        globs+=("${2:?}"); shift 2 ;;
    -t|--type)        types+=("${2:?}"); shift 2 ;;
    --hidden)         hidden=1; shift ;;
    --no-ignore)      no_ignore=1; shift ;;
    --dry-run)        dry_run=1; shift ;;
    -h|--help)        sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)               shift; while [[ $# -gt 0 ]]; do paths+=("$1"); shift; done ;;
    -*)               die "unknown option: $1" ;;
    *)
      if [[ -z "$pattern" ]]; then pattern="$1"; else paths+=("$1"); fi
      shift ;;
  esac
done

[[ -n "$pattern" ]] || die "no PATTERN given"
[[ ${#paths[@]} -gt 0 ]] || paths=(".")

if command -v rg >/dev/null 2>&1; then
  declare -a cmd=(rg --line-number --color never
                  --glob '!.git' --glob '!build' --glob '!third-party')
  [[ "$ignore_case" -eq 1 ]] && cmd+=(-i)
  [[ "$word" -eq 1 ]] && cmd+=(-w)
  [[ "$fixed" -eq 1 ]] && cmd+=(-F)
  [[ "$files_only" -eq 1 ]] && cmd+=(-l)
  [[ "$count" -eq 1 ]] && cmd+=(-c)
  [[ -n "$context" ]] && cmd+=(-C "$context")
  [[ "$hidden" -eq 1 ]] && cmd+=(--hidden)
  [[ "$no_ignore" -eq 1 ]] && cmd+=(--no-ignore)
  for g in "${globs[@]}"; do cmd+=(--glob "$g"); done
  for t in "${types[@]}"; do cmd+=(--type "$t"); done
  cmd+=(-e "$pattern" "${paths[@]}")
else
  # Fallback to POSIX grep -r.
  declare -a cmd=(grep -rn --color=never
                  --exclude-dir=.git --exclude-dir=build --exclude-dir=third-party)
  [[ "$ignore_case" -eq 1 ]] && cmd+=(-i)
  [[ "$word" -eq 1 ]] && cmd+=(-w)
  [[ "$fixed" -eq 1 ]] && cmd+=(-F)
  [[ "$files_only" -eq 1 ]] && cmd+=(-l)
  [[ "$count" -eq 1 ]] && cmd+=(-c)
  [[ -n "$context" ]] && cmd+=(-C "$context")
  for g in "${globs[@]}"; do cmd+=(--include="$g"); done
  [[ ${#types[@]} -gt 0 ]] && echo "grep_search: --type ignored (ripgrep not installed)" >&2
  cmd+=(-e "$pattern" "${paths[@]}")
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

exec "${cmd[@]}"
