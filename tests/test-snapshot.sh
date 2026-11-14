#!/usr/bin/env bash
# test-snapshot.sh — exercise the snapshot addon against a throwaway $HOME.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home NO_COLOR=1 MSH_YES=1
export MSH_HOME=$HOME/.config/msh MSH_TARGETS=$repo/shell/targets.list
mkdir -p "$HOME/.config/msh/user" "$HOME/.zsh"
echo 'old zshrc' > "$HOME/.zshrc"
echo 'my alias' > "$HOME/.config/msh/user/aliases.zsh"
echo 'SECRET' > "$HOME/.zsh/secure.zsh"
snap() { zsh "$repo/shell/addons/snapshot.zsh" "$@"; }
ok() { echo "ok - $*"; }

snap create -l test -r unit
id=$(cat "$HOME/.BACKUP/msh/.last")
[[ -f $HOME/.BACKUP/msh/$id/files/.zshrc ]] && ok "zshrc saved"
grep -q $'absent\t~/.tmux.conf' "$HOME/.BACKUP/msh/$id/manifest" && ok "absent recorded"
! grep -rq SECRET "$HOME/.BACKUP" && ok "secure.zsh never copied"
[[ $(stat -c %a "$HOME/.BACKUP/msh") == 700 ]] && ok "backup dir is 700"

echo 'new zshrc' > "$HOME/.zshrc"
echo 'tmux' > "$HOME/.tmux.conf"
rm "$HOME/.config/msh/user/aliases.zsh"
snap diff 1 | tee "$tmp/diff"
grep -q '+ ~/.tmux.conf' "$tmp/diff" && ok "diff sees created file"

snap restore "$id" -y
[[ $(cat "$HOME/.zshrc") == 'old zshrc' ]] && ok "zshrc restored"
[[ ! -e $HOME/.tmux.conf ]] && ok "file created after snapshot removed"
[[ -f $HOME/.config/msh/user/aliases.zsh ]] && ok "directory content restored"
[[ $(cat "$HOME/.zsh/secure.zsh") == SECRET ]] && ok "secure.zsh untouched"
n=$(snap list --porcelain | wc -l)
[[ $n == 2 ]] && ok "pre-restore safety snapshot exists ($n)"
snap list

snap rm 1 2 -y
[[ $(snap list --porcelain | wc -l) == 0 ]] && ok "snapshots removed"
echo "ALL PASSED"
