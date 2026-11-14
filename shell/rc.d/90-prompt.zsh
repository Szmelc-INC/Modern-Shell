# 90-prompt.zsh — prompt: Powerlevel10k (minimal config) or a built-in fallback.

if [[ $MSH_PROMPT == p10k ]] && (( $+functions[p10k] || $+functions[prompt_powerlevel10k_setup] )); then
  [[ -r $MSH_P10K_CONFIG ]] && source "$MSH_P10K_CONFIG"
  return 0
fi

# Fallback: minimal two-color prompt with git branch, no plugins required.
autoload -Uz vcs_info add-zsh-hook
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{103}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{103}%b%f %F{208}(%a)%f'
add-zsh-hook precmd vcs_info
setopt prompt_subst
PROMPT='%F{39}%(4~|…/%3~|%~)%f${vcs_info_msg_0_} %(?.%F{76}.%F{196})❯%f '
RPROMPT='%(?..%F{196}%?%f)'
