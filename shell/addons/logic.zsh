#!/usr/bin/env zsh
# NAME: logic
# DESC: Shell logic helpers: rng (pick a random arg), rngnum (random number), each/eachfile loops, Ctrl-J ${*} loop expansion
# TAGS: DEV, FILES
# DEP: zsh
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: rm -- "$(rng *.gif)"
# EXAMPLE: rngnum 1 100
# EXAMPLE: each 'mv -- {} {}.bak' *.txt
# EXAMPLE: rm ${*}.tmp      then press Ctrl-J
# | Merged from `logic.zsh` and the `.zshrc` `rng` / `eachfile`.
# |
# | | Command | What it does |
# | |---|---|
# | | `rng ARGS...` | print one random argument (`rng $(<list.txt)` = random line) |
# | | `rngnum [LO] [HI]` | random integer in [LO, HI] (default 4000000–4226019), also stored in `$RNG` |
# | | `each CMD ARGS...` | run `CMD arg` once per argument |
# | | `each 'TEMPLATE {}' ARGS...` | when CMD contains `{}`, it is evaluated with `{}` → the quoted argument |
# | | `eachfile CMD [ARGS...]` | run `CMD file ARGS...` for every regular file in `.` |
# | | **Ctrl-J** | when the line contains `${*}`, turn it into `for f in *…; do … "$f" …; done` and run it |
# |
# | Example for Ctrl-J: typing `mv -- ${*}.gif old/` + Ctrl-J runs
# | `for f in *.gif; do mv -- "$f" old/; done`. Without `${*}` Ctrl-J is a normal Enter.
# |
# | Fixed while porting: `.zshrc` defined a second `rng` (random number) that
# | silently replaced this one — it is now `rngnum`.

# rng ARGS... — print one randomly chosen argument
rng() {
  (( $# )) || return 1
  print -r -- "${@[RANDOM % $# + 1]}"
}

# rngnum [LO] [HI] — print a random integer in [LO, HI] and store it in $RNG
rngnum() {
  local lo=${1:-4000000} hi=${2:-4226019} t
  (( lo > hi )) && { t=$lo; lo=$hi; hi=$t; }
  # 30 random bits from two $RANDOM draws
  typeset -g RNG=$(( lo + (((RANDOM << 15) | RANDOM) % (hi - lo + 1)) ))
  print -r -- $RNG
}

# Old name: random number into $RNG (prints it too)
alias RNG='rngnum'

# each CMD ARGS... — run CMD once per argument ({} in CMD = placeholder for the argument)
each() {
  (( $# >= 2 )) || { print -u2 "usage: each <cmd|'template {}'> <args...>"; return 2; }
  local cmd=$1 a rc=0; shift
  for a in "$@"; do
    if [[ $cmd == *'{}'* ]]; then
      eval "${cmd//\{\}/${(q)a}}" || rc=1
    else
      ${(z)cmd} "$a" || rc=1
    fi
  done
  return rc
}

# eachfile CMD [ARGS...] — run `CMD file ARGS...` for every regular file in the current dir
eachfile() {
  (( $# )) || { print -u2 "usage: eachfile <cmd> [args...]"; return 2; }
  local cmd=$1 f; shift
  for f in *(N.); do
    ${(z)cmd} "$f" "$@"
  done
}

# logic::iter_star_accept_line — Ctrl-J widget: expand ${*} into a for-loop, else accept the line
logic::iter_star_accept_line() {
  emulate -L zsh
  if [[ $BUFFER != *'${*}'* ]]; then
    zle .accept-line; return
  fi
  local -a words=( ${(z)BUFFER} )
  local i glob=""
  for (( i = 1; i <= $#words; i++ )); do
    if [[ $words[i] == *'${*}'* ]]; then
      glob=${words[i]//'${*}'/*}
      words[i]='"$f"'
      break
    fi
  done
  BUFFER="for f in ${glob}; do ${(j: :)words}; done"
  zle .accept-line
}

if [[ -o interactive ]]; then
  zle -N logic::iter_star_accept_line
  bindkey '^J' logic::iter_star_accept_line
fi
