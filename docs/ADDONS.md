# Modern Shell — addon catalog

Every addon lives in `shell/addons/<name>.zsh` and follows
[ADDON-SPEC.md](ADDON-SPEC.md). Toggle with `msh addon on|off <name>` (or the
TUI); changes apply to new shells (`reload`). Each addon's `# |` header holds
the full help with a usage table (F1 in the TUI).

Defaults: **on** = broadly useful and safe; **off** = personal, heavy, niche,
needs keys/cookies, or talks to third-party services.

| Addon | Default | Tags | What it gives (main commands) | Ported from |
|---|---|---|---|---|
| `core-aliases` | on | CORE, FILES, EYECANDY | `ls`/`ll`/`la`/`lt` (eza), highlighted `cat`, colored grep/diff/ip, `reload` | (shipped) |
| `snapshot` | on | CORE, SYSTEM, SECURITY | `snapshot create/list/diff/restore/rm/prune` | (shipped) |
| `session` | on | SYSTEM, PROCESS | `sess save/restore/switch/list/show/diff` — desktop session snapshots via `msh-session` (Hyprland + UWSM; windows, apps, unsaved data), see [SESSIONS.md](SESSIONS.md) | (shipped) |
| `msh` | on | CORE | `msh` wrapper (TUI directory jumps `cd` your shell), `msh-snaps`, `msh-edit-local`, `msh-edit-conf` | (shipped) |
| `archives` | on | FILES | `extract [-d DIR] [-l]` (tar.*, zip, 7z, rar, gz, xz, zst, deb, rpm…), `archivize` (7z/zip/rar, password, hidden names, wizard) | ZRC `extract-archives`, `.zshrc` `extract`, `archivize.zsh` |
| `clipboard` | on | CLIPBOARD, CORE | `copy`, `copyf`, `paste`, `copy-path`, `clipboard-backend` — wl-copy → xclip → xsel → OSC 52 | ZRC `copy-paste`, `copy-file-contents`, `.zshrc` copy/paste |
| `colorized-man` | on | EYECANDY, CORE | `LESS_TERMCAP_*` colors, `GROFF_NO_SGR`, optional bat `MANPAGER` (`MSH_MAN_BAT=1`), `manc` | ZRC `colorized-man`, `.zshrc` man block |
| `eyecandy` | on | EYECANDY, FUN | `clock`, `ascii-fonts`, `typecat`, `drzewko`, `RGB1`, `BOX1`, `midnight` + `MIDNIGHT_*` palette | ZRC `cli-clock`, `ascii-fonts`, `.zshrc` clock/typecat/RGB1/BOX1/palette, `drzewko.zsh` |
| `file-tools` | on | FILES | `dedupe`, `renum`, `compare-lines`, `bin2txt`, `newf` | `dedupe.sh`, `renumerate.zsh`, `compare.zsh`, `binary.zsh`, `.zshrc` `newf` |
| `listing` | on | FILES, EYECANDY | `lsf`, `recent-file`, `lsdirs`, `les`, `lez`, `lezz`, `diskspace` | `ls-tools.zsh`, `files.zsh`, ZRC `list-recent-files`, `better-less`, `disk-usage-alias` |
| `logic` | on | DEV, FILES | `rng`, `rngnum`/`RNG`, `each`, `eachfile`, Ctrl-J `${*}` → for-loop | `logic.zsh`, `.zshrc` `rng`/`eachfile` |
| `media` | on | MEDIA, FILES | `unwebp`, `makeclip`, `screenshotd`, `tidy-media` | ZRC `unwebp`, `tidy-media`, `.zshrc` `unwebp`/`makeclip`, `screenshot.zsh` |
| `navigation` | on | NAVIGATION, FILES | `..`, `...`, `....`, `up N`, `mkcd`, `fsearch`, `cdf` (never redefines `cd`) | ZRC `lazy-cd`, `mkcd`, `.zshrc` `mkcd`, `test.zsh` `fsearch` |
| `net-pack` | on | NETWORK, WEB | `ipinfo`, `ip4ext`, `iplocal`, `ports`, `gateway`, `dns`, `mac`, `tcpd`, `sslcheck`, `weather`, `serve`, `trashupload`… | ZRC `net-pack`, `weather`, `python-http-server`, `.zshrc` `weather`, `trashupload.zsh` |
| `patterns` | on | SEARCH, DEV | `pattern [NAME [-x] FILE…]` + `URL/EMAIL/IP/IP6/UUID/MAC/HEXCOLOR/SEMVER_PATTERN` | `auto/pattern.zsh`, `auto/patterns.zsh` |
| `proc-tools` | on | PROCESS, SYSTEM | `stray`/`strays`/`slay`, `nohups`, `killem`, `pauseem`, `resumeem`, `pswide`, `pspwd`, `psport`, `ps-c`, `timer` | `stray.zsh` (= ZRC `stray`), `proc_tools.zsh`, `greps.zsh` (ps part), ZRC `silent-nohup`, `command-timer` |
| `quick-notes` | on | FILES, CORE | `note`, `notes [-g\|-e\|-t]` | ZRC `quick-notes` |
| `search` | on | SEARCH, FILES | `searchin`, `hunt`, `lsk`, `ffind`, `dfind`, `fopen`, `fzx`, `grepi`, `grepc` | `greps.zsh`, `greps2.zsh`, `list.zsh`, ZRC `grep-plus`, `find-*`, `.zshrc` `fzx` |
| `tmux-control` | on | TMUX, PROCESS | `tx-ls`, `tx-send`, `tx-run`, `tx-stop`, `tx-suspend`, `tx-pause`, `tx-unpause`, `tx-focus`, `tx-split`, `tx-close`, `tx-res` (target a pane or `ALL`) | `~/.tmuxrc` |
| `utils` | on | CORE, DEV | `countdown`, `remindme`, `jsonp`, `calh`, `syscheck`, `e`, `unsource`, `listrc`, empty `PROMPT_EOL_MARK` | ZRC `testrc`, `unsource`, `prompt-eol`, `aliases.zsh` |
| `ytdlp` | on | MEDIA, WEB | `ytw` (audio), `ytm` (video); URL from args or clipboard | `ytdlp.zsh` |
| `ai-tools` | off | AI | `sgpt` (Gemini key rotation), `gemini-ping`, `ejaj`, `jimmy`, `antigravity` | `shellgpt.zsh`, `llm.zsh`, `ejaj.zsh`, `jimmy.zsh` |
| `cookies` | off | WEB, SECURITY | `cookies -b BROWSER [-o PATH]` → private Netscape cookies.txt | `cookies.zsh` |
| `fun` | off | FUN | `joke`, `inspire`, `wisdom`, `mecho`, `remoji`, `wtf`, `bored` | ZRC `testrc` |
| `gpu-env` | off | AI, SYSTEM | `ROCM_PATH`, `HIP_VISIBLE_DEVICES`, `OLLAMA_MODELS`, `gpu-env` | `GPU.zsh`, `ollama.zsh` |
| `hypr-tools` | off | SYSTEM | `fix-xdg-portal`, `rbar`, `fnmode`, `paint` | `fix-xdg-portal.zsh`, `keyboard.zsh`, `.zshrc` `rbar`/`paint` |
| `pip-search` | off | DEV, WEB | `pip-search [-s] [-n N] QUERY` (needs `PIP_SEARCH_COOKIE`) | `pip-search.zsh` |
| `proxy-tools` | off | NETWORK, SECURITY | `proxyping` (script in `shell/bin/`), `proxy-list`, `proxy-pick`, `proxy-run`, `proxy-on`, `proxy-off` | `proxyping.sh` |
| `qemu` | off | SYSTEM, DEV | `qemu-test ISO [...]`, `qemu-test-ls`, `qemu-test-rm` | `qemu.zsh` |
| `skynet` | off | AI | `SKYNET_*` paths + `PATH`, `skynet-env` | `skynet.zsh` |
| `suno` | off | MEDIA, WEB, FUN | `suno [URL] [-f FMT] [-o DIR] [-n NAME]` | `SUNO.zsh` |
| `tmux-autostart` | off | TMUX | every interactive terminal starts in a new tmux session (acts on source by design; `NO_TMUX=1` skips) | `tmux.zsh` |
| `web-scrapers` | off | WEB, NETWORK | `texturl`, `webscrape` (Playwright mirror), `webgrab` | `scrapers.zsh`, `webscraper.zsh`, `webscraper2.zsh`, `.zshrc` `webpack-getfiles` |

## Secrets used by addons

Addons never contain credentials; they read these at call time. Store them
with `msh secret add NAME`.

| Variable | Addon | Purpose |
|---|---|---|
| `GEMINI_API_KEY`, `GEMINI_API_1` … `GEMINI_API_20` | `ai-tools` | keys rotated by `sgpt`, checked by `gemini-ping` |
| `PIP_SEARCH_COOKIE` | `pip-search` | browser cookie that passes PyPI's search challenge |

## Not ported

| Source | Why |
|---|---|
| `suno.zsh` (`wget-suno`) | needed a pasted browser cookie; `SUNO.zsh`'s cookie-free `suno` replaces it |
| `webscraper.zsh` (`wscr`) | ran a privileged `pacman` on every call; `webscraper2` logic kept as `webscrape` |
| `highlight.zsh` | redirects all stdout with `exec` on source |
| `.zshrc` `rename_files` | one-off regex for a specific set of files |
| `.zshrc` `cat` / `ls` / `histall` / `c` / `q` / `paru` / `yay` | already provided by `core-aliases` |
| `.zshrc` `FZF_DEFAULT_COMMAND` | already set by `rc.d/70-integrations.zsh` |
| ZRC `reload-rc`, `current-shell-rc` | `reload` (core-aliases) and `SHRC` (rc.d/00-init) cover them |
| ZRC `ssh-destinations` | only exported `SERVER=root@127.0.0.1` |
| testrc overrides of `cd`, `rm`, `mv`, `mkdir`, `touch`, `ping`, `exit`, `git`, `whoami`, `ls`, `please`, network `precmd` | they replace real commands with jokes or slow every failed command |
| `.tmuxrc` `download` / `upload` | nc to a tty path never worked |
| `.zshrc` `venstall` | unreviewed `curl … \| sh` of a third-party installer |
| `.zshrc` `apt='pacman'` | joke alias that breaks muscle memory on Debian hosts |
| testrc `gpt()` | superseded by `sgpt` in `ai-tools` |
| `test.zsh` `testscript` | ran a scratch file from `~/.zsh` |
| machine-specific `.zshrc` lines (KOMBINAT, szmelc-commander, auto-Hypr.sh, lmstudio, bun, grok, opencode, `REPO`, `PICO_SDK_PATH`, `BROWSER`, `QT_QPA_PLATFORMTHEME`) | per-machine setup, belongs in `user/local.zsh` / `msh env` |
