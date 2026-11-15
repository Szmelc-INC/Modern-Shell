# Modern Shell — addon & item specification

This is the contract between the zsh runtime (`shell/`), the `msh` CLI/TUI and
anyone writing addons. Everything `msh` shows is parsed from the files described
here, so following this spec is what makes an addon show up nicely in the TUI.

## Paths

| Variable     | Default                             | Owner                              |
|--------------|-------------------------------------|------------------------------------|
| `MSH_HOME`   | `${XDG_CONFIG_HOME:-~/.config}/msh` | installer (refreshed on upgrade)   |
| `MSH_USER`   | `$MSH_HOME/user`                    | **you** (never overwritten)        |
| `MSH_CACHE`  | `${XDG_CACHE_HOME:-~/.cache}/msh`   | runtime                            |
| `MSH_BACKUP` | `~/.BACKUP/msh`                     | `snapshot` addon                   |
| `MSH_SESSIONS` | `${XDG_DATA_HOME:-~/.local/share}/msh/sessions` | `session` addon (`msh-session`) |

> The Shell Integration Bible puts everything under `~/.zsh/`. Modern Shell
> deliberately lives in `~/.config/msh` instead, so it never collides with an
> existing hand-made `~/.zsh/` (and the private files kept there). Inside
> `MSH_HOME` the Bible layout and load order are followed exactly.

```
$MSH_HOME/
├── zshrc            loader (sourced by the ~/.zshrc stub)
├── rc.d/            numbered framework files, sourced in lexical order
├── addons/          shipped addons  (<name>.zsh)
├── functions/       shipped autoloaded functions (one per file, no extension)
├── bin/             shipped standalone scripts (on PATH)
├── completions/     _msh and other completion files (on fpath)
├── conf/            p10k.zsh and other tool configs
├── targets.list     every path an install modifies (snapshot source of truth)
├── VERSION
└── user/            YOUR layer — install/upgrade never touches it
    ├── msh.conf         settings (zsh syntax)
    ├── addons.state     addon on/off overrides  (name=on|off)
    ├── addons/          your own addons (same format; same name overrides shipped)
    ├── aliases.zsh      managed aliases
    ├── env.zsh          managed environment variables
    ├── secrets.zsh      managed secrets (mode 600)
    ├── functions/       managed functions (<name>.zsh, disabled: <name>.zsh.off)
    └── local.zsh        free-form, sourced last (machine-specific stuff)
```

## Load order

`~/.zshrc` (stub) → `$MSH_HOME/zshrc` → p10k instant prompt → `rc.d/*.zsh`:

| File                  | Concern                                                        |
|-----------------------|----------------------------------------------------------------|
| `00-init.zsh`         | env, XDG, PATH/fpath, output helpers, `user/msh.conf`          |
| `10-zinit.zsh`        | zinit + plugins (p10k, fzf-tab, completions, fsh, autosuggest) |
| `20-completion.zsh`   | `compinit` (24h cached dump) + zstyles                         |
| `30-history.zsh`      | history options                                                |
| `40-keybinds.zsh`     | `bindkey`                                                      |
| `50-addons.zsh`       | sources every **enabled** addon                                |
| `60-user.zsh`         | user env, secrets, aliases, functions                          |
| `70-integrations.zsh` | fzf, thefuck (lazy), **zoxide last — it owns `cd`**            |
| `90-prompt.zsh`       | p10k config or the built-in fallback prompt                    |

Then `user/local.zsh`, then external secret files (`MSH_EXTERNAL_SECRETS`,
default `~/.zsh/secure.zsh`) — sourced if readable, never parsed, copied or
modified by msh.

## Addon file format

One addon = one file `addons/<name>.zsh`. `<name>` is lowercase-kebab.
The **header** is the first contiguous block of `#` comment lines (after the
shebang). Recognised keys:

```zsh
#!/usr/bin/env zsh
# NAME: mkcd
# DESC: Create a directory and enter it in one step
# TAGS: FILES, NAVIGATION
# DEP: zoxide (optional)
# DEFAULT: on
# VER: 1.0
# DEV: SilverX
# EXAMPLE: mkcd ~/src/new-project
# | Long help, rendered as **markdown** in the TUI (F1).
# | Every line starting with `# |` belongs to it.
```

| Key       | Required | Meaning                                                             |
|-----------|----------|---------------------------------------------------------------------|
| `NAME`    | yes      | must equal the file name without `.zsh`                             |
| `DESC`    | yes      | one line, shown in lists                                            |
| `TAGS`    | yes      | comma list: CORE, FILES, NAVIGATION, SEARCH, GIT, NETWORK, WEB, MEDIA, SYSTEM, PROCESS, CLIPBOARD, EYECANDY, AI, TMUX, DEV, SECURITY, FUN |
| `DEP`     | no       | comma list of commands; `(optional)` suffix allowed                 |
| `DEFAULT` | no       | `on` (default) or `off` — state when `addons.state` has no entry    |
| `VER`     | no       | free-form version                                                   |
| `DEV`     | no       | author / credit                                                     |
| `EXAMPLE` | no       | may repeat                                                          |
| `\|`      | no       | long markdown help                                                  |

### Rules (from ZRC CONTRIBUTE + the Shell Integration Bible)

1. **No side effects on source.** Sourcing defines aliases/functions/vars only.
   No network, no `sudo`, no `killall`, no `exec`, no output. Heavy work goes
   inside functions.
2. **Idempotent.** Sourcing twice must be harmless.
3. **Guard optional tools**: `(( $+commands[eza] ))` before aliasing to them.
4. **Never redefine `cd`.** zoxide owns it.
5. **Privilege escalation uses `pkexec`**, never `sudo`.
6. **No secrets.** Read them from env vars (set through `msh secret`).
7. **No hardcoded `/home/<user>`.** Use `$HOME`, `$XDG_*`, or a `: ${VAR:=default}`
   tweakable at the top of the file.
8. **Namespaced names.** Avoid clobbering common words (`send`, `run`, `close`…).
9. Each alias and function gets a **doc comment** directly above it. The first
   comment line is the summary shown in the TUI:

```zsh
# mkcd <dir> — create a directory (with parents) and cd into it
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

# Show disk usage of entries in the current directory, sorted
alias diskspace='du -sh -- * 2>/dev/null | sort -h'
```

10. User-facing output uses the shared helpers from `00-init.zsh`:
    `msh::info`, `msh::ok`, `msh::warn`, `msh::err`, `msh::confirm` (colored,
    respect `NO_COLOR`).

## Managed item files (written by msh, hand edits welcome)

`user/aliases.zsh`, `user/env.zsh`, `user/secrets.zsh` share one line format:

```zsh
## Short description of the next item
alias gs='git status -sb'
## Disabled items are commented with the #off# marker
#off# alias gl='git log --oneline'
```

- Item line: `alias NAME='VALUE'` (aliases) or `export NAME='VALUE'` (env, secrets).
- Values are single-quoted; a literal `'` is written as `'\''`.
- `## text` directly above an item is its description.
- `#off# ` prefix = disabled (the file stays valid zsh).

User functions: `user/functions/<name>.zsh` contains `# DESC: …` then the full
`name() { … }` definition. Disabled = renamed to `<name>.zsh.off`.

## Toggle semantics per type

| Type      | ON/OFF means                                                          |
|-----------|-----------------------------------------------------------------------|
| Addon     | `addons.state` entry; off = file not sourced at all                   |
| Alias     | `#off#` marker in `user/aliases.zsh` (shipped ones: toggle the addon) |
| Function  | `.zsh` ↔ `.zsh.off` (shipped ones: toggle the addon)                  |
| Env       | `#off#` marker in `user/env.zsh`                                      |
| Secret    | `#off#` marker in `user/secrets.zsh`                                  |
| Directory | zoxide has no on/off: add, remove, or exclude via `_ZO_EXCLUDE_DIRS`  |
| Snapshot  | no on/off: create, restore, remove                                    |

Changes apply to **new** shells; run `reload` (= `exec zsh`) in an open one.
