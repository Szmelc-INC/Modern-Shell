#!/usr/bin/env zsh
# NAME: msh
# DESC: Shell integration for the msh TUI — jump to directories picked in it, quick shortcuts
# TAGS: CORE
# DEP: msh
# DEFAULT: on
# VER: 1.0
# DEV: SilverX
# EXAMPLE: msh            — open the TUI; Enter on a directory cds this shell there
# EXAMPLE: msh-edit-local — open user/local.zsh in $EDITOR
# | A program cannot change its parent shell's directory, so `msh` is wrapped:
# | the TUI writes the chosen directory to a temp file and this function `cd`s
# | there after the TUI exits. Every other `msh` subcommand passes straight through.

# msh [args] — Modern Shell manager (TUI without args); follows directory jumps
msh() {
  (( $+commands[msh] )) || { msh::err "msh binary not found — run the Modern Shell installer"; return 127; }
  local cdfile
  cdfile=$(mktemp "${TMPDIR:-/tmp}/msh-cd.XXXXXX") || { command msh "$@"; return; }
  MSH_CD_FILE=$cdfile command msh "$@"
  local rc=$? dir
  [[ -s $cdfile ]] && dir=$(<"$cdfile")
  rm -f -- "$cdfile"
  [[ -n $dir && -d $dir ]] && cd -- "$dir"
  return $rc
}

# Open the msh TUI on the Snapshots tab
alias msh-snaps='msh tui snapshots'
# Edit machine-local shell config (sourced after everything else)
alias msh-edit-local='${EDITOR:-nano} "$MSH_USER/local.zsh"'
# Edit msh settings (user/msh.conf)
alias msh-edit-conf='${EDITOR:-nano} "$MSH_USER/msh.conf"'
