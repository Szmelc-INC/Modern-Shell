#!/usr/bin/env zsh
# NAME: eyecandy
# DESC: Terminal eye candy: big ASCII clock, figlet/toilet font browser, typewriter cat, bonsai, lolcat/boxes shortcuts, Midnight palette
# TAGS: EYECANDY, FUN
# DEP: figlet (optional), toilet (optional), cbonsai (optional), lolcat (optional), boxes (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: clock -s
# EXAMPLE: clock -t -f future
# EXAMPLE: ascii-fonts -e "Hello" -s 0.02
# EXAMPLE: typecat README.md
# EXAMPLE: ls | RGB1
# | Merged from ZRC `cli-clock`, `ascii-fonts`, the `.zshrc` `clock`, `typecat`,
# | `RGB1`/`BOX1` aliases, MIDNIGHT_* palette and `drzewko.zsh`.
# |
# | | Command | What it does |
# | |---|---|
# | | `clock [-s] [-t] [figlet args]` | centered big clock; `-s` seconds, `-t` toilet; Ctrl-C quits |
# | | `ascii-fonts [-t] [-e TEXT] [-s SEC]` | render TEXT in every installed figlet (or toilet) font |
# | | `typecat FILE...` | print files like a typewriter (`TYPECAT_DELAY`, default 0.022 s) |
# | | `drzewko` | animated bonsai tree (cbonsai, infinite) |
# | | `RGB1` | rainbow-colorize stdin (lolcat) |
# | | `BOX1` | draw an info box around stdin (boxes) |
# |
# | **Midnight palette** — exported as `MIDNIGHT_BG`, `MIDNIGHT_FG`, `MIDNIGHT_ACCENT`, …
# | for scripts and themes; set any of them earlier to override. `midnight` prints swatches.
# |
# | Fixed while porting: `clock` used to leave the cursor hidden after Ctrl-C and
# | leaked its variables into the shell.

: ${TYPECAT_DELAY:=0.022}

# Midnight color palette (override any value before this addon loads)
: ${MIDNIGHT_BG:='#1e1e2e'} ${MIDNIGHT_BG_ALT:='#232339'} ${MIDNIGHT_FG:='#ffffff'}
: ${MIDNIGHT_ACCENT:='#7aa2f7'} ${MIDNIGHT_ACCENT_ALT:='#b4befe'} ${MIDNIGHT_BORDER:='#313244'}
: ${MIDNIGHT_GRAY:='#6c7086'} ${MIDNIGHT_ALERT:='#f38ba8'} ${MIDNIGHT_SUCCESS:='#a6e3a1'}
: ${MIDNIGHT_WARNING:='#f9e2af'} ${MIDNIGHT_CURSOR:='#f5e0dc'}
export MIDNIGHT_BG MIDNIGHT_BG_ALT MIDNIGHT_FG MIDNIGHT_ACCENT MIDNIGHT_ACCENT_ALT MIDNIGHT_BORDER \
  MIDNIGHT_GRAY MIDNIGHT_ALERT MIDNIGHT_SUCCESS MIDNIGHT_WARNING MIDNIGHT_CURSOR

# midnight — print the Midnight palette as true-color swatches
midnight() {
  local v hex
  for v in ${(o)${(M)${(k)parameters}:#MIDNIGHT_*}}; do
    hex=${${(P)v}#\#}
    printf '\e[48;2;%d;%d;%dm      \e[0m  %-22s %s\n' 0x${hex[1,2]} 0x${hex[3,4]} 0x${hex[5,6]} "$v" "${(P)v}"
  done
}

# clock [-s] [-t] [figlet/toilet args] — full-screen centered ASCII clock (Ctrl-C to quit)
clock() {
  emulate -L zsh
  local cmd=figlet fmt="%H:%M"
  local -a args
  while (( $# )); do
    case $1 in
      -t|--toilet)  cmd=toilet ;;
      -s|--seconds) fmt="%H:%M:%S" ;;
      -h|--help) print "usage: clock [-s|--seconds] [-t|--toilet] [figlet/toilet args, e.g. -f big]"; return 0 ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  msh::need $cmd || return
  local out line rows cols pad_top pad_left i
  {
    tput civis
    while true; do
      out=$(date +"$fmt" | $cmd "${args[@]}")
      rows=${#${(f)out}}
      cols=${#${${(f)out}[1]}}
      pad_top=$(( (LINES - rows) / 2 )) pad_left=$(( (COLUMNS - cols) / 2 ))
      (( pad_top < 0 )) && pad_top=0
      (( pad_left < 0 )) && pad_left=0
      clear
      for (( i = 0; i < pad_top; i++ )); do print; done
      for line in "${(@f)out}"; do printf '%*s%s\n' $pad_left '' "$line"; done
      sleep 1
    done
  } always {
    tput cnorm
  }
}

# ascii-fonts [-t] [-e TEXT] [-s SEC] — preview TEXT in every installed figlet/toilet font
ascii-fonts() {
  emulate -L zsh
  setopt null_glob
  local tool=figlet ex=flf text=example speed=0
  local -a dirs=(/usr/share/figlet /usr/share/figlet/fonts $HOME/.local/share/figlet $HOME/.figlet)
  while (( $# )); do
    case $1 in
      -t|--toilet)  tool=toilet ex=tlf; shift ;;
      -e|--example) [[ -n ${2-} ]] || { msh::err "missing text for -e"; return 2; }; text=$2; shift 2 ;;
      -s|--speed)   [[ -n ${2-} ]] || { msh::err "missing value for -s"; return 2; }; speed=$2; shift 2 ;;
      -h|--help) print "usage: ascii-fonts [-t|--toilet] [-e TEXT] [-s SECONDS_PER_LINE]"; return 0 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  msh::need $tool || return
  local found=0 out font dir f line
  for dir in $dirs; do
    [[ -d $dir ]] || continue
    for f in $dir/*.$ex; do
      font=${${f:t}%.$ex}
      out=$($tool -f "$font" -- "$text" 2>/dev/null) || continue
      print -- "---------------------------"
      if (( speed > 0 )); then
        for line in "${(@f)out}"; do print -r -- "$line"; sleep $speed; done
      else
        print -r -- "$out"
      fi
      print -r -- "$font"; print
      found=1
    done
  done
  (( found )) || msh::warn "No fonts found. Blame Bill Gates."
}

# Old name of ascii-fonts
alias ascii_fonts='ascii-fonts'

# typecat FILE... — print files character by character like a typewriter
typecat() {
  emulate -L zsh
  local line i f
  (( $# )) || set -- /dev/stdin
  for f in "$@"; do
    while IFS= read -r line || [[ -n $line ]]; do
      for (( i = 1; i <= $#line; i++ )); do
        printf '%s' "${line[i]}"
        sleep $TYPECAT_DELAY
      done
      printf '\n'
    done < "$f"
  done
}

# drzewko — animated, infinitely growing bonsai tree (cbonsai)
alias drzewko='cbonsai -il -t 0.1 -w 1'
# Rainbow-colorize stdin (lolcat)
alias RGB1='lolcat -F 0.0069 -S -s 256 -a'
# Draw an info box around stdin (boxes)
alias BOX1='boxes -d info'
