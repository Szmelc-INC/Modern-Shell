#!/usr/bin/env zsh
# NAME: core-aliases
# DESC: Everyday aliases with modern, colorful replacements (eza, bat, rg) and safe fallbacks
# TAGS: CORE, FILES, EYECANDY
# DEP: eza (optional), bat (optional), highlight (optional)
# DEFAULT: on
# VER: 1.0
# DEV: SilverX
# EXAMPLE: ll        — long listing with git status and icons
# EXAMPLE: cat x.py  — syntax-highlighted when printing to a terminal, raw when piped
# | The baseline "zenfull" output layer. Every alias checks that its tool exists,
# | so a bare system still gets working `ls`/`cat` with colors.
# |
# | - `ls`, `ll`, `la`, `lt`, `tree` → **eza** (icons, git), else GNU `ls --color`
# | - `cat` → **bat** (or **highlight**) only when stdout is a terminal;
# |   pipes and redirects always get the raw bytes. `ccat` is always plain cat.
# | - `grep`, `diff`, `ip` → colored output.

# ls family — eza when available, colored GNU ls otherwise
if (( $+commands[eza] )); then
  # List directory (dirs first, icons)
  alias ls='eza --color=auto --icons=auto --group-directories-first'
  # Long listing with git status, all files
  alias ll='eza -lah --git --icons=auto --group-directories-first --time-style=long-iso'
  # All files, one per line
  alias la='eza -a1 --icons=auto --group-directories-first'
  # List by modification time, newest last
  alias lt='eza -la --sort=modified --icons=auto'
  # Directory tree (eza)
  alias tree='eza --tree --icons=auto --group-directories-first'
else
  # List directory (dirs first, colors)
  alias ls='ls --color=auto --group-directories-first'
  # Long listing, all files, human sizes
  alias ll='ls -lah --color=auto --group-directories-first'
  # All files, one per line
  alias la='ls -A1 --color=auto --group-directories-first'
  # List by modification time, newest last
  alias lt='ls -latr --color=auto'
fi
# Plain ls, no colors or icons
alias lls='command ls'

# cat — syntax highlighting on a terminal, raw bytes in pipes
cat() {
  if [[ -t 1 ]] && (( $# )); then
    if (( $+commands[bat] )); then
      command bat --paging=never --style=plain --color=always -- "$@"; return
    elif (( $+commands[highlight] )); then
      command highlight -O ansi --style=molokai --force -- "$@"; return
    fi
  fi
  command cat "$@"
}
# Plain cat, never highlighted
alias ccat='command cat'

# grep with colors (GNU grep)
alias grep='grep --color=auto'
# diff with colors
alias diff='diff --color=auto'
# ip with colors
alias ip='ip -color=auto'

# Clear the screen
alias c='clear'
# Exit the shell
alias q='exit'
# Restart the shell in place (cleanest way to reload all config)
alias reload='exec zsh'
# Create directories with parents, verbosely
alias mkdir='mkdir -pv'
# Ask before overwriting
alias cp='cp -iv'
# Ask before overwriting on move
alias mv='mv -iv'
# Human-readable disk free
alias df='df -h'
# Human-readable memory usage
alias free='free -h'
# Browse every history file with less
alias histall='command cat ~/.*hist* 2>/dev/null | less'
# Colored paru/yay output
(( $+commands[paru] )) && alias paru='paru --color=auto'
(( $+commands[yay] )) && alias yay='yay --color=auto'
# vim → neovim when installed
(( $+commands[nvim] )) && alias vim='nvim'
