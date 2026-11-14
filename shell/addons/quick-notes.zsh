#!/usr/bin/env zsh
# NAME: quick-notes
# DESC: Jot notes from the prompt: note TEXT, multi-line note mode, notes to read/search/edit them
# TAGS: FILES, CORE
# DEP: date, tail
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: note buy milk
# EXAMPLE: note            (multi-line; finish with a line ending in ")
# EXAMPLE: notes -g milk
# | Ported from ZRC `quick-notes`. Notes are appended to `$NOTES_FILE`
# | (default `~/quick_notes.txt`), each prefixed with a timestamp unless
# | `NOTES_STAMP=0`.
# |
# | | Command | What it does |
# | |---|---|
# | | `note TEXT...` | append one note |
# | | `note` | multi-line mode: type lines, end with a line ending in `"` (or Ctrl-D) |
# | | `notes` | show all notes |
# | | `notes -g WORD` | grep notes (case-insensitive) |
# | | `notes -e` | open the notes file in `$EDITOR` |
# | | `notes -t [N]` | last N notes (default 10) |

: ${NOTES_FILE:=$HOME/quick_notes.txt}
: ${NOTES_STAMP:=1}

# note [TEXT...] — append a note (no args: multi-line mode, end with a trailing ")
note() {
  local stamp=""
  (( NOTES_STAMP )) && stamp="[$(date '+%F %R')] "
  if (( $# )); then
    print -r -- "$stamp$*" >> "$NOTES_FILE" && msh::ok "note added"
    return
  fi
  msh::info 'Type your note; end with a line ending in " (or Ctrl-D):'
  local line first=1
  while IFS= read -r line; do
    if [[ $line == *\" ]]; then
      print -r -- "${first:+$stamp}${line%\"}" >> "$NOTES_FILE"
      first=""
      break
    fi
    print -r -- "${first:+$stamp}$line" >> "$NOTES_FILE"
    first=""
  done
  msh::ok "note saved"
}

# notes [-g WORD | -e | -t [N]] — show, grep, edit or tail the notes file
notes() {
  [[ -f $NOTES_FILE ]] || { msh::info "No notes yet ($NOTES_FILE)."; return 0; }
  case ${1-} in
    -g|--grep) command grep -i --color=auto -- "${2:?notes -g WORD}" "$NOTES_FILE" ;;
    -e|--edit) ${EDITOR:-nano} "$NOTES_FILE" ;;
    -t|--tail) tail -n "${2:-10}" -- "$NOTES_FILE" ;;
    '')        command cat -- "$NOTES_FILE" ;;
    *) print -u2 "usage: notes [-g WORD | -e | -t [N]]"; return 2 ;;
  esac
}
