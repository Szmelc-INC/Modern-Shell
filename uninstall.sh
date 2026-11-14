#!/usr/bin/env bash
# uninstall.sh — fully revert Modern Shell by restoring the newest pre-install snapshot.
# A `pre-uninstall` snapshot is taken first, so even this can be undone.
set -euo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MSH_HOME=${MSH_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/msh}
SNAP=$SRC/shell/addons/snapshot.zsh
[[ -r $MSH_HOME/addons/snapshot.zsh ]] && SNAP=$MSH_HOME/addons/snapshot.zsh
export MSH_HOME MSH_TARGETS=$SRC/shell/targets.list
YES=()
[[ ${1-} == -y || ${1-} == --yes ]] && YES=(-y)
[[ ${1-} == -h || ${1-} == --help ]] && { echo "usage: ./uninstall.sh [-y]   restore the newest *_pre-install snapshot"; exit 0; }

# Upgrades also take pre-install snapshots, so pick the newest one taken before
# msh was ever installed (its ~/.zshrc is not the loader stub); else the oldest.
backup=$(zsh "$SNAP" path)
target='' oldest=''
while IFS=$'\t' read -r id _; do
  [[ $id == *_pre-install ]] || continue
  oldest=$id
  if [[ -z $target ]] && ! grep -qs 'Modern Shell loader stub' "$backup/$id/files/.zshrc"; then
    target=$id
  fi
done < <(zsh "$SNAP" list --porcelain)
target=${target:-$oldest}
[[ -n $target ]] || { echo "no *_pre-install snapshot found in $backup — nothing to revert to" >&2; exit 1; }
echo "Reverting to $target"
zsh "$SNAP" create --label pre-uninstall --reason "before uninstall"
zsh "$SNAP" restore "$target" --no-safety "${YES[@]}"
