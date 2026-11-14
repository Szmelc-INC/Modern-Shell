#!/usr/bin/env zsh
# NAME: suno
# DESC: Download Suno songs (wav/mp3/mp4/m4a) by URL or straight from the clipboard, with retries and dedupe
# TAGS: MEDIA, WEB, FUN
# DEP: curl, jq, ffprobe (optional), wl-paste (optional), xclip (optional)
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: suno https://suno.com/s/XXXXXXXX
# EXAMPLE: suno -f mp3 -n my-track          (URL taken from the clipboard)
# | Ported from `SUNO.zsh` (the cookie-free version). The older `suno.zsh`
# | `wget-suno` needed a pasted browser cookie and was dropped.
# |
# | Uses the third-party service sunodownload.io (`SUNO_API` to override).
# |
# | | Option | Meaning |
# | |---|---|
# | | `-f, --format mp3\|wav\|mp4\|m4a` | output format (default wav) |
# | | `-o, --output DIR` | target directory (default `$SUNO_OUTDIR`) |
# | | `-n, --name NAME` | file name (extension added when missing) |
# |
# | Tweakables: `SUNO_OUTDIR` (default `~/Music/suno`), `SUNO_API`, `SUNO_TRIES` (3).
# | An identical existing file is detected by content and never overwritten blindly.

: ${SUNO_OUTDIR:=$HOME/Music/suno}
: ${SUNO_API:=https://sunodownload.io}
: ${SUNO_TRIES:=3}

# suno::bar TEXT COLOR — gray `# ===== [ TEXT ] =====` banner (internal)
suno::bar() { printf '%s# ========= [ %s%s%s ] =========%s\n' "$3" "$2" "$1" "$3" "$4"; }

# suno [URL] [-f FMT] [-o DIR] [-n NAME] — download a Suno track (URL from clipboard when omitted)
suno() {
  emulate -L zsh
  local api=$SUNO_API format=wav outdir=$SUNO_OUTDIR name="" url=""
  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
  local R= C= O= G= GR= RED= GRN=
  if [[ -t 1 && -z ${NO_COLOR-} ]]; then
    R=$'\e[0m' C=$'\e[36m' O=$'\e[38;5;208m' G=$'\e[32m' GR=$'\e[90m' RED=$'\e[1;31m' GRN=$'\e[1;32m'
  fi
  while (( $# )); do
    case $1 in
      -f|--format) format=$2; shift 2 ;;
      -o|--output) outdir=$2; shift 2 ;;
      -n|--name)   name=$2;   shift 2 ;;
      -h|--help)
        print "usage: suno [suno-url] [-f mp3|wav|mp4|m4a] [-o dir] [-n name]"
        print "  no url -> taken from the clipboard; default dir -> $SUNO_OUTDIR"
        return 0 ;;
      -*) msh::err "suno: unknown flag $1"; return 2 ;;
      *)  url=$1; shift ;;
    esac
  done
  msh::need curl jq || return
  if [[ -z $url ]]; then
    if (( $+commands[wl-paste] )); then url=$(wl-paste -n 2>/dev/null)
    elif (( $+commands[xclip] )); then url=$(xclip -selection clipboard -o 2>/dev/null)
    fi
    [[ -n $url ]] || { msh::err "suno: no URL given and the clipboard is empty"; return 1; }
  fi
  [[ $url == *suno.com* ]] || { msh::err "suno: not a Suno URL: $url"; return 1; }
  [[ $format == (mp3|wav|mp4|m4a) ]] || { msh::err "suno: bad format '$format' (mp3|wav|mp4|m4a)"; return 2; }
  command mkdir -p -- "$outdir" || return 1

  suno::bar DOWNLOADING "$RED" "$GR" "$R"
  printf '> [DIR]: [%s%s%s]\n> [URL]: [%s%s%s]\n' "$C" "$outdir" "$R" "$C" "$url" "$R"

  # The download URL is single-use, so every retry requests a fresh one.
  local resp dl fname afmt title tmp="" attempt=0 ok=0
  while (( attempt < SUNO_TRIES )); do
    (( attempt++ ))
    resp=$(curl -s --connect-timeout 15 --max-time 45 "$api/api/suno/download/" \
      -H 'content-type: application/json' -H "origin: $api" -H "referer: $api/en/" -H "user-agent: $ua" \
      --data-raw "$(jq -nc --arg u "$url" --arg f "$format" '{url:$u,format:$f}')") || resp=""
    if [[ -z $resp ]]; then
      msh::warn "suno: request failed ($attempt/$SUNO_TRIES)"; sleep 2; continue
    fi
    if [[ $(jq -r '.success // false' <<<"$resp") != true ]]; then
      msh::err "suno: API error: $resp"; return 1
    fi
    dl=$(jq -r '.downloadUrl' <<<"$resp")
    fname=$(jq -r '.filename' <<<"$resp")
    afmt=$(jq -r --arg f "$format" '.actualFormat // $f' <<<"$resp")
    title=$(jq -r '.title // ""' <<<"$resp")
    tmp=$(mktemp "$outdir/.suno.XXXXXX") || return 1
    # --speed-limit/--speed-time only kills stalls, never a slow but active download.
    if curl -fL --progress-bar --connect-timeout 30 --speed-limit 2048 --speed-time 30 \
         "$api$dl" -H "referer: $api/en/" -H "user-agent: $ua" -o "$tmp"; then
      ok=1; break
    fi
    msh::warn "suno: download stalled ($attempt/$SUNO_TRIES)"
    rm -f -- "$tmp"; tmp=""; sleep 2
  done
  (( ok )) || { msh::err "suno: giving up after $SUNO_TRIES attempts"; return 1; }

  local out
  if [[ -n $name ]]; then
    [[ $name == *.(mp3|wav|mp4|m4a) ]] && out=$name || out="$name.$afmt"
  else
    out=${fname:t}
  fi
  [[ -n $title ]] || title=${out%.*}

  local mmss='--:--' dur bytes hsize
  if (( $+commands[ffprobe] )); then
    dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$tmp" 2>/dev/null)
    [[ -n $dur ]] && mmss=$(awk -v d="$dur" 'BEGIN{s=int(d+0.5);printf "%02d:%02d",int(s/60),s%60}')
  fi
  bytes=$(stat -c %s -- "$tmp" 2>/dev/null)
  hsize=$(numfmt --to=iec --suffix=B "${bytes:-0}" 2>/dev/null || print -r -- "${bytes}B")
  printf '> [FILE]: %s%s%s / [%s%s%s] / [%s%s%s] / [%s%s%s]\n' \
    "$O" "$out" "$R" "$G" "$mmss" "$R" "$G" "$hsize" "$R" "$G" "$afmt" "$R"

  local stem=${out%.*} ext=${out##*.} cand="$outdir/$out" dup="" k=0 final=""
  while [[ -e $cand ]]; do
    if cmp -s -- "$tmp" "$cand"; then dup=$cand; break; fi
    (( k++ )); cand="$outdir/$stem-($k).$ext"
  done
  if [[ -n $dup ]]; then
    if msh::confirm "This exact file already exists. Keep a second copy?"; then
      local n=1 save="$outdir/$stem-(1).$ext"
      while [[ -e $save ]]; do (( n++ )); save="$outdir/$stem-($n).$ext"; done
      command mv -- "$tmp" "$save"; final=$save
    else
      rm -f -- "$tmp"; final=$dup
    fi
  else
    command mv -- "$tmp" "$cand"; final=$cand
  fi
  [[ ${final:t} != "$out" ]] && printf '> [SAVED]: %s%s%s\n' "$O" "${final:t}" "$R"
  suno::bar COMPLETE "$GRN" "$GR" "$R"
}
