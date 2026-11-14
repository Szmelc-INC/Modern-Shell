# 70-integrations.zsh — external tool init. zoxide MUST be last (it owns `cd`).

# fzf: key bindings (Ctrl+T files, Ctrl+R history, Alt+C dirs) + completion.
if (( $+commands[fzf] )); then
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git'
    export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
    export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'
  fi
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=50% --layout=reverse --border=rounded --info=inline \
--color=fg:#cdd6f4,hl:#7aa2f7,fg+:#ffffff,bg+:#232339,hl+:#b4befe,info:#f9e2af,prompt:#a6e3a1,pointer:#f38ba8,marker:#a6e3a1,spinner:#f5e0dc,header:#6c7086,border:#313244}"
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null || head -200 {}'"
  export FZF_ALT_C_OPTS="--preview 'eza -1 --color=always --icons=auto {} 2>/dev/null || ls -1 --color=always {}'"
  if [[ -o zle && -t 0 ]] && fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  elif [[ -o zle && -t 0 && -r ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
  fi
fi

# thefuck: defined lazily — `eval $(thefuck --alias)` costs ~200ms per shell.
if (( MSH_THEFUCK )) && (( $+commands[thefuck] )); then
  # fuck — correct the previous command (thefuck, loaded on first use)
  fuck() {
    unfunction fuck
    eval "$(thefuck --alias)"
    fuck "$@"
  }
fi

# zoxide replaces cd (`cd` = smart jump, `cdi` = interactive fzf picker).
# Do NOT define a cd() function or alias after this line anywhere.
if (( $+commands[zoxide] )); then
  export _ZO_DOCTOR=0
  eval "$(zoxide init --cmd cd zsh)"
  alias z='cd' zi='cdi'
fi
