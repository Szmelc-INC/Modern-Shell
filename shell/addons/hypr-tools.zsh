#!/usr/bin/env zsh
# NAME: hypr-tools
# DESC: Hyprland/Wayland desktop fixes: restart xdg-desktop-portal, restart waybar, Apple keyboard F-keys mode, jspaint
# TAGS: SYSTEM
# DEP: hyprctl (optional), waybar (optional), pkexec, webui (optional)
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: fix-xdg-portal
# EXAMPLE: rbar
# EXAMPLE: fnmode 2
# | Merged from `fix-xdg-portal.zsh`, `keyboard.zsh` and the `.zshrc` `rbar` /
# | `paint` aliases. The originals ran **on source** (killing portals and calling
# | a privileged `tee` every time a shell opened); now they are plain commands.
# |
# | | Command | What it does |
# | |---|---|
# | | `fix-xdg-portal` | kill crashed xdg-desktop-portal(-hyprland/-wlr) and start them again |
# | | `rbar` | restart waybar, detached |
# | | `fnmode [0\|1\|2]` | Apple (hid_apple) keyboards: 2 = F1–F12 by default, 1 = media keys; no arg shows the current mode (pkexec) |
# | | `paint` | open jspaint.app in a webui window |
# |
# | Tweakable: `XDG_PORTAL_LIBEXEC` (default `/usr/lib`), where the portal binaries live.

: ${XDG_PORTAL_LIBEXEC:=/usr/lib}

# fix-xdg-portal — restart crashed xdg-desktop-portal processes (Hyprland session)
fix-xdg-portal() {
  local p
  pkill -x xdg-desktop-portal-hyprland; pkill -x xdg-desktop-portal-wlr; pkill -x xdg-desktop-portal
  sleep 1
  export XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-Hyprland}
  export XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-wayland}
  export XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-Hyprland}
  for p in xdg-desktop-portal xdg-desktop-portal-hyprland; do
    if [[ -x $XDG_PORTAL_LIBEXEC/$p ]]; then
      nohup "$XDG_PORTAL_LIBEXEC/$p" &>/dev/null &!
      sleep 1
    else
      msh::warn "not found: $XDG_PORTAL_LIBEXEC/$p"
    fi
  done
  msh::ok "portals restarted"
}

# rbar — restart waybar (detached)
rbar() {
  msh::need waybar || return
  pkill -x waybar; sleep 0.3
  nohup waybar &>/dev/null &!
}

# fnmode [0|1|2] — show or set the hid_apple fnmode (2 = F-keys first), via pkexec
fnmode() {
  local f=/sys/module/hid_apple/parameters/fnmode
  [[ -e $f ]] || { msh::err "hid_apple module is not loaded"; return 1; }
  if [[ -z ${1-} ]]; then print -r -- "fnmode: $(<$f)"; return; fi
  [[ $1 == [012] ]] || { print -u2 "usage: fnmode [0|1|2]"; return 2; }
  print -r -- "$1" | pkexec tee "$f" >/dev/null && msh::ok "fnmode = $1"
}

# paint — open jspaint.app in a detached webui window
paint() {
  msh::need webui || return
  nohup webui -u https://jspaint.app &>/dev/null </dev/null &!
}
