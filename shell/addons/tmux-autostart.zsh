#!/usr/bin/env zsh
# NAME: tmux-autostart
# DESC: Start every interactive terminal inside its own new tmux session (replaces the shell)
# TAGS: TMUX
# DEP: tmux
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: msh addon on tmux-autostart
# EXAMPLE: NO_TMUX=1 kitty      (skip tmux for one terminal)
# | Ported from `~/.zsh/tmux.zsh`.
# |
# | **Exception to the no-side-effects rule:** this addon acts *on source* by
# | design. When the shell is interactive, attached to a terminal, not already in
# | tmux, not inside an editor/IDE terminal and `NO_TMUX` is unset, it replaces the
# | shell with `tmux new-session` (or `tmux new-session -A -s $TMUX_AUTOSTART_SESSION`
# | when that variable is set, to re-attach one shared session).
# |
# | Non-interactive shells, scripts, `zsh -c`, SSH without a TTY, VS Code /
# | JetBrains terminals and nested tmux are left alone.
# |
# | | Variable | Effect |
# | |---|---|
# | | `NO_TMUX=1` | skip tmux for this terminal (escape hatch) |
# | | `TMUX_AUTOSTART_SESSION=NAME` | attach/create one shared session instead of a new one per window |

# tmux-autostart::run — exec tmux when this is a plain interactive terminal shell
tmux-autostart::run() {
  [[ -o interactive && -t 0 && -t 1 ]] || return 0
  [[ -z ${TMUX-} && -z ${NO_TMUX-} ]] || return 0
  [[ ${TERM_PROGRAM-} == (vscode|WarpTerminal) || -n ${INSIDE_EMACS-} || -n ${NVIM-} ]] && return 0
  (( $+commands[tmux] )) || return 0
  # `builtin exec` on purpose: replaces the shell so closing tmux closes the terminal.
  if [[ -n ${TMUX_AUTOSTART_SESSION-} ]]; then
    builtin exec tmux new-session -A -s "$TMUX_AUTOSTART_SESSION"
  else
    builtin exec tmux new-session
  fi
}

tmux-autostart::run
