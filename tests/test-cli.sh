#!/usr/bin/env bash
# test-cli.sh — exercise the msh CLI against a throwaway $HOME with a fresh install.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
export GOMODCACHE=$(go env GOMODCACHE) GOCACHE=$(go env GOCACHE) GOPATH=$(go env GOPATH) GOPROXY=off GOFLAGS=-mod=mod
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= NO_COLOR=1 SHELL=/bin/zsh
export _ZO_DATA_DIR=$tmp/zoxide
unset MSH_HOME MSH_USER MSH_CACHE MSH_BACKUP ZDOTDIR
mkdir -p "$HOME" "$_ZO_DATA_DIR"
ok() { echo "ok - $*"; }
nok() { echo "not ok - $*"; exit 1; }

bash "$repo/install.sh" -y --no-deps --no-chsh > "$tmp/install.log" 2>&1 || { cat "$tmp/install.log"; nok install; }
msh=$HOME/.local/bin/msh
[[ -x $msh ]] && ok "binary built and installed"
[[ -s $HOME/.config/msh/completions/_msh ]] && ok "zsh completion installed"
[[ -s $HOME/.local/share/bash-completion/completions/msh ]] && ok "bash completion installed"

"$msh" alias add gs 'git status -sb' -d 'short status' >/dev/null
"$msh" alias add q2 "echo it's" >/dev/null
"$msh" alias disable q2 >/dev/null
[[ $("$msh" alias show gs) == 'git status -sb' ]] && ok "alias add/show"
"$msh" alias list --json | grep -q '"enabled": false' && ok "alias disable reflected in json"

"$msh" env set EDITOR_THEME dark >/dev/null
printf 'hunter2' | "$msh" secret set DB_PASS >/dev/null
"$msh" secret list | grep -q hunter2 && nok "secret leaked in list"
ok "secret masked in list"
[[ $("$msh" secret show DB_PASS --reveal) == hunter2 ]] && ok "secret reveal"
[[ $(stat -c %a "$HOME/.config/msh/user/secrets.zsh") == 600 ]] && ok "secrets file 600"

"$msh" func add greet -d 'say hi' -b 'echo "hi ${1:-world}"' >/dev/null
"$msh" addon disable core-aliases >/dev/null
"$msh" addon list --disabled | grep -q core-aliases && ok "addon disable"
"$msh" addon enable core-aliases >/dev/null
"$msh" addon info snapshot --json | grep -q '"name": "snapshot"' && ok "addon info json"
"$msh" addon new my-stuff -d 'mine' --no-edit >/dev/null
"$msh" addon list | grep -q 'my-stuff' && ok "user addon created"
"$msh" addon rm my-stuff -y >/dev/null && ok "user addon removed"
"$msh" addon rm snapshot -y 2>/dev/null && nok "shipped addon must not be removable"
ok "shipped addon removal refused"

# Everything above must load in a real shell.
printf 'MSH_ZINIT=0\n' >> "$HOME/.config/msh/user/msh.conf"
out=$(cd "$HOME" && zsh -i -c 'gs_def=$(alias gs); echo "$gs_def|$(greet you)|$EDITOR_THEME|$DB_PASS"; alias q2 >/dev/null || echo q2-off' 2>"$tmp/zsh.err")
[[ -s $tmp/zsh.err ]] && { cat "$tmp/zsh.err"; nok "zsh errors"; }
[[ $out == *"gs='git status -sb'|hi you|dark|hunter2"* && $out == *q2-off* ]] && ok "zsh sees alias, function, env, secret; disabled alias absent" || nok "zsh view: $out"

if command -v zoxide >/dev/null; then
  mkdir -p "$tmp/proj/alpha"
  "$msh" dir add "$tmp/proj/alpha" >/dev/null
  "$msh" dir list --json | grep -q alpha && ok "zoxide dir add/list"
  "$msh" dir rm "$tmp/proj/alpha" >/dev/null && ok "zoxide dir rm"
fi

"$msh" snapshot create -l cli-test >/dev/null
"$msh" snapshot list --json | grep -q '_cli-test' && ok "snapshot via msh"
"$msh" doctor >/dev/null 2>&1 || "$msh" doctor
ok "doctor runs"

"$msh" __complete addon en | grep -q '^enable' && ok "completion: subcommands"
"$msh" __complete addon info "" | grep -q '^snapshot' && ok "completion: dynamic addon names"
"$msh" __complete alias list --a | grep -q -- '--all' && ok "completion: flags"
zsh -n "$HOME/.config/msh/completions/_msh" && ok "zsh completion parses"
bash -n "$HOME/.local/share/bash-completion/completions/msh" && ok "bash completion parses"
"$msh" nosuchcmd 2>/dev/null && nok "unknown command must fail"
rc=0; "$msh" alias set 2>/dev/null || rc=$?; [[ $rc == 2 ]] && ok "usage errors exit 2"
echo "ALL PASSED"
