#!/usr/bin/env zsh
# NAME: proxy-tools
# DESC: Find working free proxies (proxyping), then use the fastest one for a command or the whole shell
# TAGS: NETWORK, SECURITY
# DEP: bash, curl, xargs, awk
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: proxyping -j 100 -w 10
# EXAMPLE: proxy-run curl -s ifconfig.me
# EXAMPLE: proxy-on ; proxy-off
# | Ported from `proxyping.sh`. The scanner itself is the executable
# | `shell/bin/proxyping` (bash, installed to `$MSH_HOME/bin`, which is on `PATH`).
# |
# | | Command | What it does |
# | |---|---|
# | | `proxyping [-o FILE] [-i FILE] [-j N] [-n N] [-w SEC] [-a]` | test a public proxy list, save working ones sorted by delay to `$PROXYPING_OUT` |
# | | `proxy-list [N]` | show the N fastest saved proxies (default 10) |
# | | `proxy-pick [N]` | print the N-th fastest proxy URL (default 1) |
# | | `proxy-run CMD...` | run CMD with `http(s)_proxy`/`all_proxy` set to the fastest proxy |
# | | `proxy-on [N]` / `proxy-off` | export / unset the proxy variables in this shell |
# |
# | **Free public proxies are untrusted:** never send credentials or anything
# | private through them. `PROXYPING_OUT` defaults to `~/.cache/msh/proxy.list`.
# | Fixed while porting: the help said `-j` defaults to 50 while the code used 2000.

: ${PROXYPING_OUT:=${XDG_CACHE_HOME:-$HOME/.cache}/msh/proxy.list}
export PROXYPING_OUT
typeset -g MSH_PROXYPING_BIN=${${(%):-%x}:A:h:h}/bin/proxyping

# proxyping [opts] — scan a public proxy list (see `proxyping -h`)
proxyping() {
  local bin=${commands[proxyping]:-$MSH_PROXYPING_BIN}
  [[ -f $bin ]] || { msh::err "proxyping script not found ($MSH_PROXYPING_BIN)"; return 127; }
  bash "$bin" "$@"
}

# proxy-list [N] — show the N fastest saved proxies
proxy-list() {
  [[ -s $PROXYPING_OUT ]] || { msh::warn "no proxy list yet, run proxyping"; return 1; }
  head -n "${1:-10}" -- "$PROXYPING_OUT"
}

# proxy-pick [N] — print the URL of the N-th fastest saved proxy
proxy-pick() {
  [[ -s $PROXYPING_OUT ]] || { msh::warn "no proxy list yet, run proxyping"; return 1; }
  sed -n "${1:-1}{s/ .*//;p;q}" -- "$PROXYPING_OUT"
}

# proxy-run CMD... — run one command through the fastest saved proxy
proxy-run() {
  local p; p=$(proxy-pick) || return
  http_proxy=$p https_proxy=$p HTTP_PROXY=$p HTTPS_PROXY=$p all_proxy=$p ALL_PROXY=$p "$@"
}

# proxy-on [N] — export proxy variables for the N-th fastest proxy in this shell
proxy-on() {
  local p; p=$(proxy-pick "${1:-1}") || return
  export http_proxy=$p https_proxy=$p HTTP_PROXY=$p HTTPS_PROXY=$p all_proxy=$p ALL_PROXY=$p
  msh::ok "proxy on: $p"
}

# proxy-off — unset all proxy variables
proxy-off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
  msh::ok "proxy off"
}
