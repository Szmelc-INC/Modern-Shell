#!/usr/bin/env zsh
# NAME: skynet
# DESC: Environment for the SKYNET AI project (paths for history, cache, logs, settings, bin, assets)
# TAGS: AI
# DEP: zsh
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: skynet-env
# | Ported from `skynet.zsh` ("SKYNET AI — command center of the universe, v1").
# |
# | Exports `SKYNET_PATH` (default `/var/lib/skynet`) and the derived
# | `SKYNET_HISTORY`, `SKYNET_CACHE`, `SKYNET_LOGS`, `SKYNET_SETTINGS`,
# | `SKYNET_BIN`, `SKYNET_ASSETS`, and puts `$SKYNET_BIN` on `PATH` (deduplicated,
# | only when the directory exists).
# |
# |
# | | Command / variable | Meaning |
# | |---|---|
# | | `skynet-env` | print every `SKYNET_*` variable |
# | | `SKYNET_PATH` | project root (default `/var/lib/skynet`); the others derive from it |
# |
# | Fixed while porting: PATH got `$SKYNET_BIN/bin` (= `…/bin/bin`) instead of `$SKYNET_BIN`.

: ${SKYNET_PATH:=/var/lib/skynet}
export SKYNET_PATH
export SKYNET_HISTORY=${SKYNET_HISTORY:-$SKYNET_PATH/history}
export SKYNET_CACHE=${SKYNET_CACHE:-$SKYNET_PATH/cache}
export SKYNET_LOGS=${SKYNET_LOGS:-$SKYNET_PATH/logs}
export SKYNET_SETTINGS=${SKYNET_SETTINGS:-$SKYNET_PATH/settings}
export SKYNET_BIN=${SKYNET_BIN:-$SKYNET_PATH/bin}
export SKYNET_ASSETS=${SKYNET_ASSETS:-$SKYNET_PATH/assets}
[[ -d $SKYNET_BIN ]] && path=("$SKYNET_BIN" $path)

# skynet-env — print every SKYNET_* variable
skynet-env() {
  local v
  for v in ${(o)${(M)${(k)parameters}:#SKYNET_*}}; do printf '%-16s %s\n' $v "${(P)v}"; done
}
