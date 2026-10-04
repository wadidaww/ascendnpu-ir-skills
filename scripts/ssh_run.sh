#!/usr/bin/env bash
#
# ssh_run.sh — Open an SSH session or run a remote command on a server.
#
# Usage:
#   scripts/ssh_run.sh [options] [-- COMMAND ...]
#
# Options:
#   -H, --host HOST        Target host (or user@host). Required unless $SSH_HOST is set.
#   -u, --user USER        Login user (overrides user embedded in --host).
#   -p, --port PORT        SSH port (default: 22).
#   -i, --identity FILE    Private key file (identity).
#   -J, --jump HOST        ProxyJump / bastion host (user@host).
#   -o, --option OPT       Extra `ssh -o` option (repeatable), e.g. -o ServerAliveInterval=30.
#   -t, --tty              Force pseudo-terminal allocation (useful for interactive remote tools).
#   -q, --quiet            Quiet mode.
#       --dry-run          Print the ssh command instead of running it.
#   -h, --help             Show this help.
#
# Everything after `--` is executed on the remote host. With no command, an
# interactive login shell is opened.
#
# Environment variables used as defaults: SSH_HOST, SSH_USER, SSH_PORT, SSH_IDENTITY.
#
# Examples:
#   scripts/ssh_run.sh -H user@10.0.0.5
#   scripts/ssh_run.sh -H 10.0.0.5 -u dev -i ~/.ssh/id_ed25519 -- 'uname -a && nvidia-smi'
#   scripts/ssh_run.sh -H server -J bastion.example.com -- 'cd /work && ./run.sh'
#
set -euo pipefail

host="${SSH_HOST:-}"
user="${SSH_USER:-}"
port="${SSH_PORT:-22}"
identity="${SSH_IDENTITY:-}"
jump=""
force_tty=0
quiet=0
dry_run=0
declare -a extra_opts=()

die() { echo "ssh_run: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)     host="${2:?}"; shift 2 ;;
    -u|--user)     user="${2:?}"; shift 2 ;;
    -p|--port)     port="${2:?}"; shift 2 ;;
    -i|--identity) identity="${2:?}"; shift 2 ;;
    -J|--jump)     jump="${2:?}"; shift 2 ;;
    -o|--option)   extra_opts+=("-o" "${2:?}"); shift 2 ;;
    -t|--tty)      force_tty=1; shift ;;
    -q|--quiet)    quiet=1; shift ;;
    --dry-run)     dry_run=1; shift ;;
    -h|--help)     sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)            shift; break ;;
    -*)            die "unknown option: $1" ;;
    *)             host="$1"; shift ;;
  esac
done

[[ -n "$host" ]] || die "no host given (use -H/--host or set \$SSH_HOST)"

# Fold an explicit --user into the host target if host has no user@ part.
target="$host"
if [[ -n "$user" && "$host" != *"@"* ]]; then
  target="${user}@${host}"
fi

declare -a cmd=(ssh -p "$port")
[[ -n "$identity" ]] && cmd+=(-i "$identity")
[[ -n "$jump" ]] && cmd+=(-J "$jump")
[[ "$quiet" -eq 1 ]] && cmd+=(-q)
[[ "$force_tty" -eq 1 ]] && cmd+=(-t)
cmd+=(-o BatchMode=no -o ConnectTimeout=15)
[[ ${#extra_opts[@]} -gt 0 ]] && cmd+=("${extra_opts[@]}")
cmd+=("$target")
[[ $# -gt 0 ]] && cmd+=("$@")

if [[ "$dry_run" -eq 1 ]]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

exec "${cmd[@]}"
