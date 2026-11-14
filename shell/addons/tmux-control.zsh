#!/usr/bin/env zsh
# NAME: tmux-control
# DESC: Drive tmux panes from the prompt: tx-send, tx-run, tx-stop, tx-split, tx-close, tx-res, tx-focus (target one pane or ALL others)
# TAGS: TMUX, PROCESS
# DEP: tmux
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: tx-send ALL "git pull"
# EXAMPLE: tx-stop 2
# EXAMPLE: tx-split ALL v 30
# EXAMPLE: tx-run 1 ./deploy.sh
# | Ported from `~/.tmuxrc`. Every name now has a `tx-` prefix: the originals
# | (`send`, `stop`, `run`, `close`, `split`, `pause`, `res`, `focus`) clobbered
# | common words.
# |
# | **TARGET** is a pane index (`#P`, see `tx-ls`), any tmux target (`%3`,
# | `win:1.2`) or `ALL` = every pane of the current window except the active one.
# |
# | | Command | What it does |
# | |---|---|
# | | `tx-ls` | list panes of the current window |
# | | `tx-send TARGET CMD...` | type CMD + Enter in TARGET |
# | | `tx-run TARGET SCRIPT` | paste a local script file into TARGET and run it |
# | | `tx-stop TARGET` | send Ctrl-C |
# | | `tx-suspend TARGET` | send Ctrl-Z |
# | | `tx-pause TARGET` / `tx-unpause TARGET` | send Ctrl-S / Ctrl-Q (flow control) |
# | | `tx-focus TARGET` | select pane |
# | | `tx-split TARGET h\|v [PERCENT]` | split (h = side by side, v = stacked), default 50 % |
# | | `tx-close TARGET` | kill pane(s) |
# | | `tx-res up\|down\|left\|right [CELLS] [TARGET]` | resize (default: current pane, 1 cell) |
# |
# | Removed: the nc-based `download`/`upload` (they never worked: `pane_tty`
# | is a device path, not a host). Fixed: `[ "$1" == ALL ]` (not POSIX),
# | `split-window -p` (deprecated → `-l N%`), `send` only sent its 2nd argument.

# tx::targets TARGET — expand TARGET (ALL = every other pane in the window) (internal)
tx::targets() {
  if [[ $1 == ALL ]]; then
    tmux list-panes -F '#{pane_active} #{pane_id}' | awk '$1 == 0 {print $2}'
  else
    print -r -- "$1"
  fi
}

# tx::need — fail unless running inside tmux (internal)
tx::need() {
  [[ -n ${TMUX-} ]] || { msh::err "not inside tmux"; return 1; }
}

# tx::keys TARGET KEY... — send raw keys to TARGET (internal)
tx::keys() {
  tx::need || return
  local p t=$1; shift
  [[ -n $t ]] || { print -u2 "usage: <target|ALL>"; return 2; }
  for p in ${(f)"$(tx::targets $t)"}; do tmux send-keys -t "$p" "$@"; done
}

# tx-ls — list the panes of the current window
tx-ls() {
  tx::need || return
  tmux list-panes -F '#P  #{pane_id}  #{pane_width}x#{pane_height}  #{pane_current_command}  #{?pane_active,(active),}'
}

# tx-send TARGET CMD... — type a command plus Enter into pane(s)
tx-send() {
  (( $# >= 2 )) || { print -u2 "usage: tx-send <target|ALL> <command...>"; return 2; }
  local t=$1; shift
  tx::keys $t -l -- "$*" && tx::keys $t Enter
}

# tx-run TARGET SCRIPT — paste a local script into pane(s) and run it
tx-run() {
  tx::need || return
  [[ -n ${1-} && -r ${2-} ]] || { print -u2 "usage: tx-run <target|ALL> <script-file>"; return 2; }
  local p
  tmux load-buffer -b msh-tx-run -- "$2" || return
  for p in ${(f)"$(tx::targets $1)"}; do
    tmux paste-buffer -b msh-tx-run -t "$p" && tmux send-keys -t "$p" Enter
  done
  tmux delete-buffer -b msh-tx-run
}

# tx-stop TARGET — send Ctrl-C to pane(s)
tx-stop() { tx::keys "${1-}" C-c; }

# tx-suspend TARGET — send Ctrl-Z to pane(s)
tx-suspend() { tx::keys "${1-}" C-z; }

# tx-pause TARGET — send Ctrl-S (stop output) to pane(s)
tx-pause() { tx::keys "${1-}" C-s; }

# tx-unpause TARGET — send Ctrl-Q (resume output) to pane(s)
tx-unpause() { tx::keys "${1-}" C-q; }

# tx-focus TARGET — select a pane
tx-focus() {
  tx::need || return
  tmux select-pane -t "${1:?usage: tx-focus <target>}"
}

# tx-split TARGET h|v [PERCENT] — split pane(s) side by side (h) or stacked (v)
tx-split() {
  tx::need || return
  local t=${1-} dir=${2-} pct=${3:-50} p
  [[ -n $t && $dir == (h|v) && $pct == <1-99> ]] || { print -u2 "usage: tx-split <target|ALL> h|v [percent]"; return 2; }
  for p in ${(f)"$(tx::targets $t)"}; do tmux split-window -$dir -l "$pct%" -t "$p"; done
}

# tx-close TARGET — kill pane(s)
tx-close() {
  tx::need || return
  [[ -n ${1-} ]] || { print -u2 "usage: tx-close <target|ALL>"; return 2; }
  local p
  for p in ${(f)"$(tx::targets $1)"}; do tmux kill-pane -t "$p"; done
}

# tx-res up|down|left|right [CELLS] [TARGET] — resize the current pane or TARGET (ALL = others)
tx-res() {
  tx::need || return
  local flag
  case ${1-} in
    up) flag=-U ;; down) flag=-D ;; left) flag=-L ;; right) flag=-R ;;
    *) print -u2 "usage: tx-res up|down|left|right [cells] [target|ALL]"; return 2 ;;
  esac
  local size=${2:-1} t=${3-} p
  if [[ -z $t ]]; then
    tmux resize-pane $flag $size
  else
    for p in ${(f)"$(tx::targets $t)"}; do tmux resize-pane -t "$p" $flag $size; done
  fi
}
