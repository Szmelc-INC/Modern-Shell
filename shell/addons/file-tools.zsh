#!/usr/bin/env zsh
# NAME: file-tools
# DESC: File utilities: dedupe (find/remove duplicate files), renum (bulk renumber), compare-lines, bin2txt, newf
# TAGS: FILES
# DEP: md5sum, comm, sort
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: dedupe -r -c
# EXAMPLE: renum -k .jpg -p holiday_ -z 3
# EXAMPLE: compare-lines a.txt b.txt --common
# EXAMPLE: bin2txt -n 8 --dump strings.txt firmware/*
# | Merged from `dedupe.sh`, `renumerate.zsh`, `compare.zsh`, `binary.zsh` and
# | the `.zshrc` `newf` alias.
# |
# | | Command | What it does |
# | |---|---|
# | | `dedupe [-r] [-c] [-y]` | find identical files (md5) in `.`; keep the alphabetically first, delete the rest (`-c` moves them to `./COPIES/` instead, `-r` recursive, `-y` no prompt) |
# | | `renum [-k KEY] [-p PREFIX] [-s SUFFIX] [-z PAD] [-n]` | renumber files in `.` (prompts when no flags); `-n` = dry run |
# | | `compare-lines A B [-c]` | lines in only one of the files (symmetric difference); `-c` = lines in both |
# | | `bin2txt [-n MIN] [--dump OUT] FILE...` | readable strings (≥ MIN chars, ≥ 3 letters) from binaries |
# | | `newf FILE` | truncate FILE and open it in `$EDITOR` |
# |
# | Safety: `dedupe` refuses to delete more than 80 % of the files (use `-c`),
# | `renum` renames in two phases so it can never overwrite a file that has not
# | been renamed yet (the old version could).

# dedupe [-r] [-c] [-y] — delete (or move to ./COPIES) duplicate files in the current directory
dedupe() {
  emulate -L zsh
  setopt extended_glob null_glob
  local recursive=0 move=0 yes=0 opt OPTIND=1
  while getopts "rcyh" opt; do
    case $opt in
      r) recursive=1 ;;
      c) move=1 ;;
      y) yes=1 ;;
      h) print "usage: dedupe [-r recursive] [-c move to ./COPIES] [-y no prompt]"; return 0 ;;
      *) return 2 ;;
    esac
  done
  local start=$PWD copies=$PWD/COPIES
  local -a files
  if (( recursive )); then files=( **/*(.D^@) ); else files=( *(.D^@) ); fi
  files=( ${(o)files:#COPIES/*} )
  msh::info "analysing ${#files} file(s) in $start$( (( recursive )) && print ' (recursive)')"
  (( $#files )) || return 0

  local -A first
  local -a dups
  local line sum f bytes=0
  while IFS= read -r line; do
    sum=${line%% *} f=${line#*  }
    if [[ -n ${first[$sum]-} ]]; then
      dups+=("$f")
      print -r -- $'\e[1;34m'"$f"$'\e[0m  ← duplicate of  '"${first[$sum]}"
      (( bytes += $(stat -c %s -- "$f") ))
    else
      first[$sum]=$f
    fi
  done < <(md5sum -- $files 2>/dev/null)

  (( $#dups )) || { msh::ok "no duplicates"; return 0; }
  local pct=$(( $#dups * 100 / $#files ))
  msh::warn "${#dups} duplicate(s), $(numfmt --to=iec $bytes)B, ${pct}% of all files"
  if (( pct > 80 && ! move )); then
    msh::err "safety stop: refusing to delete more than 80% of the files (use -c to move instead)"
    return 1
  fi
  if (( ! yes )); then
    msh::confirm "$( (( move )) && print "Move duplicates to COPIES/" || print "Delete duplicates")?" || { msh::info "cancelled"; return 0; }
  fi
  if (( move )); then
    command mkdir -p -- $copies
    local dest n
    for f in $dups; do
      dest="$copies/Copy of ${f:t}" n=0
      while [[ -e $dest ]]; do (( n++ )); dest="$copies/Copy $n of ${f:t}"; done
      command mv -- "$f" "$dest" && print -r -- "moved: $f"
    done
  else
    rm -f -- $dups && msh::ok "deleted ${#dups} file(s)"
  fi
}

# renum [-k KEY] [-p PREFIX] [-s SUFFIX] [-z PAD] [-n] — renumber files in the current dir
renum() {
  emulate -L zsh
  local keyword="" prefix="" suffix="" pad="" dry=0 asked=0 opt OPTIND=1
  while getopts "k:p:s:z:nh" opt; do
    case $opt in
      k) keyword=$OPTARG; asked=1 ;;
      p) prefix=$OPTARG; asked=1 ;;
      s) suffix=$OPTARG; asked=1 ;;
      z) pad=$OPTARG; asked=1 ;;
      n) dry=1 ;;
      h) print "usage: renum [-k keyword] [-p prefix] [-s suffix] [-z zero-padding] [-n dry-run]"; return 0 ;;
      *) return 2 ;;
    esac
  done
  if (( ! asked )); then
    read -r "keyword?Keyword the name must contain (empty = all files): "
    read -r "prefix?Prefix before the number (e.g. film_): "
    read -r "suffix?Suffix after the number (e.g. _HD): "
    read -r "pad?Zero padding width (3 → 001, 0 = none): "
  fi
  [[ ${pad:-0} == <-> ]] || { msh::err "renum: padding must be a number"; return 2; }
  local -a src=( *(N.on) )
  [[ -n $keyword ]] && src=( ${(M)src:#*${keyword}*} )
  (( $#src )) || { msh::warn "renum: no matching files"; return 1; }
  local -a tmp dst
  local i f ext num
  for (( i = 1; i <= $#src; i++ )); do
    f=$src[i]
    [[ $f == ?*.* ]] && ext=.${f##*.} || ext=""
    printf -v num '%0*d' ${pad:-0} $i
    dst+=("${prefix}${num}${suffix}${ext}")
    tmp+=(".renum.$$.$i$ext")
  done
  # Refuse when a target already exists and is not part of this batch.
  for f in $dst; do
    if [[ -e $f && ${src[(Ie)$f]} -eq 0 ]]; then msh::err "renum: '$f' already exists"; return 1; fi
  done
  if (( dry )); then
    for (( i = 1; i <= $#src; i++ )); do print -r -- "$src[i] → $dst[i]"; done
    return 0
  fi
  for (( i = 1; i <= $#src; i++ )); do command mv -- "$src[i]" "$tmp[i]" || return 1; done
  for (( i = 1; i <= $#src; i++ )); do command mv -n -- "$tmp[i]" "$dst[i]" || return 1; done
  msh::ok "renumbered ${#src} file(s)"
}

# compare-lines A B [-c|--common] — lines unique to either file (default) or common to both
compare-lines() {
  (( $# >= 2 )) || { print -u2 "usage: compare-lines <file1> <file2> [-c|--common]"; return 2; }
  local a=$1 b=$2 mode=unique; shift 2
  case ${1-} in
    -c|--common) mode=common ;;
    '') ;;
    *) msh::err "compare-lines: unknown option $1"; return 2 ;;
  esac
  [[ -r $a && -f $a ]] || { msh::err "cannot read '$a'"; return 1; }
  [[ -r $b && -f $b ]] || { msh::err "cannot read '$b'"; return 1; }
  if [[ $mode == common ]]; then
    comm -12 <(sort -u -- "$a") <(sort -u -- "$b")
  else
    comm -3 <(sort -u -- "$a") <(sort -u -- "$b") | sed 's/^\t//'
  fi
}

# Old name of compare-lines
alias compare_lines='compare-lines'

# bin2txt [-n MIN] [--dump OUT] FILE... — extract readable text strings from binary files
bin2txt() {
  emulate -L zsh
  local dumpfile="" minlen=6 f
  local -a files
  while (( $# )); do
    case $1 in
      --dump) dumpfile=${2:?bin2txt: --dump needs a file}; shift 2 ;;
      -n|--min-length)
        [[ ${2-} == <-> ]] || { msh::err "bin2txt: -n needs a number"; return 2; }
        minlen=$2; shift 2 ;;
      -h|--help) print "usage: bin2txt [-n MINLEN] [--dump OUT.txt] <file>..."; return 0 ;;
      -*) msh::err "bin2txt: unknown option $1"; return 2 ;;
      *) files+=("$1"); shift ;;
    esac
  done
  (( $#files )) || { print -u2 "usage: bin2txt [-n MINLEN] [--dump OUT.txt] <file>..."; return 2; }
  local multi=$(( $#files > 1 || ${#dumpfile} ))
  {
    for f in $files; do
      [[ -f $f ]] || { msh::warn "bin2txt: skipping non-regular file: $f"; continue; }
      (( multi )) && print -r -- "# $f"
      LC_ALL=C command grep -aoE "[ -~]{$minlen,}" -- "$f" 2>/dev/null | command grep -E '[a-zA-Z]{3}'
      (( multi )) && print
    done
  } > ${dumpfile:-/dev/stdout}
  [[ -n $dumpfile ]] && msh::ok "dumped text from ${#files} file(s) → $dumpfile"
  return 0
}

# newf FILE — empty FILE (create when missing) and open it in $EDITOR
newf() {
  [[ -n ${1-} ]] || { print -u2 "usage: newf <file>"; return 2; }
  : >| "$1" && ${EDITOR:-nano} "$1"
}
