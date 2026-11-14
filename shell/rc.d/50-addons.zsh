# 50-addons.zsh — source every enabled addon (shipped + user, user wins by name).
#
# Enabled = `name=on|off` in $MSH_USER/addons.state, else the addon's
# `# DEFAULT:` header (on when absent). See docs/ADDON-SPEC.md.

# msh::addon_default <file> — print the DEFAULT header value (on|off)
msh::addon_default() {
  local line
  while IFS= read -r line; do
    [[ $line == '#!'* ]] && continue
    [[ $line == \#* ]] || break
    if [[ $line == '# DEFAULT:'* ]]; then
      line=${${line#'# DEFAULT:'}// /}
      print -r -- ${line:l}
      return
    fi
  done < "$1"
  print on
}

# msh::addon_enabled <name> <file> — 0 when the addon should be sourced
msh::addon_enabled() {
  local state=${MSH_ADDON_STATE[$1]-}
  [[ -z $state ]] && state=$(msh::addon_default "$2")
  [[ $state == on ]]
}

typeset -gA MSH_ADDON_STATE MSH_ADDON_FILES
MSH_ADDON_STATE=() MSH_ADDON_FILES=()
if [[ -r "$MSH_USER/addons.state" ]]; then
  () {
    local line
    while IFS= read -r line; do
      [[ $line == [a-z0-9]*=* ]] || continue
      MSH_ADDON_STATE[${line%%=*}]=${${line#*=}// /}
    done < "$MSH_USER/addons.state"
  }
fi

() {
  local f
  for f in "$MSH_HOME"/addons/*.zsh(N) "$MSH_USER"/addons/*.zsh(N); do
    MSH_ADDON_FILES[${f:t:r}]=$f      # user dir comes second, so it overrides
  done
}

typeset -ga MSH_ADDONS_LOADED
MSH_ADDONS_LOADED=()
() {
  local name
  for name in ${(ok)MSH_ADDON_FILES}; do
    msh::addon_enabled "$name" "$MSH_ADDON_FILES[$name]" || continue
    source "$MSH_ADDON_FILES[$name]"
    MSH_ADDONS_LOADED+=("$name")
  done
}
