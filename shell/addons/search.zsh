#!/usr/bin/env zsh
# NAME: search
# DESC: Find files and text fast: searchin, hunt, lsk, ffind/dfind, fopen, fzx, grepi/grepc
# TAGS: SEARCH, FILES
# DEP: grep, find, fzf (optional), fd (optional), xdg-open (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: searchin "TODO"          (interactive when no phrase is given)
# EXAMPLE: lsk invoice
# EXAMPLE: hunt
# EXAMPLE: fopen report
# | Merged from `greps.zsh`, `greps2.zsh`, `list.zsh`, ZRC `grep-plus`,
# | `find-files-alias`, `find-directories-alias`, `find-and-open` and `.zshrc` `fzx`.
# |
# | | Command | What it does |
# | |---|---|
# | | `searchin [-i] [PHRASE] [DIR]` | grep file contents recursively, pretty report with line:column |
# | | `hunt` | interactive: glob → reader tool → keyword → optional action per hit |
# | | `lsk KEYWORD` | find names containing KEYWORD, colored absolute paths |
# | | `ffind PATTERN` / `dfind PATTERN` | case-insensitive file / directory name search |
# | | `fopen [TERM]` | fuzzy-pick a file (fzf) and open it with xdg-open |
# | | `fzx` | fuzzy-pick a file (fd + fzf), prints the path |
# | | `grepi` / `grepc` | case-insensitive grep / count matches |
# |
# | `hunt`'s post-match action is run with `eval` — only type commands you trust.

# grep, case-insensitive, colored
alias grepi='grep -i --color=auto'
# grep, count matching lines
alias grepc='grep -c --color=auto'
# Find files below . by name, case-insensitive (ffind '*.pdf')
alias ffind='find . -type f -iname'
# Find directories below . by name, case-insensitive
alias dfind='find . -type d -iname'

# searchin [-i] [PHRASE] [DIR] — recursive content search with a readable colored report
searchin() {
  emulate -L zsh
  local phrase="" dir=. insensitive=0 ans
  while (( $# )); do
    case $1 in
      -i|--ignore-case) insensitive=1; shift ;;
      -h|--help) print "usage: searchin [-i] [PHRASE] [DIR]"; return 0 ;;
      *) if [[ -z $phrase ]]; then phrase=$1; else dir=$1; fi; shift ;;
    esac
  done
  if [[ -z $phrase ]]; then
    read -r "phrase?Phrase to search for: " || return 1
    [[ -n $phrase ]] || return 1
    read -r "ans?Case sensitive? [Y/n]: "
    [[ $ans == [nN]* ]] && insensitive=1
  fi
  local -a gopts=(-R -n -F --null --binary-files=without-match --color=never)
  (( insensitive )) && gopts+=(-i)
  local c_found= c_phr= c_pos= c_dim= c_path= c_hit= c_txt= c_rst=
  if [[ -t 1 && -z ${NO_COLOR-} ]]; then
    c_found=$'\e[1m' c_phr=$'\e[33m' c_pos=$'\e[35m' c_dim=$'\e[2m'
    c_path=$'\e[38;5;208m' c_hit=$'\e[1;31m' c_txt=$'\e[0;31m' c_rst=$'\e[0m'
  fi
  setopt extended_glob
  local file rest line content pre qp=${(b)phrase}
  command grep "${gopts[@]}" -- "$phrase" "$dir" 2>/dev/null |
  while IFS= read -r -d '' file && IFS= read -r rest; do
    line=${rest%%:*} content=${rest#*:}
    content=${content//$'\t'/    }
    if (( insensitive )); then
      pre=${content%%(#i)${~qp}*}
      content=${content//(#bi)(${~qp})/${c_hit}${match[1]}${c_txt}}
    else
      pre=${content%%$phrase*}
      content=${content//$phrase/${c_hit}${phrase}${c_txt}}
    fi
    print -r -- "${c_found}Found ${c_phr}\"$phrase\"${c_rst} at ${c_pos}$(( $#pre + 1 )):$line${c_rst}"
    print -r -- "${c_dim}content=${c_txt}\"$content\"${c_rst}"
    print -r -- "${c_dim}file=${c_path}\"${file:A}\"${c_rst}"
    print
  done
  return 0
}

# hunt — interactive file-content hunter (glob, reader tool, keyword, optional action)
hunt() {
  emulate -L zsh
  setopt extended_glob
  local target tool key action file matches nfiles=0 nhits=0
  read -r "target?Target pattern (find glob, default: *): "
  : ${target:=*}
  read -r "tool?Reader tool (default: cat): "
  : ${tool:=cat}
  (( $+commands[$tool] || $+functions[$tool] )) || msh::warn "'$tool' not found, continuing anyway"
  read -r "key?Keyword to locate: "
  [[ -n $key ]] || { msh::err "hunt: a keyword is required"; return 1; }
  read -r "action?Post-match action (file appended; empty = none): "
  msh::info "hunt: keyword=[$key] target=[$target] tool=[$tool]"
  # Process substitution keeps the loop in this shell so the counters survive.
  while IFS= read -r file; do
    (( nfiles++ ))
    matches=$("$tool" "$file" 2>/dev/null | command grep -i -- "$key")
    [[ -n $matches ]] || continue
    (( nhits++ ))
    print -P "%F{red}${file//\%/%%}%f"
    print -P "%F{yellow}Matching lines:%f"
    print -r -- "$matches"
    print
    if [[ -n $action ]]; then
      print -P "%F{cyan}Executing:%f ${action//\%/%%} ${(q)file//\%/%%}"
      eval "$action ${(q)file}"
    fi
  done < <(find ${~target} -type f 2>/dev/null)
  msh::ok "hunt finished: $nfiles file(s) examined, matches in $nhits"
}

# lsk KEYWORD — find files/dirs whose name contains KEYWORD (colored absolute paths)
lsk() {
  [[ -n $1 ]] || { print -u2 "usage: lsk <keyword>"; return 2; }
  local item
  find "$PWD" -iname "*$1*" 2>/dev/null | while IFS= read -r item; do
    print -r -- $'\e[38;5;208m'"${item:h}"$'\e[0m - \e[32m'"${item:t}"$'\e[0m'
  done
}

# fopen [TERM] — fuzzy-pick a file whose name contains TERM and open it
fopen() {
  msh::need fzf xdg-open || return
  local file
  file=$(find . -type f -iname "*${1-}*" 2>/dev/null | fzf) || return 1
  xdg-open "$file" &>/dev/null &!
}

# fzx — fuzzy-pick a file (fd when available) and print its path
fzx() {
  msh::need fzf || return
  if (( $+commands[fd] )); then
    fd --type f --strip-cwd-prefix "$@" | fzf
  else
    find . -type f 2>/dev/null | fzf
  fi
}
