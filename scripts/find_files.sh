#!/usr/bin/env bash
#
# find_files.sh — Find files within a directory by name/glob, type, size, or age.
#
# Usage:
#   scripts/find_files.sh [options] [DIR]
#
# DIR: directory to search (default: current directory).
#
# Options:
#   -n, --name GLOB      Match file name by glob, case-sensitive (e.g. '*.mlir'). Repeatable.
#   -i, --iname GLOB     Match file name by glob, case-insensitive. Repeatable.
#   -t, --type T         Limit to type: f (file), d (dir), l (symlink). Default: f.
#   -d, --maxdepth N     Limit recursion depth.
#   -e, --ext EXT        Shortcut for --iname '*.EXT' (e.g. -e py). Repeatable.
#       --newer-than SPEC Only entries modified within SPEC (find -newermt), e.g. '1 day ago'.
#       --size SPEC      Size filter passed to find -size, e.g. +1M, -10k.
#       --exclude GLOB   Prune paths matching GLOB (e.g. '*/build/*'). Repeatable.
#   -0, --print0         NUL-separated output (safe for xargs -0).
#       --dry-run        Print the find command instead of running it.
#   -h, --help           Show this help.
#
# By default ./.git, ./build, and ./third-party are pruned (AscendNPU-IR friendly).
# Pass --exclude '' once to disable the default prunes.
#
# Examples:
#   scripts/find_files.sh -e mlir bishengir/test
#   scripts/find_files.sh -n 'CMakeLists.txt' -d 3 .
#   scripts/find_files.sh -i '*lower*' --exclude '*/docs/*' bishengir/lib
#
set -euo pipefail

dir="."
type="f"
maxdepth=""
size=""
newer=""
print0=0
dry_run=0
declare -a names=()
declare -a inames=()
declare -a excludes=()
default_prunes=1

die() { echo "find_files: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)       names+=("${2:?}"); shift 2 ;;
    -i|--iname)      inames+=("${2:?}"); shift 2 ;;
    -e|--ext)        inames+=("*.${2:?}"); shift 2 ;;
    -t|--type)       type="${2:?}"; shift 2 ;;
    -d|--maxdepth)   maxdepth="${2:?}"; shift 2 ;;
    --size)          size="${2:?}"; shift 2 ;;
    --newer-than)    newer="${2:?}"; shift 2 ;;
    --exclude)       if [[ -z "$2" ]]; then default_prunes=0; else excludes+=("$2"); fi; shift 2 ;;
    -0|--print0)     print0=1; shift ;;
    --dry-run)       dry_run=1; shift ;;
    -h|--help)       sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)              die "unknown option: $1" ;;
    *)               dir="$1"; shift ;;
  esac
done

[[ -d "$dir" ]] || die "not a directory: $dir"

if [[ "$default_prunes" -eq 1 ]]; then
  excludes+=('*/.git/*' '*/build/*' '*/third-party/*')
fi

declare -a cmd=(find "$dir")
[[ -n "$maxdepth" ]] && cmd+=(-maxdepth "$maxdepth")

# Prune excluded paths: \( -path A -o -path B \) -prune -o ...
if [[ ${#excludes[@]} -gt 0 ]]; then
  cmd+=('(')
  first=1
  for ex in "${excludes[@]}"; do
    [[ $first -eq 0 ]] && cmd+=(-o)
    cmd+=(-path "$ex")
    first=0
  done
  cmd+=(')' -prune -o)
fi

cmd+=(-type "$type")

# Name matches: OR together all name/iname patterns.
total=$(( ${#names[@]} + ${#inames[@]} ))
if [[ $total -gt 0 ]]; then
  cmd+=('(')
  first=1
  for n in "${names[@]}"; do
    [[ $first -eq 0 ]] && cmd+=(-o)
    cmd+=(-name "$n"); first=0
  done
  for n in "${inames[@]}"; do
    [[ $first -eq 0 ]] && cmd+=(-o)
    cmd+=(-iname "$n"); first=0
  done
  cmd+=(')')
fi

[[ -n "$size" ]]  && cmd+=(-size "$size")
[[ -n "$newer" ]] && cmd+=(-newermt "$newer")

if [[ "$print0" -eq 1 ]]; then
  cmd+=(-print0)
else
  cmd+=(-print)
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

exec "${cmd[@]}"
