# 30-history.zsh — history behavior only.

HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000
SAVEHIST=$HISTSIZE
setopt append_history share_history extended_history \
       hist_ignore_space hist_ignore_dups hist_ignore_all_dups \
       hist_save_no_dups hist_find_no_dups hist_reduce_blanks hist_verify
# Commands starting with a space are never saved — use that for anything secret.
