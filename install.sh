#!/usr/bin/env bash
# install.sh — install or upgrade Modern Shell for the current user.
#
# Safe to re-run. Before touching anything it takes a snapshot of every path in
# shell/targets.list (see the `snapshot` addon), and it only ever writes to
# those paths. Your layer ($MSH_HOME/user) is created once and never overwritten.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MSH_HOME=${MSH_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/msh}
BIN_DIR=$HOME/.local/bin
VERSION=$(cat "$SRC/shell/VERSION")

YES=0 DRY=0 DEPS=1 NANO=1 TMUX=1 BINARY=1 CHSH=1

# ── Output ────────────────────────────────────────────────────────────────
if [[ -t 1 && -z ${NO_COLOR-} ]]; then
  B=$'\e[1m' DIM=$'\e[2m' R=$'\e[0m' BLUE=$'\e[1;34m' GREEN=$'\e[1;32m' YEL=$'\e[1;33m' RED=$'\e[1;31m' MAG=$'\e[1;35m'
else
  B='' DIM='' R='' BLUE='' GREEN='' YEL='' RED='' MAG=''
fi
info() { printf '%s::%s %s\n' "$BLUE" "$R" "$*"; }
ok()   { printf '%s✔%s %s\n' "$GREEN" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$YEL" "$R" "$*" >&2; }
die()  { printf '%s✘%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }
step() { printf '\n%s━━ %s%s\n' "$MAG" "$*" "$R"; }
ask()  { (( YES )) && return 0; local a; read -r -p "${YEL}?${R} $1 [Y/n] " a || return 1; [[ -z $a || $a == [yY]* ]]; }
run()  { if (( DRY )); then printf '%s  would run:%s %s\n' "$DIM" "$R" "$*"; else "$@"; fi; }

usage() {
  cat <<EOF
${B}${BLUE}Modern Shell${R} installer ${DIM}v$VERSION${R}

${B}USAGE${R}
  ./install.sh [options]

${B}OPTIONS${R}
  ${GREEN}-y, --yes${R}          answer yes to every question
  ${GREEN}-n, --dry-run${R}      show what would happen, change nothing
      ${GREEN}--no-deps${R}      skip the dependency check / package install
      ${GREEN}--no-nano${R}      do not install ~/.nanorc
      ${GREEN}--no-tmux${R}      do not install ~/.tmux.conf
      ${GREEN}--no-binary${R}    do not build/install the msh binary
      ${GREEN}--no-chsh${R}      never offer to make zsh the login shell
  ${GREEN}-h, --help${R}         this help

${B}WHAT IT DOES${R}
  1. checks dependencies (offers to install missing ones with pkexec)
  2. ${B}snapshot${R} of everything below → ~/.BACKUP/msh/<id>_pre-install
  3. deploys the framework to ${DIM}$MSH_HOME${R} (your user/ layer is kept)
  4. writes the ~/.zshrc loader stub, ~/.nanorc, ~/.tmux.conf
  5. builds ${B}msh${R} into ~/.local/bin + bash/zsh/fish completions

${B}ENVIRONMENT${R}
  MSH_HOME   install location (default: \${XDG_CONFIG_HOME:-~/.config}/msh)
  NO_COLOR   disable colors
EOF
}

while (( $# )); do
  case $1 in
    -y|--yes) YES=1 ;;
    -n|--dry-run) DRY=1 ;;
    --no-deps) DEPS=0 ;;
    --no-nano) NANO=0 ;;
    --no-tmux) TMUX=0 ;;
    --no-binary) BINARY=0 ;;
    --no-chsh) CHSH=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

# ── Target guard: every write must be inside shell/targets.list ────────────
mapfile -t TARGETS < <(grep -vE '^\s*(#|$)' "$SRC/shell/targets.list" | sed "s|^~/|$HOME/|")
MSH_HOME_DEFAULT=${XDG_CONFIG_HOME:-$HOME/.config}/msh
in_targets() {
  local p=$1 t
  for t in "${TARGETS[@]}"; do
    [[ $t == "$MSH_HOME_DEFAULT" ]] && t=$MSH_HOME
    [[ $p == "$t" || $p == "$t"/* ]] && return 0
  done
  return 1
}
put() { # put <src> <dest> [mode] — copy one file to a guarded destination
  in_targets "$2" || die "refusing to write outside targets.list: $2"
  run install -Dm"${3:-644}" "$1" "$2"
}

printf '%s\n' "${B}${BLUE}"'  ┏┳┓┏━┓╺┳┓┏━╸┏━┓┏┓╻   ┏━┓╻ ╻┏━╸╻  ╻  '
printf '%s\n' '  ┃┃┃┃ ┃ ┃┃┣╸ ┣┳┛┃┗┫   ┗━┓┣━┫┣╸ ┃  ┃  '
printf '%s\n' '  ╹ ╹┗━┛╺┻┛┗━╸╹┗╸╹ ╹   ┗━┛╹ ╹┗━╸┗━╸┗━╸'"${R}  ${DIM}v$VERSION${R}"
(( DRY )) && warn "dry run — nothing will be changed"

# ── 1. Dependencies ───────────────────────────────────────────────────────
step "1/5  Dependencies"
REQUIRED=(zsh git fzf zoxide)
OPTIONAL=(eza bat fd rg highlight tmux nano thefuck tldr delta go wl-copy xclip)
missing=()
for c in "${REQUIRED[@]}"; do
  if command -v "$c" >/dev/null; then printf '  %s✔%s %-10s %srequired%s\n' "$GREEN" "$R" "$c" "$DIM" "$R"
  else printf '  %s✘%s %-10s %srequired%s\n' "$RED" "$R" "$c" "$DIM" "$R"; missing+=("$c"); fi
done
for c in "${OPTIONAL[@]}"; do
  if command -v "$c" >/dev/null; then printf '  %s✔%s %-10s %soptional%s\n' "$GREEN" "$R" "$c" "$DIM" "$R"
  else printf '  %s·%s %-10s %soptional — missing%s\n' "$YEL" "$R" "$c" "$DIM" "$R"; missing+=("$c"); fi
done

pkg_name() { # map command → package name per package manager
  case $1:$2 in
    pacman:rg) echo ripgrep ;; pacman:delta) echo git-delta ;; pacman:wl-copy) echo wl-clipboard ;;
    apt:rg) echo ripgrep ;; apt:fd) echo fd-find ;; apt:delta) echo git-delta ;; apt:wl-copy) echo wl-clipboard ;; apt:go) echo golang ;;
    dnf:rg) echo ripgrep ;; dnf:fd) echo fd-find ;; dnf:delta) echo git-delta ;; dnf:wl-copy) echo wl-clipboard ;; dnf:go) echo golang ;;
    brew:rg) echo ripgrep ;; brew:delta) echo git-delta ;;
    *) echo "$2" ;;
  esac
}
if (( DEPS )) && (( ${#missing[@]} )); then
  pm=''
  for m in pacman apt dnf brew; do command -v $m >/dev/null && { pm=$m; break; }; done
  if [[ -n $pm ]]; then
    pkgs=()
    for c in "${missing[@]}"; do [[ $pm == brew && $c == wl-copy ]] && continue; pkgs+=("$(pkg_name $pm "$c")"); done
    if ask "Install ${#pkgs[@]} missing package(s) with $pm? (${pkgs[*]})"; then
      case $pm in
        pacman) run pkexec pacman -S --needed --noconfirm "${pkgs[@]}" || warn "some packages failed" ;;
        apt)    run pkexec apt-get install -y "${pkgs[@]}" || warn "some packages failed (eza/zoxide may need a newer repo or cargo)" ;;
        dnf)    run pkexec dnf install -y "${pkgs[@]}" || warn "some packages failed" ;;
        brew)   run brew install "${pkgs[@]}" || warn "some packages failed" ;;
      esac
    fi
  else
    warn "no supported package manager found — install manually: ${missing[*]}"
  fi
fi
command -v zsh >/dev/null || (( DRY )) || die "zsh is required"

# ── 2. Snapshot (always) ──────────────────────────────────────────────────
step "2/5  Snapshot of the current state"
if (( DRY )); then
  info "would snapshot: ${TARGETS[*]/#$HOME/~}"
else
  MSH_HOME=$MSH_HOME MSH_TARGETS=$SRC/shell/targets.list \
    zsh "$SRC/shell/addons/snapshot.zsh" create --label pre-install --reason "install v$VERSION" \
    || die "snapshot failed — aborting before any change"
fi

# ── 3. Framework ──────────────────────────────────────────────────────────
step "3/5  Framework → ${MSH_HOME/#$HOME/~}"
in_targets "$MSH_HOME" || die "MSH_HOME must be one of the targets: $MSH_HOME"
for d in rc.d addons conf functions bin completions; do
  [[ -d $SRC/shell/$d ]] || continue
  run rm -rf -- "${MSH_HOME:?}/$d"
  run mkdir -p -- "$MSH_HOME/$d"
  run cp -a -- "$SRC/shell/$d/." "$MSH_HOME/$d/"
done
for f in zshrc targets.list VERSION; do put "$SRC/shell/$f" "$MSH_HOME/$f"; done
(( DRY )) || printf '%s\n' "$SRC" > "$MSH_HOME/.source"
ok "framework v$VERSION deployed"

# User layer: create what is missing, never overwrite.
U=$MSH_HOME/user
run mkdir -p -- "$U/addons" "$U/functions" "$U/completions"
seed() { # seed <dest> <mode> <content>
  [[ -e $1 ]] && return 0
  if (( DRY )); then info "would create ${1/#$HOME/~}"; return 0; fi
  (umask 077; printf '%s\n' "$3" > "$1"); chmod "$2" "$1"
}
seed "$U/msh.conf" 644 "# Modern Shell settings — sourced early by rc.d/00-init.zsh (zsh syntax).
# MSH_ZINIT=1                 # 0 = no plugin manager (plain zsh + addons)
# MSH_ZINIT_AUTOINSTALL=1     # clone zinit on first start
# MSH_PROMPT=p10k             # p10k | minimal
# MSH_P10K_CONFIG=\$HOME/.p10k.zsh
# MSH_THEFUCK=1
# MSH_EXTERNAL_SECRETS=(\$HOME/.zsh/secure.zsh)   # read-only secret files, sourced last
# EDITOR=nano"
seed "$U/addons.state" 644 "# addon on/off overrides: name=on|off  (manage with: msh addon enable|disable)"
seed "$U/aliases.zsh" 644 "# Managed by msh (msh alias … or the TUI). Hand edits welcome — see docs/ADDON-SPEC.md."
seed "$U/env.zsh" 644 "# Managed by msh (msh env … or the TUI). Hand edits welcome — see docs/ADDON-SPEC.md."
seed "$U/secrets.zsh" 600 "# Managed by msh (msh secret … or the TUI). Mode 600 — never commit this file."
seed "$U/local.zsh" 644 "# Machine-specific shell config, sourced after everything else.
# Good place for things that only make sense on this computer, e.g.:
#   [[ -r ~/.config/zshrc.d/auto-Hypr.sh ]] && source ~/.config/zshrc.d/auto-Hypr.sh
#   export BROWSER=thorium"
(( DRY )) || chmod 600 "$U/secrets.zsh"

# ── 4. Dotfiles ───────────────────────────────────────────────────────────
step "4/5  Dotfiles"
stub="# ~/.zshrc — Modern Shell loader stub. Real config: ${MSH_HOME/#$HOME/\~}  (manage it with: msh)
# Your previous ~/.zshrc is in the pre-install snapshot: snapshot list / snapshot show 1
source \"\${MSH_HOME:-\${XDG_CONFIG_HOME:-\$HOME/.config}/msh}/zshrc\"

# Lines that other installers append below this one keep working."
if [[ -f $HOME/.zshrc ]] && grep -q 'Modern Shell loader stub' "$HOME/.zshrc"; then
  ok "~/.zshrc already is the msh loader stub (kept, including lines appended to it)"
else
  in_targets "$HOME/.zshrc" || die "guard"
  if (( DRY )); then info "would write ~/.zshrc stub"; else printf '%s\n' "$stub" > "$HOME/.zshrc"; fi
  ok "~/.zshrc → loader stub"
fi
if (( NANO )); then
  put "$SRC/configs/nano/nanorc" "$HOME/.nanorc"
  run mkdir -p -- "$HOME/.cache/nano/backups"
  ok "~/.nanorc"
fi
if (( TMUX )); then
  put "$SRC/configs/tmux/tmux.conf" "$HOME/.tmux.conf"
  ok "~/.tmux.conf"
fi

# ── 5. msh binary + completions ───────────────────────────────────────────
step "5/5  msh (CLI + TUI)"
MSH_BIN=''
if (( BINARY )); then
  if command -v go >/dev/null && [[ -f $SRC/go.mod ]]; then
    info "building msh with $(go version | awk '{print $3}')…"
    in_targets "$BIN_DIR/msh" || die "guard"
    run mkdir -p -- "$BIN_DIR"
    (cd "$SRC" && run go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$BIN_DIR/msh" ./cmd/msh) \
      && MSH_BIN=$BIN_DIR/msh && ok "msh → ~/.local/bin/msh"
  elif [[ -x $SRC/bin/msh ]]; then
    put "$SRC/bin/msh" "$BIN_DIR/msh" 755 && MSH_BIN=$BIN_DIR/msh && ok "msh (prebuilt) → ~/.local/bin/msh"
  else
    warn "Go not found and no prebuilt binary — skipping msh (install go and re-run)"
  fi
fi
[[ -z $MSH_BIN ]] && command -v msh >/dev/null && MSH_BIN=$(command -v msh)
if [[ -n $MSH_BIN && -x $MSH_BIN ]] && (( ! DRY )); then
  "$MSH_BIN" completion zsh > "$MSH_HOME/completions/_msh"
  bc=$HOME/.local/share/bash-completion/completions/msh
  mkdir -p "$(dirname "$bc")" && "$MSH_BIN" completion bash > "$bc"
  if command -v fish >/dev/null; then
    fc=$HOME/.config/fish/completions/msh.fish
    mkdir -p "$(dirname "$fc")" && "$MSH_BIN" completion fish > "$fc"
  fi
  ok "completions: zsh, bash$(command -v fish >/dev/null && echo ', fish')"
fi
# msh-session ships its zsh completion in shell/completions; bash/fish are generated.
if [[ -x $MSH_HOME/bin/msh-session ]] && command -v python3 >/dev/null && (( ! DRY )); then
  bc=$HOME/.local/share/bash-completion/completions/msh-session
  in_targets "$bc" || die "guard"
  mkdir -p "$(dirname "$bc")" && python3 "$MSH_HOME/bin/msh-session" completion bash > "$bc"
  if command -v fish >/dev/null; then
    fc=$HOME/.config/fish/completions/msh-session.fish
    in_targets "$fc" || die "guard"
    mkdir -p "$(dirname "$fc")" && python3 "$MSH_HOME/bin/msh-session" completion fish > "$fc"
  fi
fi

if (( CHSH )) && [[ ${SHELL##*/} != zsh ]] && command -v zsh >/dev/null; then
  ask "Make zsh your login shell? (chsh)" && run chsh -s "$(command -v zsh)" || true
fi

printf '\n%s✔ Modern Shell v%s installed.%s\n' "$GREEN" "$VERSION" "$R"
cat <<EOF
  ${B}next${R}  open a new terminal (or run: ${GREEN}exec zsh${R})
        ${GREEN}msh${R}                 TUI — addons, aliases, functions, secrets, dirs, snapshots
        ${GREEN}msh doctor${R}          check the installation
        ${GREEN}snapshot list${R}       your backups (the pre-install one is #1)
        ${GREEN}snapshot restore 1${R}  undo this install completely
EOF
