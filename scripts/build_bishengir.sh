#!/usr/bin/env bash
#
# build_bishengir.sh — Build AscendNPU-IR and produce a runnable `bishengir-compile`.
#
# Wraps the repository's own ./build-tools/build.sh with the flags needed to get
# an installed, collected, runnable bishengir-compile binary, then verifies it.
#
# Usage:
#   scripts/build_bishengir.sh [options]
#
# Source resolution (first that applies):
#   1. --source DIR
#   2. $ASCENDNPU_IR_SRC
#   3. current dir if it contains build-tools/build.sh
#   4. ./AscendNPU-IR if it exists
#   5. clone it (only with --clone)
#
# Options:
#   -s, --source DIR       AscendNPU-IR source tree (contains build-tools/build.sh).
#       --clone            Clone the repo if no source is found.
#       --repo URL         Clone URL (default: https://gitcode.com/Ascend/AscendNPU-IR.git).
#       --mirror           Shortcut: clone from the GitHub mirror instead of GitCode.
#   -o, --build DIR        Build output dir (default: <source>/build).
#       --build-type T     Release | Debug (default: Release).
#   -j, --jobs N           Parallel jobs (default: let build.sh decide).
#       --enable-assertion Build with assertions (recommended while developing).
#       --collect-dir DIR  Where build.sh --collect-binary gathers bins
#                          (default: <source>/bishengir-output). Result: <dir>/bin/bishengir-compile.
#       --no-collect       Do not pass --collect-binary (use the install/ tree instead).
#       --cann PATH        Source CANN env: <PATH>/cann/set_env.sh or ascend-toolkit/set_env.sh.
#       --c-compiler P     C compiler (default: build.sh default, clang).
#       --cxx-compiler P   C++ compiler (default: build.sh default, clang++).
#   -r, --rebuild          Pass -r to build.sh (clear & reconfigure).
#       --skip-submodules  Do not run `git submodule update --init --recursive`.
#       --extra "ARGS"     Extra raw args appended to build.sh (quoted).
#   -l, --log FILE         Log file (default: logs/build_bishengir_<timestamp>.log).
#       --dry-run          Print what would run; make no changes.
#   -h, --help             Show this help.
#
# Notes:
#   * Installation (which collect-binary relies on) runs only when NEITHER
#     --build-test NOR --fast-build is set, so this script intentionally omits
#     both. bishengir-compile is a default build target.
#   * This is a heavy build (it compiles LLVM/MLIR). Needs clang, cmake, ninja,
#     and plenty of disk/RAM. Run it on the target build host, not a laptop.
#
# Examples:
#   scripts/build_bishengir.sh --source ~/AscendNPU-IR -j 64 --enable-assertion
#   scripts/build_bishengir.sh --clone --mirror --cann /usr/local/Ascend
#   ASCENDNPU_IR_SRC=~/src/AscendNPU-IR scripts/build_bishengir.sh --build-type Debug
#
set -uo pipefail

source_dir=""
do_clone=0
repo_url="https://gitcode.com/Ascend/AscendNPU-IR.git"
mirror_url="https://github.com/Ascend/AscendNPU-IR.git"
use_mirror=0
build_dir=""
build_type="Release"
jobs=""
enable_assertion=0
collect_dir=""
do_collect=1
cann_path=""
c_compiler=""
cxx_compiler=""
rebuild=0
skip_submodules=0
extra=""
log=""
dry_run=0

die() { echo "build_bishengir: $*" >&2; exit 2; }
run() { if [[ "$dry_run" -eq 1 ]]; then printf 'DRY: '; printf '%q ' "$@"; echo; else "$@"; fi; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source)        source_dir="${2:?}"; shift 2 ;;
    --clone)            do_clone=1; shift ;;
    --repo)             repo_url="${2:?}"; shift 2 ;;
    --mirror)           use_mirror=1; shift ;;
    -o|--build)         build_dir="${2:?}"; shift 2 ;;
    --build-type)       build_type="${2:?}"; shift 2 ;;
    -j|--jobs)          jobs="${2:?}"; shift 2 ;;
    --enable-assertion) enable_assertion=1; shift ;;
    --collect-dir)      collect_dir="${2:?}"; shift 2 ;;
    --no-collect)       do_collect=0; shift ;;
    --cann)             cann_path="${2:?}"; shift 2 ;;
    --c-compiler)       c_compiler="${2:?}"; shift 2 ;;
    --cxx-compiler)     cxx_compiler="${2:?}"; shift 2 ;;
    -r|--rebuild)       rebuild=1; shift ;;
    --skip-submodules)  skip_submodules=1; shift ;;
    --extra)            extra="${2:?}"; shift 2 ;;
    -l|--log)           log="${2:?}"; shift 2 ;;
    --dry-run)          dry_run=1; shift ;;
    -h|--help)          sed -n '2,56p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                  die "unknown option: $1" ;;
  esac
done

[[ "$use_mirror" -eq 1 ]] && repo_url="$mirror_url"

# ---- resolve source dir ---------------------------------------------------
if [[ -z "$source_dir" ]]; then
  if [[ -n "${ASCENDNPU_IR_SRC:-}" ]]; then
    source_dir="$ASCENDNPU_IR_SRC"
  elif [[ -f "build-tools/build.sh" ]]; then
    source_dir="$(pwd)"
  elif [[ -f "AscendNPU-IR/build-tools/build.sh" ]]; then
    source_dir="$(pwd)/AscendNPU-IR"
  fi
fi

if [[ -z "$source_dir" || ! -f "$source_dir/build-tools/build.sh" ]]; then
  if [[ "$do_clone" -eq 1 ]]; then
    source_dir="${source_dir:-$(pwd)/AscendNPU-IR}"
    echo "build_bishengir: cloning $repo_url -> $source_dir" >&2
    run git clone "$repo_url" "$source_dir" || die "clone failed"
  else
    die "no AscendNPU-IR source found (pass --source DIR, set \$ASCENDNPU_IR_SRC, or use --clone)"
  fi
fi

if [[ "$dry_run" -ne 1 ]]; then
  source_dir="$(cd "$source_dir" && pwd)"
  [[ -f "$source_dir/build-tools/build.sh" ]] || die "build-tools/build.sh not in: $source_dir"
fi

build_dir="${build_dir:-$source_dir/build}"
collect_dir="${collect_dir:-$source_dir/bishengir-output}"

# ---- log setup ------------------------------------------------------------
if [[ -z "$log" ]]; then
  log="logs/build_bishengir_$(date +%Y%m%d_%H%M%S).log"
fi
if [[ "$dry_run" -ne 1 ]]; then
  mkdir -p "$(dirname "$log")"
  : > "$log"
  echo "build_bishengir: logging to $log" >&2
fi

# tee everything (stdout+stderr) to the log when not dry-running.
if [[ "$dry_run" -ne 1 ]]; then
  exec > >(tee -a "$log") 2>&1
fi

echo "# source     : $source_dir"
echo "# build dir  : $build_dir"
echo "# build type : $build_type"
echo "# collect    : $([[ $do_collect -eq 1 ]] && echo "$collect_dir" || echo '(disabled)')"
echo "# started    : $(date -Is)"

# ---- CANN environment -----------------------------------------------------
if [[ -n "$cann_path" ]]; then
  if [[ -f "$cann_path/cann/set_env.sh" ]]; then
    echo "# sourcing   : $cann_path/cann/set_env.sh"
    [[ "$dry_run" -eq 1 ]] || source "$cann_path/cann/set_env.sh"
  elif [[ -f "$cann_path/ascend-toolkit/set_env.sh" ]]; then
    echo "# sourcing   : $cann_path/ascend-toolkit/set_env.sh"
    [[ "$dry_run" -eq 1 ]] || source "$cann_path/ascend-toolkit/set_env.sh"
  elif [[ "$dry_run" -eq 1 ]]; then
    echo "# sourcing   : $cann_path/{cann,ascend-toolkit}/set_env.sh (dry-run: not checked)"
  else
    die "no set_env.sh under $cann_path (cann/ or ascend-toolkit/)"
  fi
fi

# ---- toolchain sanity -----------------------------------------------------
for tool in cmake ninja git; do
  command -v "$tool" >/dev/null 2>&1 || echo "WARNING: '$tool' not found on PATH" >&2
done

# ---- submodules -----------------------------------------------------------
if [[ "$skip_submodules" -eq 0 ]]; then
  echo "# ---- git submodule update --init --recursive ----"
  ( cd "$source_dir" && run git submodule update --init --recursive ) \
    || die "submodule update failed"
fi

# ---- assemble build.sh command -------------------------------------------
declare -a bcmd=("./build-tools/build.sh" -o "$build_dir" --build-type "$build_type")
[[ "$rebuild" -eq 1 ]]          && bcmd+=(-r)
[[ -n "$jobs" ]]                && bcmd+=(-j "$jobs")
[[ "$enable_assertion" -eq 1 ]] && bcmd+=(--enable-assertion)
[[ -n "$c_compiler" ]]          && bcmd+=(--c-compiler "$c_compiler")
[[ -n "$cxx_compiler" ]]        && bcmd+=(--cxx-compiler "$cxx_compiler")
[[ "$do_collect" -eq 1 ]]       && bcmd+=(--collect-binary "$collect_dir")
# NOTE: deliberately NOT passing --build-test or --fast-build, so install runs
# and bishengir-compile is produced and (optionally) collected.
if [[ -n "$extra" ]]; then
  # shellcheck disable=SC2206
  declare -a extra_arr=($extra)
  bcmd+=("${extra_arr[@]}")
fi

echo "# ---- build ----"
echo "# cd $source_dir && ${bcmd[*]}"
if [[ "$dry_run" -eq 1 ]]; then
  echo "DRY: (cd $source_dir && ${bcmd[*]})"
else
  ( cd "$source_dir" && "${bcmd[@]}" )
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "EXIT CODE: $rc  (build failed — see $log)"
    exit "$rc"
  fi
fi

# ---- locate bishengir-compile --------------------------------------------
echo "# ---- locate bishengir-compile ----"
candidates=(
  "$collect_dir/bin/bishengir-compile"
  "$build_dir/install/bin/bishengir-compile"
  "$build_dir/bin/bishengir-compile"
)
found=""
if [[ "$dry_run" -eq 1 ]]; then
  echo "DRY: would check: ${candidates[*]}"
else
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then found="$c"; break; fi
  done
  if [[ -z "$found" ]]; then
    found="$(find "$build_dir" "$collect_dir" -name bishengir-compile -type f -perm -u+x 2>/dev/null | head -n1)"
  fi
  [[ -n "$found" ]] || die "build succeeded but bishengir-compile not found under $build_dir / $collect_dir"
  echo "FOUND: $found"

  echo "# ---- verify (bishengir-compile --help) ----"
  if "$found" --help >/dev/null 2>&1 || "$found" --version >/dev/null 2>&1; then
    echo "OK: bishengir-compile is runnable"
  else
    echo "WARNING: bishengir-compile found but --help/--version returned nonzero; check runtime deps (CANN env?)"
  fi
  echo
  echo "bishengir-compile: $found"
fi

echo "# finished   : $(date -Is)"
echo "EXIT CODE: 0"
