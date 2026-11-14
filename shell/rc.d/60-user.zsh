# 60-user.zsh — user-managed items (msh TUI / `msh alias|env|secret|func`).
# Loaded after addons, so a user alias/function with the same name wins.

[[ -d $MSH_USER ]] || return 0

# Env and secrets first: aliases/functions may reference them.
[[ -r "$MSH_USER/env.zsh"     ]] && source "$MSH_USER/env.zsh"
[[ -r "$MSH_USER/secrets.zsh" ]] && source "$MSH_USER/secrets.zsh"
[[ -r "$MSH_USER/aliases.zsh" ]] && source "$MSH_USER/aliases.zsh"

() {
  local f
  for f in "$MSH_USER"/functions/*.zsh(N); do
    source "$f"
  done
}
