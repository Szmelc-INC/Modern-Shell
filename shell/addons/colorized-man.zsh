#!/usr/bin/env zsh
# NAME: colorized-man
# DESC: Colored man pages (LESS_TERMCAP) and optional bat-powered MANPAGER
# TAGS: EYECANDY, CORE
# DEP: less, bat (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: man ls
# EXAMPLE: MSH_MAN_BAT=1   (in msh.conf: render man pages through bat)
# | Merged from ZRC `colorized-man` and the `.zshrc` "Man Syntax Highlight" block.
# |
# | - Headings magenta, emphasis/underline green, search hits yellow on blue.
# | - `GROFF_NO_SGR=1` is exported so newer groff emits the classic overstrike
# |   sequences that `LESS_TERMCAP_*` can recolor.
# | - Set `MSH_MAN_BAT=1` (e.g. in `user/msh.conf`) to use **bat** as `MANPAGER`
# |   instead (syntax-highlighted man pages). Ignored when bat is not installed
# |   or when you already set `MANPAGER` yourself.
# |
# | | Command / setting | What it does |
# | |---|---|
# | | `man CMD` | man page with the LESS_TERMCAP colors |
# | | `manc CMD` | one-off bat-highlighted man page |
# | | `MSH_MAN_BAT=1` | make bat the default `MANPAGER` |

export LESS_TERMCAP_mb=$'\e[1;31m'      # blink      → bold red
export LESS_TERMCAP_md=$'\e[1;35m'      # bold       → bold magenta
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'   # standout   → yellow on blue
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'      # underline  → bold green
export LESS_TERMCAP_ue=$'\e[0m'
export GROFF_NO_SGR=1

# bat binary name differs per distro (bat / batcat)
typeset -g MSH_BAT_CMD=${${commands[bat]:+bat}:-${commands[batcat]:+batcat}}

if [[ ${MSH_MAN_BAT-} == 1 && -n $MSH_BAT_CMD && -z ${MANPAGER-} ]]; then
  export MANPAGER="sh -c 'col -bx | $MSH_BAT_CMD -l man -p'"
  export MANROFFOPT='-c'
fi

# manc CMD — show a man page highlighted by bat (one-off, regardless of MSH_MAN_BAT)
manc() {
  [[ -n $MSH_BAT_CMD ]] || { msh::err "manc: bat is not installed"; return 127; }
  MANPAGER="sh -c 'col -bx | $MSH_BAT_CMD -l man -p'" MANROFFOPT='-c' man "$@"
}
