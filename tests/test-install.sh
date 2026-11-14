#!/usr/bin/env bash
# test-install.sh — install into a throwaway $HOME, start an interactive zsh, uninstall.
# Never touches the real home directory. zinit is disabled (offline, fast).
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= NO_COLOR=1 SHELL=/bin/zsh
unset MSH_HOME MSH_USER MSH_CACHE MSH_BACKUP ZDOTDIR
mkdir -p "$HOME/.zsh"
printf 'echo old-rc\n' > "$HOME/.zshrc"
printf 'export FAKE_SECRET=from-secure\n' > "$HOME/.zsh/secure.zsh"
ok() { echo "ok - $*"; }
nok() { echo "not ok - $*"; exit 1; }

bash "$repo/install.sh" -y --no-deps --no-chsh ${MSH_TEST_BINARY:+} $([[ -n ${MSH_TEST_BINARY-} ]] || echo --no-binary) > "$tmp/install.log" 2>&1 \
  || { cat "$tmp/install.log"; nok "install failed"; }
ok "install ran"
grep -q 'Modern Shell loader stub' "$HOME/.zshrc" && ok "zshrc stub written"
[[ -f $HOME/.config/msh/rc.d/00-init.zsh ]] && ok "framework deployed"
[[ $(stat -c %a "$HOME/.config/msh/user/secrets.zsh") == 600 ]] && ok "secrets.zsh is 600"
ls "$HOME/.BACKUP/msh" | grep -q '_pre-install$' && ok "pre-install snapshot taken"
grep -q 'old-rc' "$HOME"/.BACKUP/msh/*_pre-install/files/.zshrc && ok "old zshrc inside snapshot"
[[ $(cat "$HOME/.zsh/secure.zsh") == 'export FAKE_SECRET=from-secure' ]] && ok "secure.zsh untouched"

# user layer survives a re-install
echo "alias keepme='echo kept'" >> "$HOME/.config/msh/user/aliases.zsh"
bash "$repo/install.sh" -y --no-deps --no-chsh --no-binary > "$tmp/install2.log" 2>&1 || nok "reinstall failed"
grep -q keepme "$HOME/.config/msh/user/aliases.zsh" && ok "user layer kept on reinstall"

# interactive shell: no errors, features present
printf 'MSH_ZINIT=0\n' >> "$HOME/.config/msh/user/msh.conf"
out=$(cd "$HOME" && zsh -i -c 'print -r -- "ADDONS=${(j:,:)MSH_ADDONS_LOADED}"; whence -w cd snapshot keepme mkcd | tr "\n" " "; echo; echo "SECRET=$FAKE_SECRET"' 2>"$tmp/zsh.err")
echo "$out"
[[ ! -s $tmp/zsh.err ]] || { cat "$tmp/zsh.err"; nok "zsh -i printed errors"; }
ok "interactive zsh starts cleanly"
grep -q 'snapshot: function' <<<"$out" && ok "snapshot addon loaded"
grep -q 'keepme: alias' <<<"$out" && ok "user alias loaded"
grep -q 'SECRET=from-secure' <<<"$out" && ok "external secure.zsh still sourced"
if command -v zoxide >/dev/null; then grep -q 'cd: function' <<<"$out" && ok "zoxide owns cd"; fi
# Aliases from core-aliases (cp -iv, mkdir -pv) must not leak into addon functions.
leak=$(cd "$HOME" && zsh -i -c 'whence -f msh::snap_create msh::snap_restore' 2>/dev/null | grep -cE 'cp -iv|mkdir -pv' || true)
[[ $leak == 0 ]] && ok "no alias expansion inside addon functions" || nok "aliases leaked into functions ($leak)"
lines=$(cd "$HOME" && zsh -i -c 'snapshot create -l itest' 2>&1 | wc -l)
[[ $lines == 1 ]] && ok "interactive snapshot create prints one line" || nok "snapshot printed $lines lines"
(cd "$HOME" && zsh -i -c 'alias cp' 2>/dev/null | grep -q 'cp -iv') && ok "interactive aliases still defined"
printf 'a\nb\n' > "$tmp/two"
[[ $(cd "$HOME" && script -qc "zsh -i -c 'cat -n $tmp/two'" /dev/null | grep -c '1.*a') -ge 1 ]] && ok "cat -n on a terminal uses real cat"
start=$(date +%s%N); (cd "$HOME" && zsh -i -c exit) 2>/dev/null; end=$(date +%s%N)
echo "startup: $(( (end-start)/1000000 )) ms (no zinit)"

bash "$repo/uninstall.sh" -y > "$tmp/uninstall.log" 2>&1 || { cat "$tmp/uninstall.log"; nok "uninstall failed"; }
[[ $(cat "$HOME/.zshrc") == 'echo old-rc' ]] && ok "uninstall restored the old zshrc"
[[ ! -e $HOME/.config/msh ]] && ok "uninstall removed msh home (did not exist before)"
[[ ! -e $HOME/.nanorc ]] && ok "uninstall removed ~/.nanorc (did not exist before)"
echo "ALL PASSED"
