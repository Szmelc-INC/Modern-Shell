#!/usr/bin/env bash
# test-addons.sh — every addon must source silently (twice, so it is idempotent),
# exit 0, and give every alias/function a doc comment on the line directly above.
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
red=$'\e[1;31m' green=$'\e[1;32m' reset=$'\e[0m'
[[ -n ${NO_COLOR-} || ! -t 1 ]] && red='' green='' reset=''

for f in shell/addons/*.zsh; do
  name=$(basename "$f" .zsh)

  # 1. Silent, successful, idempotent load in a clean non-interactive zsh.
  out=$(zsh -f -c 'source shell/rc.d/00-init.zsh || exit 9; source "$1" || exit $?; source "$1"' _ "$f" 2>&1)
  rc=$?
  if (( rc != 0 )); then
    echo "${red}load${reset}  $name: exit $rc"; fail=1
  fi
  if [[ -n $out ]]; then
    echo "${red}noisy${reset} $name: output on source:"; printf '      %s\n' "$out" | head -5; fail=1
  fi

  # 2. Doc comment directly above every alias and function definition
  #    Heredoc bodies and internal `ns::helper` functions are skipped.
  awk -v name="$name" '
    heredoc != "" { if ($0 ~ "^[ \t]*" heredoc "[ \t]*$") heredoc = ""; prev = $0; next }
    {
      line = $0
      if (match(line, /<<-?[ \t]*["\x27]?[A-Za-z_]+["\x27]?/)) {
        tag = substr(line, RSTART, RLENGTH); gsub(/<<-?[ \t]*|["\x27]/, "", tag); heredoc = tag
      }
      if (line ~ /^[ \t]*alias[ \t]+[^ \t=]+=/ ||
          (line ~ /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)[ \t]*[{(]/ && line !~ /::/)) {
        if (prev !~ /^[ \t]*#/) { printf "undoc %s:%d: %s\n", name, NR, line; bad = 1 }
      }
      prev = line
    }
    END { exit bad }' "$f" || fail=1
done

(( fail )) && { echo "${red}addon tests failed${reset}"; exit 1; }
echo "${green}addon tests ok${reset}"
