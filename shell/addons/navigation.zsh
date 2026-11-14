#!/usr/bin/env zsh
# NAME: navigation
# DESC: Move around quickly: .. / ... / ...., up N, mkcd, fsearch (find by name and jump), cdf (jump to a file's dir)
# TAGS: NAVIGATION, FILES
# DEP: fzf (optional), zoxide (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: mkcd ~/src/new-project
# EXAMPLE: up 3
# EXAMPLE: fsearch config
# | Merged from ZRC `lazy-cd`, `mkcd`, the `.zshrc` `mkcd` and `test.zsh` `fsearch`.
# | Every jump goes through `cd`, so it is recorded by **zoxide** (which owns `cd`;
# | this addon never redefines it).
# |
# | | Command | What it does |
# | |---|---|
# | | `..` `...` `....` | go up 1 / 2 / 3 levels |
# | | `up [N]` | go up N levels (default 1) |
# | | `mkcd DIR` | create DIR (with parents) and enter it |
# | | `fsearch NAME` | find a file/dir whose base name (without extension) is NAME, offer to jump there |
# | | `cdf [TERM]` | fuzzy-pick a file (fzf) and cd into its directory |

# Go up one directory
alias ..='cd ..'
# Go up two directories
alias ...='cd ../..'
# Go up three directories
alias ....='cd ../../..'

# up [N] — go up N directory levels (default 1)
up() {
  local n=${1:-1}
  [[ $n == <1-> ]] || { print -u2 "usage: up [N]"; return 2; }
  local d=.. i
  for (( i = 1; i < n; i++ )); do d+=/..; done
  cd -- "$d"
}

# mkcd DIR — create a directory (with parents) and cd into it
mkcd() {
  [[ -n ${1-} ]] || { print -u2 "usage: mkcd <dir>"; return 2; }
  command mkdir -p -- "$1" && cd -- "$1"
}

# fsearch NAME — find the first file/dir whose base name (sans extension) is NAME and offer to cd there
fsearch() {
  emulate -L zsh
  [[ -n ${1-} ]] || { print -u2 "usage: fsearch <name>"; return 2; }
  local f b p="" ans
  while IFS= read -r -d '' f; do
    b=${f:t}; b=${b%%.*}
    if [[ $b == "$1" ]]; then p=${f:A}; break; fi
  done < <(find . -print0 2>/dev/null)
  [[ -n $p ]] || { msh::warn "not found: $1"; return 1; }
  msh::ok "found: $p"
  read -r "ans?Jump there? (cd) [Y/n] "
  if [[ -z $ans || $ans == [yY]* ]]; then
    if [[ -d $p ]]; then cd -- "$p"; else cd -- "${p:h}"; fi
  fi
}

# cdf [TERM] — fuzzy-pick a file below . and cd into its directory
cdf() {
  msh::need fzf || return
  local f
  f=$(find . -type f -iname "*${1-}*" 2>/dev/null | fzf) || return 1
  cd -- "${f:h}"
}
