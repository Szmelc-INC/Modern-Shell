#!/usr/bin/env bash
# test-zinit.sh — the real daily path: interactive zsh in a terminal (tmux) with
# zinit, p10k, fzf-tab, fast-syntax-highlighting and autosuggestions loaded.
# Uses a COPY of ~/.local/share/zinit in a throwaway $HOME (never the real one).
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
src_zinit=${XDG_DATA_HOME:-$HOME/.local/share}/zinit
[[ -d $src_zinit/zinit.git ]] || { echo "skip - no local zinit to copy"; exit 0; }
tmp=$(mktemp -d)
sock="msh-zi-$$"
trap 'tmux -L "$sock" kill-server 2>/dev/null; chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= SHELL=/bin/zsh NO_COLOR=1
unset MSH_HOME MSH_USER MSH_CACHE MSH_BACKUP ZDOTDIR ZINIT_HOME
mkdir -p "$HOME/.local/share"
cp -a "$src_zinit" "$HOME/.local/share/zinit"
bash "$repo/install.sh" -y --no-deps --no-chsh --no-binary >/dev/null 2>&1

out=$tmp/out.txt
tmux -L "$sock" -f /dev/null new-session -d -x 120 -y 30 "env HOME=$HOME TERM=xterm-256color zsh -i"
sleep 4   # instant prompt, then turbo (wait lucid) plugins
tmux -L "$sock" send-keys "whence -w p10k _zsh_autosuggest_start fast-theme fzf-tab-complete cd > $out 2>&1; echo DONE >> $out" Enter
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q DONE "$out" 2>/dev/null && break; sleep 1; done
cat "$out"
screen=$(tmux -L "$sock" capture-pane -p)
fail=0
for f in p10k _zsh_autosuggest_start fast-theme fzf-tab-complete cd; do
  grep -q "^$f: function" "$out" || { echo "not ok - $f not loaded"; fail=1; }
done
if grep -qiE 'error|command not found|no such file' <<<"$screen"; then
  echo "not ok - errors on screen:"; echo "$screen"; fail=1
fi
(( fail )) && exit 1
echo "ok - zinit, p10k, fzf-tab, autosuggestions, fast-syntax-highlighting and zoxide cd load in a real terminal"
