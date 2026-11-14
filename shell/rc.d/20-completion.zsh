# 20-completion.zsh — completion engine + styling. compinit runs exactly once.

autoload -Uz compinit
_msh_zcd="$MSH_CACHE/zcompdump-${ZSH_VERSION}"
# Rebuild the dump only if it is missing or older than 24h, else load cached.
if [[ ! -s $_msh_zcd || -n $_msh_zcd(#qN.mh+24) ]]; then
  compinit -i -d "$_msh_zcd"
else
  compinit -C -d "$_msh_zcd"
fi
unset _msh_zcd
(( $+functions[zinit] )) && zinit cdreplay -q   # replay compdefs collected by blockf

# Colors for completion lists (same palette as ls/eza).
if [[ -z $LS_COLORS ]] && (( $+commands[dircolors] )); then
  if [[ -r $HOME/.dircolors ]]; then eval "$(dircolors -b "$HOME/.dircolors")"
  else eval "$(dircolors -b)"; fi
fi

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=* r:|=*'  # case-insensitive + partial
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no                                  # fzf-tab owns the menu
zstyle ':completion:*' verbose yes
zstyle ':completion:*' group-name ''
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$MSH_CACHE/zcompcache"
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false

# fzf-tab: previews for directories, files, processes and env vars.
_msh_ls_preview='eza -1 --color=always --icons=auto $realpath 2>/dev/null || ls -1 --color=always $realpath'
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' fzf-flags --height=60% --border=rounded
zstyle ':fzf-tab:complete:cd:*'         fzf-preview $_msh_ls_preview
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview $_msh_ls_preview
zstyle ':fzf-tab:complete:(nano|bat|cat|less|vim|nvim):*' fzf-preview \
  '[[ -d $realpath ]] && { eza -1 --color=always $realpath 2>/dev/null || ls -1 --color=always $realpath; } || bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -200 $realpath'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview '[[ $group == "[process ID]" ]] && ps -o pid,user,%cpu,%mem,cmd -p $word'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview 'echo ${(P)word}'
unset _msh_ls_preview
