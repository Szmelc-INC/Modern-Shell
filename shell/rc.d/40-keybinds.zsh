# 40-keybinds.zsh — bindkey only.

bindkey -e                                   # emacs mode
bindkey '^p' history-search-backward         # Ctrl+P: previous match of typed prefix
bindkey '^n' history-search-forward          # Ctrl+N: next match of typed prefix
bindkey '^[w' kill-region                    # Alt+W: cut region
bindkey '^[[1;5C' forward-word               # Ctrl+→
bindkey '^[[1;5D' backward-word              # Ctrl+←
bindkey '^[[H' beginning-of-line             # Home
bindkey '^[[F' end-of-line                   # End
bindkey '^[[3~' delete-char                  # Delete
bindkey '^H' backward-kill-word              # Ctrl+Backspace

# Ctrl+X Ctrl+E: edit the current command line in $EDITOR
autoload -Uz edit-command-line && zle -N edit-command-line
bindkey '^x^e' edit-command-line
