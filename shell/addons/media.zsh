#!/usr/bin/env zsh
# NAME: media
# DESC: Media helpers: unwebp, makeclip (audio + image/video → mp4), screenshotd (delayed area shot), tidy-media
# TAGS: MEDIA, FILES
# DEP: ffmpeg (optional), grim (optional), slurp (optional), wl-copy (optional), notify-send (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: unwebp
# EXAMPLE: makeclip song.wav cover.png out.mp4
# EXAMPLE: screenshotd 3
# EXAMPLE: tidy-media -n
# | Merged from ZRC `unwebp`, `tidy-media`, the `.zshrc` `unwebp` and `makeclip`,
# | and `screenshot.zsh`.
# |
# | | Command | What it does |
# | |---|---|
# | | `unwebp [-k] [FILE...]` | convert WebP → PNG (all `*.webp` here by default); `-k` keeps the originals |
# | | `makeclip [AUDIO IMAGE\|VIDEO OUT]` | YouTube-safe H.264/AAC mp4 from audio + still/gif/video (prompts when no args) |
# | | `screenshotd [DELAY]` | pick an area, wait DELAY s (default 5), save to `$SCREENSHOT_FILE` + clipboard (Wayland) |
# | | `tidy-media [-n]` | move pictures/videos/audio/documents from `.` into `$MEDIA_DIR/<Kind>/`, never overwriting; `-n` = dry run |
# |
# | Tweakables: `MEDIA_DIR` (default `~/Media`), `SCREENSHOT_FILE` (default `/tmp/scr.png`).
# | `tidy` was renamed to `tidy-media` so it no longer hides HTML Tidy.

: ${MEDIA_DIR:=$HOME/Media}
: ${SCREENSHOT_FILE:=${TMPDIR:-/tmp}/scr.png}

# unwebp [-k] [FILE...] — convert WebP images to PNG (default: every *.webp here)
unwebp() {
  emulate -L zsh
  setopt null_glob
  msh::need ffmpeg || return
  local keep=0 f out
  [[ ${1-} == -k ]] && { keep=1; shift; }
  (( $# )) || set -- *.webp
  (( $# )) || { msh::info "no .webp files here"; return 0; }
  for f in "$@"; do
    out=${f%.webp}.png
    if ffmpeg -loglevel error -y -i "$f" "$out"; then
      (( keep )) || rm -f -- "$f"
      print -r -- "[*] $f → $out"
    else
      msh::err "failed: $f"
    fi
  done
}

# makeclip [AUDIO VISUAL OUT] — make an mp4 from an audio track and an image, gif or video
makeclip() {
  emulate -L zsh
  msh::need ffmpeg || return
  local audio=${1-} video=${2-} output=${3-}
  [[ -n $audio ]]  || read -r "audio?Audio file (.wav/.mp3): "
  [[ -n $video ]]  || read -r "video?Video/image file (.mp4/.png/.jpg/.gif): "
  [[ -n $output ]] || read -r "output?Output file (e.g. output.mp4): "
  [[ -f $audio && -f $video && -n $output ]] || { msh::err "makeclip: missing input"; return 1; }
  local -a enc=(-c:v libx264 -crf 23 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest)
  case ${video:e:l} in
    png|jpg|jpeg|webp) ffmpeg -y -loop 1 -i "$video" -i "$audio" $enc "$output" ;;
    gif)               ffmpeg -y -ignore_loop 0 -i "$video" -i "$audio" $enc "$output" ;;
    mp4|mkv|webm|mov)  ffmpeg -y -i "$video" -i "$audio" -map 0:v:0 -map 1:a:0 $enc "$output" ;;
    *) msh::err "makeclip: unsupported visual format: ${video:e}"; return 1 ;;
  esac && msh::ok "created $output (H.264 + AAC)"
}

# screenshotd [DELAY] — select an area, wait DELAY seconds, save + copy the screenshot (Wayland)
screenshotd() {
  msh::need grim slurp wl-copy || return
  local delay=${1:-5} geo
  msh::info "Select an area..."
  geo=$(slurp) || { msh::warn "selection cancelled"; return 1; }
  msh::info "Capturing in ${delay}s..."
  sleep $delay
  if grim -g "$geo" "$SCREENSHOT_FILE" && wl-copy --type image/png < "$SCREENSHOT_FILE"; then
    msh::ok "saved $SCREENSHOT_FILE (also in the clipboard)"
    (( $+commands[notify-send] )) && notify-send "Screenshot captured" "Saved to $SCREENSHOT_FILE and copied"
    return 0
  fi
  msh::err "screenshot failed"; return 1
}

# tidy-media [-n] — sort media files from the current dir into $MEDIA_DIR/{Pictures,Videos,Audio,Documents}
tidy-media() {
  emulate -L zsh
  setopt extended_glob null_glob
  local dry=0 f kind dest name ext n moved=0
  [[ ${1-} == -n ]] && dry=1
  local -A map=(
    Pictures '*.(#i)(gif|jpg|jpeg|png|webp|bmp|svg|heic)'
    Videos   '*.(#i)(mp4|mkv|webm|mov|avi)'
    Audio    '*.(#i)(mp3|wav|flac|ogg|opus|m4a)'
    Documents '*.(#i)(pdf|epub|docx|odt|txt|md)'
  )
  for kind in ${(k)map}; do
    for f in ${~map[$kind]}; do
      [[ -f $f ]] || continue
      dest=$MEDIA_DIR/$kind/$f name=${f:r} ext=${f:e} n=0
      while [[ -e $dest ]]; do (( n++ )); dest=$MEDIA_DIR/$kind/$name-$n.$ext; done
      if (( dry )); then
        print -r -- "would move $f → $dest"
      else
        command mkdir -p -- $MEDIA_DIR/$kind && command mv -n -- "$f" "$dest" && print -r -- "moved $f → $dest"
      fi
      (( moved++ ))
    done
  done
  msh::ok "$moved file(s) organized"
}
