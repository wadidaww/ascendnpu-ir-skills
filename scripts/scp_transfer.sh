#!/usr/bin/env bash
#
# scp_transfer.sh — Copy files/dirs to or from a remote server with scp.
#
# Usage:
#   scripts/scp_transfer.sh [options] --src SRC --dst DST
#
# Direction:
#   --to-remote    SRC is local, DST is a path on the remote host (default).
#   --from-remote  SRC is a path on the remote host, DST is local.
#
# Options:
#   -H, --host HOST        Target host (or user@host). Required unless $SSH_HOST is set.
#   -u, --user USER        Login user (overrides user embedded in --host).
#   -p, --port PORT        SSH port (default: 22).
#   -i, --identity FILE    Private key file (identity).
#   -J, --jump HOST        ProxyJump / bastion host (user@host).
#   -s, --src PATH         Source path (local or remote depending on direction). Required.
#   -d, --dst PATH         Destination path (remote or local depending on direction). Required.
#   -r, --recursive        Copy directories recursively (auto-enabled if SRC is a local dir).
#   -C, --compress         Enable compression.
#       --dry-run          Print the scp command instead of running it.
#   -h, --help             Show this help.
#
# Environment variables used as defaults: SSH_HOST, SSH_USER, SSH_PORT, SSH_IDENTITY.
#
# Examples:
#   # upload a file
#   scripts/scp_transfer.sh -H dev@10.0.0.5 --to-remote -s ./model.mlir -d /work/in/model.mlir
#   # download a directory
#   scripts/scp_transfer.sh -H 10.0.0.5 -u dev -i ~/.ssh/id_rsa --from-remote -r -s /work/out -d ./out
#
set -euo pipefail

host="${SSH_HOST:-}"
user="${SSH_USER:-}"
port="${SSH_PORT:-22}"
identity="${SSH_IDENTITY:-}"
jump=""
direction="to-remote"
src=""
dst=""
recursive=0
compress=0
dry_run=0

die() { echo "scp_transfer: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)      host="${2:?}"; shift 2 ;;
    -u|--user)      user="${2:?}"; shift 2 ;;
    -p|--port)      port="${2:?}"; shift 2 ;;
    -i|--identity)  identity="${2:?}"; shift 2 ;;
    -J|--jump)      jump="${2:?}"; shift 2 ;;
    -s|--src)       src="${2:?}"; shift 2 ;;
    -d|--dst)       dst="${2:?}"; shift 2 ;;
    --to-remote)    direction="to-remote"; shift ;;
    --from-remote)  direction="from-remote"; shift ;;
    -r|--recursive) recursive=1; shift ;;
    -C|--compress)  compress=1; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ -n "$host" ]] || die "no host given (use -H/--host or set \$SSH_HOST)"
[[ -n "$src"  ]] || die "no --src given"
[[ -n "$dst"  ]] || die "no --dst given"

target="$host"
if [[ -n "$user" && "$host" != *"@"* ]]; then
  target="${user}@${host}"
fi

# Auto-enable recursion when copying a local directory up.
if [[ "$direction" == "to-remote" && -d "$src" ]]; then
  recursive=1
fi

declare -a cmd=(scp -P "$port" -o ConnectTimeout=15)
[[ -n "$identity" ]] && cmd+=(-i "$identity")
[[ -n "$jump" ]] && cmd+=(-J "$jump")
[[ "$recursive" -eq 1 ]] && cmd+=(-r)
[[ "$compress" -eq 1 ]] && cmd+=(-C)

if [[ "$direction" == "to-remote" ]]; then
  [[ -e "$src" ]] || die "local source does not exist: $src"
  cmd+=("$src" "${target}:${dst}")
else
  cmd+=("${target}:${src}" "$dst")
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

echo "scp_transfer: ${direction}  ${src} -> ${dst}" >&2
exec "${cmd[@]}"
