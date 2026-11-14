#!/usr/bin/env zsh
# NAME: cookies
# DESC: Export a browser's cookies to a Netscape cookies.txt (via yt-dlp) for curl, wget and yt-dlp
# TAGS: WEB, SECURITY
# DEP: yt-dlp
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: cookies -b firefox
# EXAMPLE: cookies -b brave -o ~/.config/cookies.txt
# EXAMPLE: curl -b "$(cookies -b chrome -q)" https://example.com
# | Ported from `cookies.zsh`.
# |
# | | Flag | Meaning |
# | |---|---|
# | | `-b BROWSER` | firefox, chrome, chromium, brave, edge, opera, vivaldi, safari (default firefox) |
# | | `-o PATH` | output file; a directory gets `cookies.txt` appended (default `$COOKIES_DIR/cookies.txt`) |
# | | `-u URL` | URL handed to yt-dlp as a pretext (default: a harmless video page) |
# | | `-q` | quiet: print only the output path |
# |
# | **These are live session cookies — treat the file like a password.**
# | The file is created with mode 600 in `$COOKIES_DIR`
# | (default `${XDG_RUNTIME_DIR:-~/.cache}/msh-cookies`, mode 700), never in a
# | world-readable `/tmp`. Delete it when done: `rm "$COOKIES_DIR/cookies.txt"`.

: ${COOKIES_DIR:=${XDG_RUNTIME_DIR:-$HOME/.cache}/msh-cookies}

# cookies [-b BROWSER] [-o PATH] [-u URL] [-q] — dump browser cookies to a private cookies.txt
cookies() {
  emulate -L zsh
  local browser=firefox out="$COOKIES_DIR/cookies.txt" url="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  local quiet=0 opt OPTIND=1
  while getopts "b:o:u:qh" opt; do
    case $opt in
      b) browser=$OPTARG ;;
      o) out=$OPTARG ;;
      u) url=$OPTARG ;;
      q) quiet=1 ;;
      h) print "usage: cookies [-b browser] [-o path] [-u url] [-q]"; return 0 ;;
      *) return 2 ;;
    esac
  done
  msh::need yt-dlp || return
  [[ -d $out || $out == */ ]] && out="${out%/}/cookies.txt"
  (( quiet )) || msh::info "extracting cookies from $browser → $out"
  # Subshell so the private umask does not leak into the interactive shell.
  # yt-dlp may exit non-zero on the pretext URL but still writes the jar: check the file instead.
  (
    umask 077
    command mkdir -p -- "${out:h}" || exit 1
    yt-dlp --cookies-from-browser "$browser" --cookies "$out" --skip-download \
      --quiet --no-warnings -- "$url" 2>/dev/null
  )
  if [[ -s $out ]]; then
    chmod 600 -- "$out"
    if (( quiet )); then print -r -- "$out"
    else msh::ok "saved $(command grep -vc '^#' -- "$out") cookies to $out"
    fi
  else
    msh::err "cookies: extraction failed (is $browser closed / profile readable?)"
    return 1
  fi
}
