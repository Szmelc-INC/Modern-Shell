#!/usr/bin/env zsh
# NAME: clipboard
# DESC: copy / paste / copyf that work everywhere: Wayland (wl-clipboard), X11 (xclip/xsel), SSH (OSC 52)
# TAGS: CLIPBOARD, CORE
# DEP: wl-copy (optional), wl-paste (optional), xclip (optional), xsel (optional), base64
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: echo hello | copy
# EXAMPLE: copy "some text"
# EXAMPLE: copyf ~/.ssh/id_ed25519.pub
# EXAMPLE: vim "$(paste)"
# | Merged from ZRC `copy-paste`, `copy-file-contents` and the `.zshrc` copy/paste.
# |
# | Backend order: **wl-copy** (when `WAYLAND_DISPLAY` is set) → **xclip** →
# | **xsel** (when `DISPLAY` is set) → **OSC 52** escape (works over SSH and in
# | most modern terminals; copy only).
# |
# | | Command | What it does |
# | |---|---|
# | | `copy` | copy stdin |
# | | `copy TEXT...` | copy the arguments as text |
# | | `copyf FILE` | copy the contents of FILE |
# | | `paste` | print the clipboard |
# | | `copy-path [FILE]` | copy the absolute path of FILE (default: `$PWD`) |
# | | `clipboard-backend` | show which backend is used |
# |
# | **Note:** the old `.zshrc` `copy FILE` copied the *file contents*; that is
# | now `copyf FILE`. `copy` always copies text.
# |
# | `paste` shadows coreutils `paste` only when called with **no arguments and
# | a terminal on stdin**. `paste a.txt b.txt` or `… | paste -sd,` still run
# | the real coreutils `paste`.

# clipboard-backend — print the backend copy/paste will use (wayland, xclip, xsel, osc52)
clipboard-backend() {
  if [[ -n ${WAYLAND_DISPLAY-} ]] && (( $+commands[wl-copy] )); then print wayland
  elif [[ -n ${DISPLAY-} ]] && (( $+commands[xclip] )); then print xclip
  elif [[ -n ${DISPLAY-} ]] && (( $+commands[xsel] )); then print xsel
  else print osc52
  fi
}

# copy [TEXT...] — copy arguments (or stdin) to the system clipboard
copy() {
  if (( $# )); then
    print -rn -- "$*" | copy
    return
  fi
  case $(clipboard-backend) in
    wayland) wl-copy ;;
    xclip)   xclip -selection clipboard ;;
    xsel)    xsel --clipboard --input ;;
    osc52)
      local data
      data=$(base64 | tr -d '\n')
      if [[ -n ${TMUX-} ]]; then
        printf '\ePtmux;\e\e]52;c;%s\a\e\\' "$data" > /dev/tty
      else
        printf '\e]52;c;%s\a' "$data" > /dev/tty
      fi ;;
  esac
}

# copyf FILE — copy the contents of a file to the clipboard
copyf() {
  if (( $# != 1 )); then
    print -u2 "usage: copyf <file>"; return 2
  fi
  [[ -f $1 && -r $1 ]] || { msh::err "copyf: cannot read '$1'"; return 1; }
  copy < "$1" && msh::ok "copied ${1:t} ($(wc -c < "$1") bytes)"
}

# copy-path [FILE] — copy the absolute path of FILE (default: current directory)
copy-path() {
  local p=${1:-$PWD}
  print -rn -- "${p:A}" | copy && msh::ok "copied ${p:A}"
}

# paste — print the clipboard (with arguments or piped stdin it runs coreutils paste)
paste() {
  if (( $# )) || [[ ! -t 0 ]]; then
    command paste "$@"; return
  fi
  case $(clipboard-backend) in
    wayland) wl-paste --no-newline ;;
    xclip)   xclip -selection clipboard -o ;;
    xsel)    xsel --clipboard --output ;;
    *) msh::err "paste: no clipboard reader (install wl-clipboard or xclip)"; return 1 ;;
  esac
}
