# 10-zinit.zsh — plugin manager + declarations. Disable with MSH_ZINIT=0.

(( MSH_ZINIT )) || return 0

ZINIT_HOME="${ZINIT_HOME:-$XDG_DATA_HOME/zinit/zinit.git}"
if [[ ! -r "$ZINIT_HOME/zinit.zsh" ]]; then
  (( MSH_ZINIT_AUTOINSTALL )) && (( $+commands[git] )) || return 0
  mkdir -p -- "${ZINIT_HOME:h}"
  git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" >/dev/null 2>&1 \
    || { msh::warn "zinit: clone failed (offline?) — plugins skipped this session"; return 0; }
fi
source "$ZINIT_HOME/zinit.zsh"

# Theme — loaded immediately (instant prompt already painted).
[[ $MSH_PROMPT == p10k ]] && { zinit ice depth=1; zinit light romkatv/powerlevel10k; }

# Order matters (see docs/ADDON-SPEC.md → Load order):
#   compinit (20-completion, synchronous) → fzf-tab → completions
#   → fast-syntax-highlighting → autosuggestions (last widget wrapper).
zinit ice wait lucid;                               zinit light Aloxaf/fzf-tab
zinit ice wait lucid blockf;                        zinit light zsh-users/zsh-completions
zinit ice wait lucid;                               zinit light zdharma-continuum/fast-syntax-highlighting
zinit ice wait lucid atload'_zsh_autosuggest_start'; zinit light zsh-users/zsh-autosuggestions

# Oh-My-Zsh snippets (declarative libs).
zinit snippet OMZP::git
zinit snippet OMZP::sudo                 # Esc Esc prefixes the line with sudo
(( $+commands[pacman] )) && zinit snippet OMZP::archlinux
zinit snippet OMZP::command-not-found
