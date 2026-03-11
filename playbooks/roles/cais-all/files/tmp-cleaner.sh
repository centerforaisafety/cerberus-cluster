#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

if command -v squeue &>/dev/null; then
  active_jobs=$(squeue -h -w "$(hostname)" 2>/dev/null | wc -l)
  if [ "$active_jobs" -gt 0 ]; then
    exit 0
  fi
fi

# --- Allowlist: never delete these ---
is_protected() {
    local name
    name="$(basename "$1")"
    case "$name" in
      tmux-*|claude-*|systemd-private-*|ssh-*|.X*|.ICE-*|pip-*|jupyter-*)
        return 0 ;;
      .font-unix|.Test-unix|.XIM-unix)
        return 0 ;;
      .nv|mstflint_lockfiles|hsperfdata_*|dcgm*)
        return 0 ;;
      latest_healthcheck.log|node-compile-cache)
        return 0 ;;
    esac
    # Protect directories named after real users (LDAP/local)
    if [ -d "$1" ] && id "$name" &>/dev/null; then
      return 0
    fi
    return 1
}

# --- Nuke everything not on the allowlist ---
for entry in /tmp/*; do
	[ -e "$entry" ] || continue
	case "$entry" in /tmp|/tmp/.|/tmp/..) continue ;; esac
	is_protected "$entry" && continue
	rm -rf -- "$entry"
done

# Also clean hidden entries (dotfiles) not on the allowlist
for entry in /tmp/.*; do
	[ -e "$entry" ] || continue
	case "$entry" in /tmp/.|/tmp/..) continue ;; esac
	is_protected "$entry" && continue
	rm -rf -- "$entry"
done
