#!/usr/bin/env zsh
# NAME: pip-search
# DESC: Search PyPI from the terminal (pip search replacement) — needs a browser cookie in PIP_SEARCH_COOKIE
# TAGS: DEV, WEB
# DEP: curl, python3
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: pip-search requests
# EXAMPLE: pip-search --short http client
# | Ported from `pip-search.zsh`. PyPI's search page sits behind a Fastly
# | browser challenge, so a cookie from a real browser session is required.
# |
# | **Setup (once, and again whenever it expires):**
# | 1. Open https://pypi.org/search/?q=test in your browser.
# | 2. DevTools → Network → the `search` request → copy the `cookie:` header value.
# | 3. `msh secret add PIP_SEARCH_COOKIE` and paste it.
# |
# | The cookie is read from the environment at call time and never written to disk
# | by this addon.
# |
# | | Flag | Meaning |
# | |---|---|
# | | `-s, --short` | one line per package |
# | | `-n N` | show at most N results |

: ${PIP_SEARCH_UA:='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'}

# pip-search [-s] [-n N] QUERY... — search PyPI packages (needs PIP_SEARCH_COOKIE)
pip-search() {
  emulate -L zsh
  setopt pipefail
  local short=0 limit=0
  local -a rest
  while (( $# )); do
    case $1 in
      -s|--short) short=1 ;;
      -n) limit=${2:?pip-search -n N}; shift ;;
      -h|--help) print "usage: pip-search [-s|--short] [-n N] <query>"; return 0 ;;
      *) rest+=("$1") ;;
    esac
    shift
  done
  local query="${(j: :)rest}"
  [[ -n $query ]] || { msh::err "pip-search: give a query"; return 2; }
  msh::need curl python3 || return
  local cookie=${PIP_SEARCH_COOKIE:?set it with: msh secret add PIP_SEARCH_COOKIE}
  local color=0
  [[ -t 1 && -z ${NO_COLOR-} ]] && color=1

  local py
  py=$(cat <<'PY'
import sys, re, html
query, short, color, limit = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", int(sys.argv[4])
data = sys.stdin.read()
if "Client Challenge" in data or "_fs-ch-" in data:
    sys.exit(3)
def c(code):
    return code if color else ""
R, OR, ORB, CY, GR, GI, WH, GB = (c("\033[0m"), c("\033[38;5;208m"), c("\033[1;38;5;208m"), c("\033[1;36m"),
                                  c("\033[38;5;245m"), c("\033[3;38;5;245m"), c("\033[97m"), c("\033[1;32m"))
m = re.search(r"<strong>([^<]+)</strong>\s*(?:&nbsp;|\s)*projects", data)
count = m.group(1).strip() if m else None
mu = re.search(r'<ul[^>]*aria-label="Search results"[^>]*>(.*?)</ul>', data, re.S)
body = mu.group(1) if mu else ""
pkgs = []
for href, chunk in re.findall(r'<a class="package-snippet"[^>]*href="(/project/[^"]+/)"(.*?)</a>', body, re.S):
    nm = re.search(r'package-snippet__name">([^<]+)</span>', chunk)
    name = html.unescape(nm.group(1).strip()) if nm else href.strip("/").split("/")[-1]
    dt = re.search(r'datetime="(\d{4})-(\d{2})-(\d{2})', chunk)
    date = f"{dt.group(3)}/{dt.group(2)}/{dt.group(1)}" if dt else "--/--/----"
    dm = re.search(r'package-snippet__description">(.*?)</p>', chunk, re.S)
    desc = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", dm.group(1)))).strip() if dm else ""
    pkgs.append((name, date, desc))
if limit > 0:
    pkgs = pkgs[:limit]
out = [f'# Found: {ORB}{count or len(pkgs)}{R} packages for {GB}"{query}"{R}']
if not short:
    out.append("")
for i, (name, date, desc) in enumerate(pkgs, 1):
    if short:
        out.append(f"{OR}{i}.{R} {CY}{name}{R} {GR}-{R} {GI}{desc}{R}")
    else:
        d = f"{GR}/{R}".join(f"{WH}{p}{R}" for p in date.split("/"))
        out += [f"{OR}{i}.{R} {CY}{name}{R} {GR}/ [{R}{d}{GR}]{R}", f"{GI}> {desc}{R}", ""]
if not pkgs:
    out.append(f"{GR}(no packages){R}")
print("\n".join(out))
PY
)
  # The cookie header is fed through a pipe (-H @file) so it never appears in `ps`.
  curl -sS --compressed -A "$PIP_SEARCH_UA" \
    -H @<(print -r -- "cookie: $cookie") \
    -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    -H 'accept-language: en-US,en;q=0.9' \
    --get --data-urlencode "q=$query" -d 'o=' 'https://pypi.org/search/' 2>/dev/null |
    python3 -c "$py" "$query" $short $color $limit
  local rc=$?
  (( rc == 3 )) && msh::err "pip-search: the cookie expired (Fastly challenge). Refresh PIP_SEARCH_COOKIE."
  return rc
}
