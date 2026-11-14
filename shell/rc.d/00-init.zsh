# 00-init.zsh — environment, XDG, PATH, output helpers, user settings. Runs first.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

export MSH_HOME="${MSH_HOME:-$XDG_CONFIG_HOME/msh}"
export MSH_USER="${MSH_USER:-$MSH_HOME/user}"
export MSH_CACHE="${MSH_CACHE:-$XDG_CACHE_HOME/msh}"
export MSH_BACKUP="${MSH_BACKUP:-$HOME/.BACKUP/msh}"
[[ -d $MSH_CACHE ]] || mkdir -p -- "$MSH_CACHE"

# ── Settings defaults (override in $MSH_USER/msh.conf) ──────────────────────
typeset -g  MSH_ZINIT=${MSH_ZINIT:-1}              # 1 = load zinit + plugins
typeset -g  MSH_ZINIT_AUTOINSTALL=${MSH_ZINIT_AUTOINSTALL:-1}  # clone zinit if missing
typeset -g  MSH_PROMPT=${MSH_PROMPT:-p10k}         # p10k | minimal
typeset -g  MSH_P10K_CONFIG=${MSH_P10K_CONFIG:-$MSH_HOME/conf/p10k.zsh}
typeset -g  MSH_THEFUCK=${MSH_THEFUCK:-1}          # lazy `fuck` alias
typeset -ga MSH_EXTERNAL_SECRETS
(( ${#MSH_EXTERNAL_SECRETS} )) || MSH_EXTERNAL_SECRETS=("$HOME/.zsh/secure.zsh")
typeset -g  EDITOR=${EDITOR:-nano} VISUAL=${VISUAL:-nano} PAGER=${PAGER:-less}
export EDITOR VISUAL PAGER

[[ -r "$MSH_USER/msh.conf" ]] && source "$MSH_USER/msh.conf"

# ── PATH / fpath (deduplicated, so re-sourcing never bloats them) ───────────
typeset -U path fpath
path=("$HOME/.local/bin" "$MSH_HOME/bin" $path)
fpath=("$MSH_HOME/functions" "$MSH_HOME/completions" "$MSH_USER/completions" $fpath)

# ── Output helpers shared by every addon ────────────────────────────────────
# Colors are disabled when NO_COLOR is set or stdout is not a terminal.
msh::_c() { [[ -z ${NO_COLOR-} && -t 1 ]] && print -n -- "$1"; }
# msh::info <msg> — blue informational line
msh::info() { print -r -- "$(msh::_c $'\e[1;34m')::$(msh::_c $'\e[0m') $*"; }
# msh::ok <msg> — green success line
msh::ok()   { print -r -- "$(msh::_c $'\e[1;32m')✔$(msh::_c $'\e[0m') $*"; }
# msh::warn <msg> — yellow warning on stderr
msh::warn() { print -ru2 -- "$(msh::_c $'\e[1;33m')!$(msh::_c $'\e[0m') $*"; }
# msh::err <msg> — red error on stderr
msh::err()  { print -ru2 -- "$(msh::_c $'\e[1;31m')✘$(msh::_c $'\e[0m') $*"; }
# msh::confirm <question> — ask y/N, returns 0 on yes (MSH_YES=1 auto-confirms)
msh::confirm() {
  [[ ${MSH_YES-} == 1 ]] && return 0
  local reply
  read -r "reply?$(msh::_c $'\e[1;33m')?$(msh::_c $'\e[0m') $1 [y/N] " || return 1
  [[ $reply == [yY]* ]]
}
# msh::need <cmd>... — fail with a readable message when a dependency is missing
msh::need() {
  local c
  for c; do
    (( $+commands[$c] )) || { msh::err "missing dependency: $c"; return 127; }
  done
}

# Path of the running shell's rc file (fixes the old `$HOME/.$0rc` trick).
export SHRC="${ZDOTDIR:-$HOME}/.zshrc"
