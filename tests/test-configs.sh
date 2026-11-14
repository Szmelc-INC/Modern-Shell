#!/usr/bin/env bash
# test-configs.sh — validate the shipped nano and tmux configs on real binaries.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

if command -v tmux >/dev/null; then
  if tmux -L "msh-test-$$" -f "$repo/configs/tmux/tmux.conf" start-server \; kill-server; then
    echo "ok - tmux.conf parses"
  else
    echo "not ok - tmux.conf"; fail=1
  fi
fi

if command -v nano >/dev/null && command -v script >/dev/null; then
  mkdir -p "$tmp/.cache/nano/backups"
  # nano prints rc errors before drawing; capture a few seconds of screen output.
  HOME=$tmp TERM=xterm-256color timeout 3 script -qc \
    "nano --rcfile='$repo/configs/nano/nanorc' '$tmp/x.txt'" /dev/null > "$tmp/nano.out" 2>&1
  if grep -aiqE 'error|unknown|mistake|not found' "$tmp/nano.out"; then
    echo "not ok - nanorc:"
    tr -c '[:print:]' '\n' < "$tmp/nano.out" | grep -aiE 'error|unknown|mistake|not found' | sort -u | head -10
    fail=1
  else
    echo "ok - nanorc loads without errors"
  fi
fi
exit $fail
