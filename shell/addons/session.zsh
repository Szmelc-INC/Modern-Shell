#!/usr/bin/env zsh
# NAME: session
# DESC: Desktop session snapshots (Hyprland + UWSM): save, restore and switch every window, app and unsaved buffer
# TAGS: SYSTEM, PROCESS
# DEP: msh-session, python3, hyprctl, uwsm (optional), grim (optional), qdbus6 (optional), fzf (optional)
# DEFAULT: on
# VER: 1.0
# DEV: SilverX
# EXAMPLE: sess save work -m "coding setup"
# EXAMPLE: sess switch music
# EXAMPLE: sess restore #1 --dry-run
# EXAMPLE: sess-list
# | Front-end for **`msh-session`**, which snapshots the whole graphical session:
# |
# | - every window: class, title, workspace (special ones too), monitor, exact
# |   position/size, floating / pinned / fullscreen state, focus
# | - the program behind it: command line, working directory, open files,
# |   the UWSM unit, and the best command to start it again
# | - app state: Kate documents, browser tabs (Chromium family), terminal tabs
# |   with their directories and foreground commands, mpv playlists, OBS
# |   profile/collection/scene, file-manager folders
# | - **unsaved data**: Kate's stash of never-saved and modified documents is
# |   flushed over D-Bus and restored *as unsaved documents*; text of
# |   accessible (GTK, Qt with a11y on) editors and kitty scrollback is saved
# |   to `<snapshot>/unsaved/`
# | - session state: active workspaces, keyboard layout, wallpaper, volume,
# |   environment (allowlist only), screenshots, a copy of `~/.config/hypr`
# |
# | | Command | What it does |
# | |---|---|
# | | `sess save [name] [-m note]` | snapshot the running session |
# | | `sess restore [name]` | reuse open windows, launch the missing ones, put all back in place |
# | | `sess switch [name]` | same, and close windows that are not in the snapshot (auto-backup first) |
# | | `sess list` / `show` / `diff` / `status` | inspect snapshots and the live session |
# | | `sess rm` / `prune` / `rename` / `export` / `import` | manage snapshots |
# | | `sess doctor` | what can be captured here and how to enable the rest |
# |
# | Snapshots live in `~/.local/share/msh/sessions/<name>/` (mode 700).
# | Settings: `msh-session config init` → `$MSH_USER/session.toml`.
# | Bind it in Hyprland, e.g. `bind = SUPER ALT, S, exec, msh-session save quick -f -y`.

# sess [command] [args] — msh-session front-end; no arguments lists snapshots
sess() {
  msh::need msh-session || return
  if (( $# )); then msh-session "$@"; else msh-session list; fi
}

# Snapshot the current desktop session (name optional)
alias sess-save='msh-session save'
# Restore a session snapshot (picker when no name)
alias sess-load='msh-session restore'
# Switch to another session snapshot (closes windows not in it)
alias sess-switch='msh-session switch'
# List session snapshots, newest first
alias sess-list='msh-session list'
# Show windows, apps and unsaved data in a snapshot
alias sess-show='msh-session show'

if (( $+functions[compdef] )); then compdef sess=msh-session; fi
