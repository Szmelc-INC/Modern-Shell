#!/usr/bin/env zsh
# NAME: patterns
# DESC: Named regex library (*_PATTERN env vars) with `pattern` to list, grep and extract URLs, emails, IPs, UUIDs
# TAGS: SEARCH, DEV
# DEP: grep
# DEFAULT: on
# VER: 1.1
# DEV: SilverX
# EXAMPLE: pattern                      (list all patterns)
# EXAMPLE: pattern URL page.html        (lines containing a URL)
# EXAMPLE: curl -s example.com | pattern URL -x   (extract the URLs)
# | Ported from `~/.zsh/auto/pattern.zsh` + `auto/patterns.zsh`.
# |
# | Any environment variable named `NAME_PATTERN` (POSIX ERE) becomes a pattern.
# | Add your own in `msh env` or `user/env.zsh`, e.g. `export HASH_PATTERN='[[:xdigit:]]{40}'`.
# |
# | | Command | What it does |
# | |---|---|
# | | `pattern` | list every defined pattern |
# | | `pattern NAME` | print the regex |
# | | `pattern NAME [FILE...]` | print matching lines (stdin when no file) |
# | | `pattern NAME -x [FILE...]` | print every match, one per line |
# |
# | Shipped: `URL`, `EMAIL`, `IP`, `IP6`, `UUID`, `MAC`, `HEXCOLOR`, `SEMVER`.
# | Existing values are never overwritten.

: ${URL_PATTERN:='https?://[[:alnum:]._-]+(\.[[:alpha:]]{2,})+(:[0-9]+)?(/[[:alnum:]._%~!$&'\''()*+,;=:@/?#-]*)?'}
: ${EMAIL_PATTERN:='[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}'}
: ${IP_PATTERN:='([0-9]{1,3}\.){3}[0-9]{1,3}'}
: ${IP6_PATTERN:='([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}'}
: ${UUID_PATTERN:='[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}'}
: ${MAC_PATTERN:='([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'}
: ${HEXCOLOR_PATTERN:='#[[:xdigit:]]{6}([[:xdigit:]]{2})?'}
: ${SEMVER_PATTERN:='v?[0-9]+\.[0-9]+\.[0-9]+(-[[:alnum:].-]+)?'}
export URL_PATTERN EMAIL_PATTERN IP_PATTERN IP6_PATTERN UUID_PATTERN MAC_PATTERN HEXCOLOR_PATTERN SEMVER_PATTERN

# pattern [NAME [-x] [FILE...]] — list, show, grep or extract a named *_PATTERN regex
pattern() {
  emulate -L zsh
  local -a available
  available=(${(o)${${(M)${(k)parameters}:#*_PATTERN}%_PATTERN}})
  if (( ! $# )); then
    (( $#available )) || { print "No *_PATTERN variables are defined."; return 0; }
    print "Available patterns:"
    local p val
    for p in $available; do
      val=${(P)${:-${p}_PATTERN}}
      printf '  %-12s  %s\n' "$p" "${val[1,72]}${val[73]:+…}"
    done
    return 0
  fi
  local name=$1; shift
  local var="${name:u}_PATTERN"
  if [[ -z ${(P)var-} ]]; then
    msh::err "pattern '$name' is not defined"
    print -u2 "available: ${available[*]:-none}"
    return 1
  fi
  local regex=${(P)var}
  (( $# )) || { print -r -- "$regex"; return 0; }
  local mode=match
  local -a files
  while (( $# )); do
    case $1 in
      -x|--extract) mode=extract ;;
      -*) msh::err "pattern: unknown option $1 (supported: -x/--extract)"; return 2 ;;
      *) files+=("$1") ;;
    esac
    shift
  done
  if [[ $mode == match ]]; then
    command grep -E -- "$regex" "${files[@]}"
  else
    command grep -Eo -- "$regex" "${files[@]}"
  fi
}
