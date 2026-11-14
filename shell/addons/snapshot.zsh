#!/usr/bin/env zsh
# NAME: snapshot
# DESC: Back up everything Modern Shell modifies — create, list, diff, restore, remove snapshots
# TAGS: CORE, SYSTEM, SECURITY
# DEP: coreutils, fzf (optional)
# DEFAULT: on
# VER: 1.0
# DEV: SilverX
# EXAMPLE: snapshot create -l before-experiment
# EXAMPLE: snapshot list
# EXAMPLE: snapshot restore        (pick from a list)
# EXAMPLE: snapshot rm             (pick, then confirm)
# | Snapshots live in `~/.BACKUP/msh/<id>/` (override with `MSH_BACKUP`).
# | A snapshot copies every path listed in `$MSH_HOME/targets.list` — the same
# | list the installer writes to — and also records which paths did **not**
# | exist, so restoring is a *full* revert: files created later are removed.
# |
# | The installer runs `snapshot create --label pre-install` automatically
# | before it changes anything, and `restore` itself takes a `pre-restore`
# | snapshot first, so a restore can always be undone.
# |
# | | Command | What it does |
# | |---|---|
# | | `snapshot create [-l label] [-r reason]` | new snapshot of the current state |
# | | `snapshot list [--porcelain]` | newest first; `#1` is the latest |
# | | `snapshot show <id\|#>` | metadata + what is inside |
# | | `snapshot diff <id\|#>` | what changed since the snapshot |
# | | `snapshot restore [id\|#] [-y]` | full revert (picker when no id) |
# | | `snapshot rm [id\|#...] [-y]` | delete snapshots (picker when no id) |
# | | `snapshot prune [--keep N] [-y]` | keep only the newest N (default 5) |
# |
# | Short aliases: `snap-new`, `snap-list`, `snap-restore`, `snap-rm`.
# | Run as a script too: `zsh snapshot.zsh create -l manual`.

# Script mode / standalone use: pull in the shared helpers if they are missing.
(( $+functions[msh::info] )) || source "${${(%):-%x}:A:h:h}/rc.d/00-init.zsh"

zmodload -F zsh/datetime p:EPOCHSECONDS p:EPOCHREALTIME b:strftime

: ${MSH_BACKUP:=$HOME/.BACKUP/msh}
: ${MSH_TARGETS:=$MSH_HOME/targets.list}

# snapshot <command> [args] — manage Modern Shell snapshots (see `snapshot help`)
snapshot() {
  local cmd=${1:-help}
  (( $# )) && shift
  case $cmd in
    create|new|c)        msh::snap_create "$@" ;;
    list|ls|l)           msh::snap_list "$@" ;;
    show|info)           msh::snap_show "$@" ;;
    diff)                msh::snap_diff "$@" ;;
    restore|revert|r)    msh::snap_restore "$@" ;;
    rm|remove|delete|d)  msh::snap_rm "$@" ;;
    prune)               msh::snap_prune "$@" ;;
    path|dir)            print -r -- "$MSH_BACKUP" ;;
    help|-h|--help)      msh::snap_help ;;
    *) msh::err "snapshot: unknown command '$cmd'"; msh::snap_help; return 2 ;;
  esac
}

# Create a new snapshot of the current state
alias snap-new='snapshot create'
# List snapshots, newest first
alias snap-list='snapshot list'
# Restore a snapshot (interactive picker without an id)
alias snap-restore='snapshot restore'
# Remove snapshots (interactive picker without an id)
alias snap-rm='snapshot rm'

msh::snap_help() {
  msh::pp "%B%F{39}snapshot%f%b — back up & restore everything Modern Shell modifies

%BUSAGE%b
  snapshot %F{76}create%f  [-l|--label NAME] [-r|--reason TEXT] [-q] [--targets FILE]
  snapshot %F{76}list%f    [--porcelain]
  snapshot %F{76}show%f    <id|#>
  snapshot %F{76}diff%f    <id|#>
  snapshot %F{76}restore%f [id|#|latest] [-y|--yes] [--no-safety]
  snapshot %F{76}rm%f      [id|#...] [-y|--yes]
  snapshot %F{76}prune%f   [--keep N] [-y|--yes]
  snapshot %F{76}path%f

%BNOTES%b
  # = position in \`snapshot list\` (1 = newest). Storage: %F{103}$MSH_BACKUP%f
  Targets: %F{103}$MSH_TARGETS%f"
}

# msh::snap_targets [file] — print absolute target paths (comments skipped)
msh::snap_targets() {
  local file=${1:-$MSH_TARGETS} line
  [[ -r $file ]] || { msh::err "snapshot: targets list not found: $file"; return 1; }
  while IFS= read -r line; do
    line=${line%%[[:space:]]#}
    [[ -z $line || $line == \#* ]] && continue
    [[ $line == '~/'* ]] && line=$HOME/${line#'~/'}
    # Hard wall: never touch private files outside msh's own territory.
    [[ $line == $HOME/.zsh || $line == $HOME/.zsh/* || $line == $MSH_BACKUP* ]] && continue
    print -r -- "$line"
  done < "$file"
}

# msh::snap_ids — snapshot ids, newest first
msh::snap_ids() {
  local d
  local -a rows
  for d in "$MSH_BACKUP"/<->-<->*(N/); do
    rows+=("${$(msh::snap_meta ${d:t} epoch):-0}:${d:t}")
  done
  rows=(${(On)rows})
  (( ${#rows} )) && print -rl -- ${rows#*:}
}

# msh::pp <prompt-string> — print -P, with styling stripped under NO_COLOR / no tty
msh::pp() {
  setopt local_options extended_glob
  local s=$1
  if [[ -n ${NO_COLOR-} || ! -t 1 ]]; then
    s=${s//\%F\{[0-9a-z]##\}/}
    s=${s//\%[fBbUuKk]/}
  fi
  print -P -- "$s"
}

# msh::snap_resolve <id|#|latest> — print the snapshot id or fail
msh::snap_resolve() {
  local want=$1 ids
  ids=(${(f)"$(msh::snap_ids)"})
  (( ${#ids} )) || { msh::err "snapshot: no snapshots in $MSH_BACKUP"; return 1; }
  case $want in
    latest|'') print -r -- $ids[1] ;;
    <1-9999>)
      (( want <= ${#ids} )) || { msh::err "snapshot: no snapshot #$want (have ${#ids})"; return 1; }
      print -r -- $ids[want] ;;
    *)
      [[ -d $MSH_BACKUP/$want && $want == <->-<->* ]] || { msh::err "snapshot: '$want' not found"; return 1; }
      print -r -- $want ;;
  esac
}

# msh::snap_meta <id> <key> — read one key from a snapshot's meta file
msh::snap_meta() {
  local line
  [[ -r $MSH_BACKUP/$1/meta ]] || return 0
  while IFS= read -r line; do
    [[ $line == "$2="* ]] && { print -r -- "${line#*=}"; return; }
  done < "$MSH_BACKUP/$1/meta"
}

msh::snap_create() {
  local label='' reason='manual' quiet=0 targets=$MSH_TARGETS
  while (( $# )); do
    case $1 in
      -l|--label)   label=$2; shift 2 ;;
      -r|--reason)  reason=$2; shift 2 ;;
      -q|--quiet)   quiet=1; shift ;;
      --targets)    targets=$2; shift 2 ;;
      *) label=${label:-$1}; shift ;;
    esac
  done
  label=${${label//[^A-Za-z0-9._-]/-}[1,40]}

  local -a paths
  paths=(${(f)"$(msh::snap_targets "$targets")"}) || return 1

  local id n=1
  strftime -s id %Y%m%d-%H%M%S $EPOCHSECONDS
  [[ -n $label ]] && id+="_$label"
  while [[ -e $MSH_BACKUP/$id ]]; do id=${id%%.<->}.$((n++)); done
  local dir=$MSH_BACKUP/$id

  ( umask 077; mkdir -p -- "$dir/files" ) || { msh::err "snapshot: cannot create $dir"; return 1; }
  chmod 700 -- "${MSH_BACKUP:h}" "$MSH_BACKUP" 2>/dev/null

  local p rel present=0 absent=0
  : > "$dir/manifest"
  for p in $paths; do
    rel=${p#$HOME/}
    if [[ -e $p || -L $p ]]; then
      mkdir -p -- "$dir/files/${rel:h}"
      if cp -a -- "$p" "$dir/files/$rel"; then
        print -r -- "present	~/$rel" >> "$dir/manifest"; (( present++ ))
      else
        msh::warn "snapshot: could not copy $p"
      fi
    else
      print -r -- "absent	~/$rel" >> "$dir/manifest"; (( absent++ ))
    fi
  done

  {
    print -r -- "id=$id"
    print -r -- "created=$(strftime "%Y-%m-%d %H:%M:%S" $EPOCHSECONDS)"
    print -r -- "epoch=$EPOCHREALTIME"
    print -r -- "label=$label"
    print -r -- "reason=$reason"
    print -r -- "host=${HOST:-$(uname -n)}"
    print -r -- "user=$USER"
    print -r -- "msh_version=$([[ -r $MSH_HOME/VERSION ]] && print -r -- "$(<$MSH_HOME/VERSION)")"
  } > "$dir/meta"

  (( quiet )) || msh::ok "snapshot $id created ($present saved, $absent absent) → $dir"
  print -r -- "$id" > "$MSH_BACKUP/.last"
}

msh::snap_list() {
  local porcelain=0
  [[ $1 == --porcelain || $1 == -p ]] && porcelain=1
  local -a ids
  ids=(${(f)"$(msh::snap_ids)"})
  if (( ! ${#ids} )); then
    (( porcelain )) || msh::info "no snapshots yet in $MSH_BACKUP — create one with: snapshot create"
    return 0
  fi
  local id i=0 size items
  (( porcelain )) || printf "%s  #  %-32s %-19s %-12s %5s %6s%s\n" "$(msh::_c $'\e[1;34m')" ID CREATED REASON ITEMS SIZE "$(msh::_c $'\e[0m')"
  for id in $ids; do
    (( i++ ))
    size=$(du -sh -- "$MSH_BACKUP/$id" 2>/dev/null); size=${size%%[[:space:]]*}
    items=$(grep -c '^present' "$MSH_BACKUP/$id/manifest" 2>/dev/null)
    if (( porcelain )); then
      print -r -- "$id	$(msh::snap_meta $id created)	$(msh::snap_meta $id label)	$(msh::snap_meta $id reason)	${items:-0}	$size"
    else
      printf '%s%3d%s  %-32s %-19s %-12s %5s %6s\n' "$(msh::_c $'\e[1;33m')" $i "$(msh::_c $'\e[0m')" \
        "$id" "$(msh::snap_meta $id created)" "$(msh::snap_meta $id reason)" "${items:-0}" "$size"
    fi
  done
}

msh::snap_show() {
  local id; id=$(msh::snap_resolve "$1") || return 1
  msh::pp "%B%F{39}snapshot $id%f%b"
  local line
  while IFS= read -r line; do
    printf '  %-12s %s\n' "${line%%=*}" "${line#*=}"
  done < "$MSH_BACKUP/$id/meta"
  msh::pp "%BContents%b"
  while IFS=$'\t' read -r state tgt; do
    if [[ $state == present ]]; then msh::pp "  %F{76}●%f $tgt"
    else msh::pp "  %F{244}○ $tgt (did not exist)%f"; fi
  done < "$MSH_BACKUP/$id/manifest"
}

msh::snap_diff() {
  local id; id=$(msh::snap_resolve "$1") || return 1
  local state tgt abs src changed=0
  while IFS=$'\t' read -r state tgt; do
    abs=$HOME/${tgt#'~/'} src=$MSH_BACKUP/$id/files/${tgt#'~/'}
    if [[ $state == absent ]]; then
      [[ -e $abs || -L $abs ]] && { msh::pp "%F{76}+ $tgt%f (created after snapshot)"; changed=1; }
    elif [[ ! -e $abs && ! -L $abs ]]; then
      msh::pp "%F{196}- $tgt%f (removed since snapshot)"; changed=1
    elif ! diff -rq -- "$src" "$abs" >/dev/null 2>&1; then
      msh::pp "%F{214}~ $tgt%f"
      diff -rq -- "$src" "$abs" 2>/dev/null | sed 's/^/    /' | head -20
      changed=1
    fi
  done < "$MSH_BACKUP/$id/manifest"
  (( changed )) || msh::ok "no changes since $id"
}

# msh::snap_pick <prompt> [multi] — interactive picker, prints chosen ids
msh::snap_pick() {
  local -a ids
  ids=(${(f)"$(msh::snap_ids)"})
  (( ${#ids} )) || { msh::err "snapshot: no snapshots in $MSH_BACKUP"; return 1; }
  if (( $+commands[fzf] )) && [[ -t 0 ]]; then
    local -a flags=(--prompt="$1 › " --height=60% --reverse
      --preview="cat $MSH_BACKUP/{}/meta; echo; cat $MSH_BACKUP/{}/manifest")
    [[ -n $2 ]] && flags+=(--multi --header='TAB selects several')
    print -rl -- $ids | fzf "${flags[@]}"
  else
    msh::snap_list >&2
    local reply
    read -r "reply?$1 — number(s) or id(s): " || return 1
    local r
    for r in ${=reply}; do msh::snap_resolve "$r" || return 1; done
  fi
}

msh::snap_restore() {
  local want='' yes=0 safety=1
  while (( $# )); do
    case $1 in
      -y|--yes) yes=1 ;;
      --no-safety) safety=0 ;;
      *) want=$1 ;;
    esac
    shift
  done
  local id
  if [[ -z $want ]]; then id=$(msh::snap_pick restore) || return 1; [[ -n $id ]] || return 1
  else id=$(msh::snap_resolve "$want") || return 1; fi

  msh::snap_show "$id"
  print
  (( yes )) || MSH_YES=${MSH_YES-} msh::confirm "Fully revert to snapshot $id? Current versions of these paths are replaced" || {
    msh::info "cancelled"; return 1; }

  (( safety )) && msh::snap_create -l pre-restore -r "before restoring $id"

  local state tgt abs src failed=0
  while IFS=$'\t' read -r state tgt; do
    abs=$HOME/${tgt#'~/'} src=$MSH_BACKUP/$id/files/${tgt#'~/'}
    if [[ -e $abs || -L $abs ]]; then
      rm -rf -- "$abs" || { msh::err "cannot remove $abs"; failed=1; continue; }
    fi
    if [[ $state == present ]]; then
      mkdir -p -- "${abs:h}" && cp -a -- "$src" "$abs" || { msh::err "cannot restore $abs"; failed=1; }
    fi
  done < "$MSH_BACKUP/$id/manifest"
  (( failed )) && { msh::warn "restore of $id finished with errors"; return 1; }
  msh::ok "restored $id — open a new shell (or run: exec zsh) to load it"
}

msh::snap_rm() {
  local -a want ids
  local yes=0
  while (( $# )); do
    case $1 in
      -y|--yes) yes=1 ;;
      *) want+=("$1") ;;
    esac
    shift
  done
  if (( ${#want} )); then
    local w
    for w in $want; do ids+=("$(msh::snap_resolve "$w")") || return 1; done
  else
    ids=(${(f)"$(msh::snap_pick remove multi)"}) || return 1
  fi
  ids=(${ids:#})
  (( ${#ids} )) || { msh::info "nothing selected"; return 1; }
  msh::pp "%BWill permanently delete:%b"
  print -rl -- "  "${^ids}
  (( yes )) || msh::confirm "Delete ${#ids} snapshot(s)?" || { msh::info "cancelled"; return 1; }
  local id
  for id in $ids; do
    [[ $id == <->-<->* && -d $MSH_BACKUP/$id ]] || continue
    rm -rf -- "$MSH_BACKUP/$id" && msh::ok "removed $id"
  done
}

msh::snap_prune() {
  local keep=5 yes=0
  while (( $# )); do
    case $1 in
      --keep|-k) keep=$2; shift ;;
      -y|--yes) yes=1 ;;
    esac
    shift
  done
  local -a ids
  ids=(${(f)"$(msh::snap_ids)"})
  (( ${#ids} > keep )) || { msh::info "nothing to prune (${#ids} ≤ $keep)"; return 0; }
  local -a old=(${ids[keep+1,-1]})
  local -a flags=()
  (( yes )) && flags=(-y)
  msh::snap_rm $flags $old
}

# Script mode: `zsh snapshot.zsh <command> ...`
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then snapshot "$@"; fi
