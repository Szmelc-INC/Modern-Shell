#!/usr/bin/env zsh
# NAME: utils
# DESC: Small daily helpers: countdown, remindme, jsonp, calh, syscheck, e (GUI editor), unsource, listrc
# TAGS: CORE, DEV
# DEP: python3 (optional), ncal (optional), notify-send (optional), featherpad (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: countdown 10
# EXAMPLE: remindme 15m "tea is ready"
# EXAMPLE: curl -s api.example.com | jsonp
# EXAMPLE: listrc ~/.zshrc
# | Collected from ZRC `testrc`, `unsource`, `prompt-eol`, `aliases.zsh`.
# |
# | | Command | What it does |
# | |---|---|
# | | `countdown N` | count down N seconds |
# | | `remindme TIME MESSAGE` | desktop notification after TIME (`sleep` syntax: 90, 5m, 1h); runs in the background |
# | | `jsonp` | pretty-print JSON from stdin or a file (jq, else python) |
# | | `calh` | calendar with Monday first |
# | | `syscheck` | CPU model, cores, memory, uptime at a glance |
# | | `e FILE` | open FILE in `$MSH_GUI_EDITOR` (default featherpad), detached |
# | | `unsource FILE` | undo a sourced file: unset its variables, functions and aliases |
# | | `listrc FILE` | list the aliases, functions and exported variables a file defines |
# |
# | Also hides the `%` end-of-line mark zsh prints after output without a newline
# | (`PROMPT_EOL_MARK`); set `PROMPT_EOL_MARK` yourself to keep it.
# | Fixed while porting: `remindme` used to block the shell until the reminder fired.

: ${MSH_GUI_EDITOR:=featherpad}
: ${PROMPT_EOL_MARK=''}

# countdown N — count down N seconds, then print Done!
countdown() {
  local i
  [[ ${1-} == <-> ]] || { print -u2 "usage: countdown <seconds>"; return 2; }
  for (( i = $1; i > 0; i-- )); do print "$i..."; sleep 1; done
  print "Done!"
}

# remindme TIME MESSAGE — desktop notification after TIME (e.g. 90, 5m, 1h), in the background
remindme() {
  (( $# >= 2 )) || { print -u2 "usage: remindme <time> <message>"; return 2; }
  msh::need notify-send || return
  local t=$1; shift
  ( sleep "$t" && notify-send "Reminder" "$*" ) &!
  msh::ok "reminder set for $t"
}

# jsonp [FILE] — pretty-print JSON (jq when available, else python)
jsonp() {
  if (( $+commands[jq] )); then jq . "$@"; else python3 -m json.tool "$@"; fi
}

# Calendar with Monday as the first day, today not highlighted
alias calh='ncal -M -h'

# syscheck — CPU model, cores, memory and uptime at a glance
syscheck() {
  print -P "%BCPU:%b    $(lscpu | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}') ($(nproc) threads)"
  print -P "%BMemory:%b"; free -h
  print -P "%BUptime:%b $(uptime -p)"
}

# e FILE... — open files in the GUI editor ($MSH_GUI_EDITOR), detached from the shell
e() {
  msh::need $MSH_GUI_EDITOR || return
  $MSH_GUI_EDITOR "$@" &>/dev/null &!
}

# unsource FILE — unset the variables, functions and aliases a file defines
unsource() {
  emulate -L zsh
  [[ -f ${1-} ]] || { print -u2 "usage: unsource <file>"; return 2; }
  local name
  for name in ${(f)"$(sed -nE 's/^[[:space:]]*(export[[:space:]]+|typeset[^=]*[[:space:]]|local[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' -- "$1")"}; do
    unset "$name" 2>/dev/null
  done
  for name in ${(f)"$(sed -nE 's/^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*\(\).*/\2/p; s/^[[:space:]]*function[[:space:]]+([A-Za-z_][A-Za-z0-9_:.-]*).*/\1/p' -- "$1")"}; do
    unset -f "$name" 2>/dev/null
  done
  for name in ${(f)"$(sed -nE "s/^[[:space:]]*alias[[:space:]]+(-g[[:space:]]+)?([^=[:space:]]+)=.*/\2/p" -- "$1")"}; do
    unalias "$name" 2>/dev/null
  done
  msh::ok "unloaded: $1"
}

# listrc FILE — list aliases, functions and exported variables defined in a file
listrc() {
  [[ -f ${1-} ]] || { print -u2 "usage: listrc <file>"; return 2; }
  print -P "%B# Aliases:%b"
  sed -nE "s/^[[:space:]]*alias[[:space:]]+(-g[[:space:]]+)?([^=[:space:]]+)=.*/\2/p" -- "$1"
  print -P "\n%B# Functions:%b"
  sed -nE 's/^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*\(\).*/\2/p; s/^[[:space:]]*function[[:space:]]+([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*\{.*/\1/p' -- "$1"
  print -P "\n%B# Variables:%b"
  sed -nE 's/^[[:space:]]*(export|declare[[:space:]]+-x|typeset[[:space:]]+-g?x)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/$\2/p' -- "$1"
}
