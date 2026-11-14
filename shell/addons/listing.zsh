#!/usr/bin/env zsh
# NAME: listing
# DESC: Smarter listings: lsf (recent files, trimmed names), lsdirs (dirs by activity + size), less helpers, diskspace
# TAGS: FILES, EYECANDY
# DEP: ls, less, awk, du
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: lsf ~/Downloads
# EXAMPLE: lsdirs ~/Projects
# EXAMPLE: recent-file
# | Merged from `ls-tools.zsh`, `files.zsh`, ZRC `list-recent-files`,
# | `better-less` and `disk-usage-alias`.
# |
# | | Command | What it does |
# | |---|---|
# | | `lsf [DIR]` | files only, oldest → newest (newest at the bottom), names trimmed to `LSF_MAX` (25) chars, colors kept |
# | | `recent-file [DIR]` | the most recently modified file |
# | | `lsdirs [DIR]` | sub-dirs sorted by newest file inside, prefixed `[size MB \| files changed in 24h]` |
# | | `les FILE` | less with raw colors, starting at the end |
# | | `lez [DIR]` | colored `ls -1` in les |
# | | `lezz [DIR]` | `lsf` in les |
# | | `diskspace` | size of every entry here, sorted |
# |
# | `lsdirs` was called `lsd` in `ls-tools.zsh`; renamed so it no longer hides
# | the real `lsd` (LSDeluxe) program.

: ${LSF_MAX:=25}

# lsf [DIR] — files sorted by mtime (newest last), names trimmed, colors preserved
lsf() {
  command ls --color=always --hyperlink=never -1 -p -t "$@" | tac | awk -v max="$LSF_MAX" '
    BEGIN { ESC = sprintf("%c", 27); esc_re = ESC "\\[[0-9;]*[A-Za-z]"; reset_re = ESC "\\[[0-9;]*m" }
    {
      orig = $0; plain = orig; gsub(esc_re, "", plain)
      if (plain ~ /\/$/) next                         # drop directories (from -p)
      col = ""; rest = orig
      while (match(rest, "^" esc_re)) { col = col substr(rest, RSTART, RLENGTH); rest = substr(rest, RLENGTH + 1) }
      reset = ""; t = orig
      while (match(t, reset_re)) { reset = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH) }
      n = length(plain); dot = 0
      for (i = 2; i <= n - 1; i++) if (substr(plain, i, 1) == ".") dot = i
      if (dot > 1) { base = substr(plain, 1, dot - 1); ext = substr(plain, dot + 1) } else { base = plain; ext = "" }
      bmax = max; if (ext != "") bmax = max - 1 - length(ext); if (bmax < 1) bmax = 1
      printf "%s%s%s\n", col, substr(base, 1, bmax) ((ext != "") ? "." ext : ""), reset
    }'
}

# recent-file [DIR] — print the most recently modified file
recent-file() {
  local -a f=( ${1:-.}/*(.DNom[1]) )
  (( $#f )) && print -r -- "${f[1]#./}"
}

# les FILE — less with raw colors, starting at the bottom, no screen clear
les() { command less -R +G -X -- "$@"; }

# lez [DIR] — colored one-per-line ls, paged with les
lez() { command ls --color=always -1 "$@" | les; }

# lezz [DIR] — lsf, paged with les
lezz() { lsf "$@" | les; }

# lsdirs [DIR] — sub-directories sorted by recent activity, with size and 24h change count
lsdirs() {
  emulate -L zsh
  zmodload -F zsh/stat b:zstat
  local target=${1:-.} d newest line size
  [[ -d $target ]] || { msh::err "lsdirs: not a directory: $target"; return 1; }
  local -a activity newestf recent
  for d in $target/*(DN/); do
    newestf=( $d/*(DN.om[1]) )
    if (( $#newestf )); then newest=$(zstat +mtime -- $newestf[1]); else newest=$(zstat +mtime -- $d); fi
    activity+=("$newest $d")
  done
  for line in ${(f)"$(print -rl -- $activity | sort -n)"}; do
    d=${line#* }
    size=$(du -sm -- "$d" 2>/dev/null | cut -f1)
    recent=( $d/*(DN.m-1) )
    if [[ ${d:t} == .* ]]; then
      print -r -- "[${size:-?}MB | $#recent] "$'\e[2;36m'"${d:t}/"$'\e[0m'
    else
      print -r -- "[${size:-?}MB | $#recent] "$'\e[1;34m'"${d:t}/"$'\e[0m'
    fi
  done
}

# Show disk usage of every entry in the current directory, sorted
alias diskspace='du -sh -- *(DN) 2>/dev/null | sort -h'
