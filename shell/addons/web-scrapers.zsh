#!/usr/bin/env zsh
# NAME: web-scrapers
# DESC: Pull text/URLs out of web pages, mirror JS-heavy sites with Playwright, grab a page's assets with wget
# TAGS: WEB, NETWORK
# DEP: curl, python3, node (optional), npm (optional), php (optional), wget (optional), chromium (optional)
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: texturl --all https://example.com
# EXAMPLE: texturl --render --format json --url https://example.com
# EXAMPLE: webscrape https://example.com
# EXAMPLE: webgrab example.com
# | Merged from `scrapers.zsh`, `webscraper.zsh`, `webscraper2.zsh` and the
# | `.zshrc` `webpack-getfiles`.
# |
# | | Command | What it does |
# | |---|---|
# | | `texturl [-a\|-t\|-u] [-r] [-f text\|json] [URL]` | readable text and/or every URL of a page |
# | | `webscrape URL` | full mirror of a rendered (SPA/SSR) site into `./<host>/` + `router.php` |
# | | `webgrab [URL]` | one-level wget of a page and its assets (images, css, js, fonts, media) |
# |
# | `webscrape` installs the Playwright npm package into a throw-away temp dir on
# | every run; Playwright caches Chromium in `~/.cache/ms-playwright` (~200 MB, first run only). The mirror script is embedded here; nothing is
# | fetched from third-party repos and nothing is cached in `/tmp`.
# | Serve the result with `cd <host> && php -S localhost:2137 router.php`.
# |
# | Python dependency: `python3 -m pip install --user beautifulsoup4`
# | (or `pacman -S python-beautifulsoup4`).

# texturl [-a|-t|-u] [-r] [-f text|json] [URL] — extract readable text and/or URLs from a page
texturl() {
  emulate -L zsh
  setopt pipefail
  local want_txt=1 want_url=0 render=0 format=text url=""
  while (( $# )); do
    case $1 in
      -a|--all)    want_txt=1 want_url=1 ;;
      -t|--txt)    want_txt=1 want_url=0 ;;
      -u|--url)    want_txt=0 want_url=1 ;;
      -r|--render) render=1 ;;
      -f|--format) format=$2; shift ;;
      -h|--help)
        print -r -- "usage: texturl [FLAGS] [URL]
  -a, --all       text + URLs
  -t, --txt       only text (default)
  -u, --url       only URLs
  -r, --render    let headless Chromium run the JS first
  -f, --format    text|json (default text)"
        return 0 ;;
      --) shift; url=${1-}; break ;;
      -*) msh::err "texturl: unknown flag $1"; return 2 ;;
      *)  url=$1 ;;
    esac
    shift
  done
  [[ -n $url ]] || read -r "url?URL: "
  [[ -n $url ]] || { msh::err "texturl: no URL"; return 1; }
  [[ $format == (text|json) ]] || { msh::err "texturl: --format must be text or json"; return 2; }
  msh::need curl python3 || return

  local browser=""
  if (( render )); then
    local b
    for b in chromium google-chrome google-chrome-stable brave thorium; do
      (( $+commands[$b] )) && { browser=$b; break; }
    done
    [[ -n $browser ]] || { msh::err "texturl: --render needs chromium/chrome/brave"; return 127; }
  fi

  local py
  py=$(cat <<'PY'
import sys, re, json
from urllib.parse import urljoin
try:
    from bs4 import BeautifulSoup
except Exception:
    sys.stderr.write("texturl: missing python package beautifulsoup4\n")
    sys.exit(127)
base, want_txt, want_url, fmt = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4]
html = sys.stdin.read()
soup = BeautifulSoup(html, "html.parser")
bt = soup.find("base", href=True)
if bt and bt.get("href"):
    base = urljoin(base, bt["href"])
for tag in soup(["script", "style"]):
    tag.decompose()
text_out = ""
if want_txt:
    text = soup.get_text("\n", strip=True)
    seen, extra = set(), []
    for el in soup.find_all(True):
        for k in ("alt", "title", "aria-label", "placeholder"):
            v = (el.get(k) or "").strip()
            if v and v not in seen:
                seen.add(v); extra.append(v)
    text_out = (text + ("\n" + "\n".join(extra) if extra else "")).strip()
urls = set()
def add(u):
    u = (u or "").strip().strip("\"'")
    if not u or u.startswith("#") or u.lower().startswith("javascript:"):
        return
    urls.add(u if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", u) else urljoin(base, u))
if want_url:
    for el in soup.find_all(True):
        for a in ("href", "src", "action", "poster", "cite", "longdesc", "data-href", "data-src"):
            if el.get(a):
                add(el.get(a))
        for part in (el.get("srcset") or "").split(","):
            if part.strip():
                add(part.split()[0])
        for m in re.findall(r"url\(([^)]+)\)", el.get("style") or "", flags=re.I):
            add(m)
    for m in soup.find_all("meta"):
        if (m.get("http-equiv") or "").lower() == "refresh":
            mm = re.search(r"url\s*=\s*(.+)$", m.get("content") or "", flags=re.I)
            if mm:
                add(mm.group(1))
    for m in re.findall(r"\bhttps?://[^\s<>()\"']+", html):
        add(m)
if fmt == "json":
    obj = {"url": base}
    if want_txt: obj["text"] = text_out
    if want_url: obj["urls"] = sorted(urls)
    print(json.dumps(obj, ensure_ascii=False))
else:
    if want_txt: print(text_out)
    if want_txt and want_url: print("\n---- URLs ----")
    if want_url: print("\n".join(sorted(urls)))
PY
)
  if (( render )); then
    "$browser" --headless --disable-gpu --dump-dom "$url" 2>/dev/null |
      python3 -c "$py" "$url" $want_txt $want_url $format
  else
    curl -fsSL --compressed "$url" | python3 -c "$py" "$url" $want_txt $want_url $format
  fi
}

# webscrape URL — mirror a rendered (JS) website into ./<host>/ with a php router
webscrape() {
  emulate -L zsh
  [[ -n ${1-} ]] || { print -u2 "usage: webscrape <URL>"; return 2; }
  msh::need node npm npx || return
  local url=$1 host=${${1#*://}%%/*}
  local outdir="$PWD/${host//:/_}"
  msh::info "Mirroring $url → $outdir/"
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/msh-webscrape.XXXXXX") || return 1
  {
    ( cd -- "$tmp" &&
      npm init -y >/dev/null 2>&1 &&
      npm install playwright --no-audit --no-fund --silent &&
      npx playwright install chromium ) || { msh::err "webscrape: playwright setup failed"; return 1; }
    cat > "$tmp/mirror.js" <<'JS'
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [url, outDir] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const page = await (await browser.newContext({ ignoreHTTPSErrors: true })).newPage();
  page.on('response', async (res) => {
    const u = res.url();
    if (!u.startsWith('http')) return;
    let p = new URL(u).pathname;
    if (p === '/' || p.endsWith('/')) p += 'index.html';
    const file = path.join(outDir, path.normalize(p).replace(/^(\.\.[\/\\])+/, ''));
    if (!file.startsWith(outDir)) return;
    try {
      const buf = await res.body();
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, buf);
    } catch (e) {}
  });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 120000 });
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(6000);
  fs.writeFileSync(path.join(outDir, 'index.html'), await page.content());
  await browser.close();
})();
JS
    ( cd -- "$tmp" && node mirror.js "$url" "$outdir" ) || { msh::err "webscrape: mirroring failed"; return 1; }
    cat > "$outdir/router.php" <<'PHP'
<?php
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
if ($uri === '/' || $uri === '') $uri = '/index.html';
$file = realpath(__DIR__ . $uri);
if ($file && str_starts_with($file, __DIR__) && is_file($file)) {
  $ct = [
    'css' => 'text/css', 'js' => 'application/javascript', 'json' => 'application/json',
    'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'gif' => 'image/gif',
    'svg' => 'image/svg+xml', 'webp' => 'image/webp', 'woff' => 'font/woff', 'woff2' => 'font/woff2',
  ][strtolower(pathinfo($file, PATHINFO_EXTENSION))] ?? 'text/html; charset=utf-8';
  header('Content-Type: ' . $ct);
  readfile($file);
  exit;
}
if (strpos($uri, '/api/') === 0) { header('Content-Type: application/json'); echo '{}'; exit; }
header('Content-Type: text/html; charset=utf-8');
readfile(__DIR__ . '/index.html');
PHP
    msh::ok "Mirror ready: $outdir"
    msh::info "serve it: cd ${(q)outdir} && php -S localhost:2137 router.php"
  } always {
    rm -rf -- "$tmp"
  }
}

# webgrab [URL] — download a page plus its direct assets (one level, wget)
webgrab() {
  msh::need wget || return
  local url=${1-}
  [[ -n $url ]] || read -r "url?URL: "
  [[ -n $url ]] || { msh::err "webgrab: no URL"; return 1; }
  [[ $url == http* ]] || url="https://$url"
  wget -e robots=off -r -l1 -H -np -k -p \
    -A jpg,jpeg,png,gif,webp,js,css,html,htm,svg,woff,woff2,ttf,eot,otf,mp3,mp4,webm \
    -U "Mozilla/5.0" -- "$url"
}

# Old name of webgrab (from .zshrc)
alias webpack-getfiles='webgrab'
