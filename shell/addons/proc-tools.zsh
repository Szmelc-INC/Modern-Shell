#!/usr/bin/env zsh
# NAME: proc-tools
# DESC: Process toolbox: stray/strays/slay detached jobs, killem/pauseem/resumeem by regex, pswide/pspwd/psport, ps-c, timer
# TAGS: PROCESS, SYSTEM
# DEP: ps, pgrep, ss
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: stray firefox
# EXAMPLE: strays ; slay 2 ; slay all
# EXAMPLE: pauseem chromium ; resumeem chromium
# EXAMPLE: psport 8080
# EXAMPLE: timer make -j8
# | Merged from `stray.zsh` (= ZRC `stray`), `proc_tools.zsh`, the process part of
# | `greps.zsh`, ZRC `silent-nohup` and `command-timer`.
# |
# | | Command | What it does |
# | |---|---|
# | | `stray CMD...` | start CMD fully detached (no nohup.out) and remember it |
# | | `strays` | list remembered stray processes (dead ones are marked) |
# | | `slay [N\|PID\|all]` | kill the last / N-th / given / all strays |
# | | `nohups CMD...` | fire-and-forget detached command (not tracked) |
# | | `killem [REGEX]` | SIGKILL every process whose command line matches (asks first) |
# | | `pauseem [REGEX]` / `resumeem [REGEX]` | SIGSTOP / SIGCONT matching processes |
# | | `pswide` | every process, colored, full command line |
# | | `pspwd` | processes whose command line mentions the current directory |
# | | `psport PORT` | processes listening on PORT (TCP + UDP) |
# | | `ps-c PID` | the exact, shell-quoted command line of PID |
# | | `timer CMD...` | run CMD and print the wall time (ms precision) |
# |
# | `killem` now asks for confirmation (set `MSH_YES=1` to skip) and never
# | matches the calling shell.

typeset -ga STRAY_PIDS STRAY_CMDS

# stray CMD... — start a command detached in the background and remember its PID
stray() {
  (( $# )) || { print -u2 "usage: stray <command> [args]"; return 2; }
  nohup "$@" >/dev/null 2>&1 &!
  local pid=$!
  STRAY_PIDS+=($pid) STRAY_CMDS+=("$*")
  printf 'Started [%d] PID=%d: %s\n' $#STRAY_PIDS $pid "$*"
}

# strays — list remembered stray processes
strays() {
  (( $#STRAY_PIDS )) || { print "No stray processes tracked."; return 0; }
  local i state
  for i in {1..$#STRAY_PIDS}; do
    kill -0 $STRAY_PIDS[i] 2>/dev/null && state="" || state=" (dead)"
    printf '[%d] PID=%-7d %s%s\n' $i $STRAY_PIDS[i] "$STRAY_CMDS[i]" "$state"
  done
}

# slay [N|PID|all] — kill the last stray, stray number N, a raw PID, or all strays
slay() {
  local idx="" pid=""
  if [[ ${1-} == all ]]; then
    (( $#STRAY_PIDS )) || { print "No stray processes to kill."; return 0; }
    print "Killing all: ${STRAY_PIDS[*]}"
    kill -9 $STRAY_PIDS 2>/dev/null
    STRAY_PIDS=() STRAY_CMDS=()
    return 0
  elif [[ -z ${1-} ]]; then
    idx=$#STRAY_PIDS
  elif [[ $1 == <-> ]] && (( $1 <= $#STRAY_PIDS )); then
    idx=$1
  else
    pid=$1
  fi
  if [[ -z $pid ]]; then
    (( idx >= 1 && idx <= $#STRAY_PIDS )) || { msh::err "slay: invalid index: $idx"; return 1; }
    pid=$STRAY_PIDS[idx]
  fi
  kill -9 -- $pid 2>/dev/null || { msh::err "slay: failed to kill PID $pid"; return 1; }
  print "Killed PID=$pid"
  if [[ -n $idx ]]; then
    STRAY_PIDS[idx]=() STRAY_CMDS[idx]=()
  fi
}

# nohups CMD... — run a command detached with all output discarded
nohups() { nohup "$@" &>/dev/null &! }

# proc::match PROMPT REGEX... — print PIDs whose command line matches REGEX (internal)
proc::match() {
  local prompt=$1; shift
  local re="$*"
  [[ -n $re ]] || vared -p "$prompt" re
  [[ -n $re ]] || { msh::err "empty regex (aborted)"; return 1; }
  local -a pids
  pids=( ${(f)"$(pgrep -f -- "$re")"} )
  pids=( ${pids:#($$|$PPID)} )
  (( $#pids )) || { msh::err "no matches for: $re"; return 1; }
  print -r -- $pids
}

# killem [REGEX] — SIGKILL every process whose command line matches REGEX
killem() {
  local -a pids
  pids=( $(proc::match "Process regex to KILL: " "$@") ) || return 1
  ps -o pid=,args= -p ${(j:,:)pids}
  msh::confirm "Kill ${#pids} process(es)?" || return 1
  kill -9 -- $pids
}

# pauseem [REGEX] — freeze (SIGSTOP) every process whose command line matches REGEX
pauseem() {
  local -a pids
  pids=( $(proc::match "Process regex to PAUSE: " "$@") ) || return 1
  msh::info "freezing PIDs: $pids"
  kill -STOP -- $pids
}

# resumeem [REGEX] — wake up (SIGCONT) every process whose command line matches REGEX
resumeem() {
  local -a pids
  pids=( $(proc::match "Process regex to RESUME: " "$@") ) || return 1
  msh::info "unfreezing PIDs: $pids"
  kill -CONT -- $pids
}

# proc::fmt [MAXARGS] [FILTER] — colorize `ps -o pid=,tty=,user=,comm=,args=` from stdin (internal)
proc::fmt() {
  awk -v max="${1:-0}" -v wd="${2-}" '
    BEGIN { r="\033[31m"; o="\033[38;5;208m"; g="\033[32m"; p="\033[35m"; c="\033[36m"; z="\033[0m" }
    wd != "" && !index($0, wd) { next }
    {
      pid=$1; tty=$2; user=$3; comm=$4; args=""
      for (i = 5; i <= NF; i++) args = args $i (i < NF ? " " : "")
      if (comm == "awk" || comm == "ps") next
      if (max > 0 && length(args) > max) args = substr(args, 1, max - 3) "..."
      printf("  %s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s\n\n", r,pid,z, o,tty,z, g,user,z, p,comm,z, c,args,z)
    }'
}

# pswide — every process with its full command line, colored
pswide() { ps axww -o pid=,tty=,user=,comm=,args= | proc::fmt; }

# pspwd — processes whose command line mentions the current directory (args trimmed to 100)
pspwd() { ps axww -o pid=,tty=,user=,comm=,args= | proc::fmt 100 "$(pwd -P)"; }

# psport PORT — processes listening on PORT (TCP and UDP)
psport() {
  local port=${1:?usage: psport <port>}
  local -a pids
  pids=( ${(u)${(f)"$( { ss -H -ltnp "sport = :$port"; ss -H -lunp "sport = :$port"; } 2>/dev/null |
    grep -o 'pid=[0-9]*' | cut -d= -f2 )"}} )
  (( $#pids )) || { msh::info "nothing listens on :$port (or it belongs to another user)"; return 0; }
  ps -p ${(j:,:)pids} -o pid=,tty=,user=,comm=,args= | proc::fmt
}

# ps-c PID — print the exact, shell-quoted command line of a process
ps-c() {
  local pid=${1:?usage: ps-c <PID>}
  [[ -r /proc/$pid/cmdline ]] || { msh::err "no readable process with PID $pid"; return 1; }
  local -a argv=( ${(0)"$(< /proc/$pid/cmdline)"} )
  print -r -- ${(q-)argv}
}

# timer CMD... — run a command and print how long it took
timer() {
  zmodload -F zsh/datetime p:EPOCHREALTIME
  local start=$EPOCHREALTIME rc
  "$@"; rc=$?
  printf 'Time elapsed: %.3f s\n' $(( EPOCHREALTIME - start ))
  return rc
}
