#!/usr/bin/env bash
# lint.sh — syntax-check every shell file and validate addon headers.
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
red=$'\e[1;31m' green=$'\e[1;32m' reset=$'\e[0m'
[[ -n ${NO_COLOR-} || ! -t 1 ]] && red='' green='' reset=''

for f in shell/zshrc shell/rc.d/*.zsh shell/addons/*.zsh; do
  if ! zsh -n "$f"; then
    echo "${red}syntax${reset} $f"; fail=1
  fi
done
for f in install.sh uninstall.sh tests/*.sh; do
  [[ -f $f ]] || continue
  bash -n "$f" || { echo "${red}syntax${reset} $f"; fail=1; }
done

# Addon header contract (docs/ADDON-SPEC.md).
for f in shell/addons/*.zsh; do
  name=$(basename "$f" .zsh)
  hdr=$(awk 'NR==1 && /^#!/ {next} /^#/ {print; next} {exit}' "$f")
  grep -q "^# NAME: $name\$" <<<"$hdr" || { echo "${red}header${reset} $f: NAME must be '$name'"; fail=1; }
  grep -q '^# DESC: .' <<<"$hdr"       || { echo "${red}header${reset} $f: missing DESC"; fail=1; }
  grep -q '^# TAGS: .' <<<"$hdr"       || { echo "${red}header${reset} $f: missing TAGS"; fail=1; }
  if grep -nE '^\s*(sudo|killall|exec )' "$f" >/dev/null; then
    echo "${red}rule${reset} $f: top-level sudo/killall/exec"; fail=1
  fi
  if grep -nE '(^|[^.])\bsudo\b' "$f" | grep -v '^\s*#' | grep -vE 'OMZP::sudo|# .*sudo' >/dev/null; then
    echo "${red}rule${reset} $f: uses sudo (use pkexec)"; fail=1
  fi
  if grep -n '/home/[a-z]' "$f" >/dev/null; then
    echo "${red}rule${reset} $f: hardcoded /home path"; fail=1
  fi
done

(( fail )) && { echo "${red}lint failed${reset}"; exit 1; }
echo "${green}lint ok${reset}"
