#!/usr/bin/env zsh
# NAME: ytdlp
# DESC: One-word yt-dlp downloads: ytw (audio → wav/mp3), ytm (video); URL from args or the clipboard
# TAGS: MEDIA, WEB
# DEP: yt-dlp, ffmpeg (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: ytw https://youtu.be/XXXX
# EXAMPLE: ytw -f mp3 -r            (whole playlist, URL from clipboard)
# EXAMPLE: ytm -p ~/Videos/talks URL
# | Ported from `ytdlp.zsh`.
# |
# | | Flag | Meaning |
# | |---|---|
# | | `-r` | download the whole playlist (default: only the linked item) |
# | | `-p DIR` | output directory (default `$YTW_DIR` / `$YTM_DIR`) |
# | | `-f FMT` | audio format for `ytw` (default `$YTW_FORMAT`, wav) |
# | | `-u URL` | URL (or pass URLs as arguments; empty = clipboard) |
# | | `-b BROWSER` | take cookies from BROWSER (default `$YTDLP_BROWSER`; empty = none) |
# |
# | Tweakables: `YTW_DIR` (~/Music), `YTM_DIR` (~/Videos), `YTW_FORMAT` (wav),
# | `YTDLP_BROWSER` (firefox).
# | Fixed while porting: `getopts` without `local OPTIND` broke every second call;
# | unquoted URLs were word-split.

: ${YTW_DIR:=$HOME/Music}
: ${YTM_DIR:=$HOME/Videos}
: ${YTW_FORMAT:=wav}
: ${YTDLP_BROWSER=firefox}

# ytdl::run MODE ARGS... — shared option parser for ytw/ytm (internal)
ytdl::run() {
  emulate -L zsh
  msh::need yt-dlp || return
  local mode=$1; shift
  local OPTIND=1 OPTARG opt playlist=--no-playlist browser=$YTDLP_BROWSER fmt=$YTW_FORMAT
  local outdir; [[ $mode == audio ]] && outdir=$YTW_DIR || outdir=$YTM_DIR
  local -a urls
  while getopts "rp:u:f:b:h" opt; do
    case $opt in
      r) playlist=--yes-playlist ;;
      p) outdir=$OPTARG ;;
      u) urls+=("$OPTARG") ;;
      f) fmt=$OPTARG ;;
      b) browser=$OPTARG ;;
      h) print "usage: ${${mode:#audio}:+ytm}${${(M)mode:#audio}:+ytw} [-r] [-p DIR] [-f FMT] [-b BROWSER] [-u URL] [URL...]"; return 0 ;;
      *) return 2 ;;
    esac
  done
  shift $(( OPTIND - 1 ))
  urls+=("$@")
  if (( ! $#urls )); then
    local clip
    (( $+functions[paste] )) && clip=$(paste 2>/dev/null)
    [[ -n $clip ]] || { msh::err "no URL given and the clipboard is empty"; return 1; }
    urls=("$clip")
  fi
  local -a cmd=(yt-dlp -i $playlist -o "$outdir/%(title)s.%(ext)s")
  [[ -n $browser ]] && cmd+=(--cookies-from-browser "$browser")
  [[ $mode == audio ]] && cmd+=(-x --audio-format "$fmt")
  "${cmd[@]}" -- "${urls[@]}"
}

# ytw [-r] [-p DIR] [-f FMT] [URL...] — download audio (default wav) with yt-dlp
ytw() { ytdl::run audio "$@"; }

# ytm [-r] [-p DIR] [URL...] — download video with yt-dlp
ytm() { ytdl::run video "$@"; }
