#!/usr/bin/env bash
# tui-capture.sh — run the real msh TUI inside a detached tmux session (throwaway
# $HOME) and print text captures of a few screens. Usage: tests/tui-capture.sh [keys…]
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
export GOMODCACHE=$(go env GOMODCACHE) GOCACHE=$(go env GOCACHE) GOPATH=$(go env GOPATH) GOPROXY=off GOFLAGS=-mod=mod
tmp=$(mktemp -d)
sock="msh-cap-$$"
trap 'tmux -L "$sock" kill-server 2>/dev/null; chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= SHELL=/bin/zsh _ZO_DATA_DIR=$tmp/zo
unset MSH_HOME MSH_USER MSH_CACHE MSH_BACKUP NO_COLOR
mkdir -p "$HOME" "$_ZO_DATA_DIR"
bash "$repo/install.sh" -y --no-deps --no-chsh >/dev/null 2>&1
msh=$HOME/.local/bin/msh
"$msh" alias add gs 'git status -sb' -d 'short git status' >/dev/null
"$msh" env set PAGER less -d 'default pager' >/dev/null
printf 'hunter2' | "$msh" secret set DB_PASS -d 'local postgres' >/dev/null
zoxide add "$repo" "$HOME" 2>/dev/null || true

tmux -L "$sock" -f /dev/null new-session -d -x "${W:-120}" -y "${H:-34}" \
  "env HOME=$HOME _ZO_DATA_DIR=$_ZO_DATA_DIR TERM=xterm-256color $msh"
sleep 1.2
cap() { echo "════════ $1"; tmux -L "$sock" capture-pane -p; }
cap "start (Addons)"
for k in "${@:-}"; do
  [[ -z $k ]] && continue
  tmux -L "$sock" send-keys "$k"
  sleep 0.6
  cap "after: $k"
done
