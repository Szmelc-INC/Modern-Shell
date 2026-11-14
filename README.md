<div align="center">

# ◆ Modern Shell

**One modular, colorful, safe zsh environment — and `msh`, a TUI + CLI to manage it.**

[![License: MIT](https://img.shields.io/badge/license-MIT-7aa2f7.svg)](LICENSE)
[![Shell: zsh](https://img.shields.io/badge/shell-zsh-b4befe.svg)](https://www.zsh.org/)
[![Go](https://img.shields.io/badge/msh-Go%20%C2%B7%20bubbletea-a6e3a1.svg)](https://github.com/charmbracelet/bubbletea)
[![Arch PKGBUILD](https://img.shields.io/badge/Arch-PKGBUILD-1793d1.svg)](packaging/arch/PKGBUILD)
[![Nix flake](https://img.shields.io/badge/nix-flake-5277c3.svg)](flake.nix)

</div>

Modern Shell consolidates [Silver-ZSH](https://github.com/Szmelc-INC/Silver-ZSH),
[ZRC](https://github.com/Szmelc-INC/ZRC) and years of hand-grown `~/.zsh` addons
into one framework that follows the **Shell Integration Bible**: a tiny loader,
numbered `rc.d/` files in a deterministic order, one concern per file, and
everything toggleable.

- **Zen out of the box** — Powerlevel10k minimal prompt (instant prompt),
  fast-syntax-highlighting, autosuggestions, fzf-tab completion with previews,
  zoxide-powered `cd`, colored `ls`/`cat`/`man`/`grep`, command-not-found + lazy `thefuck`.
- **Addons** — ~30 themed addons (archives, clipboard, search, navigation,
  eyecandy, net-pack, proc-tools, tmux-control, quick-notes…), each one file,
  documented, switchable on/off. See [docs/ADDONS.md](docs/ADDONS.md).
- **Snapshots** — every install first copies everything it will touch to
  `~/.BACKUP/msh/<id>`; `snapshot restore` is a *full* revert.
- **`msh`** — an interactive TUI and a scriptable CLI for addons, aliases,
  functions, env vars, secrets, zoxide directories and snapshots, with **F1
  context help** everywhere.
- **Companions** — a polished `~/.nanorc` and `~/.tmux.conf` in the same Midnight palette.

```
 ◆ msh   1 Addons 32  2 Aliases  3 Functions  4 Env  5 Secrets  6 Dirs  7 Snapshots              v0.1.0
╭──────────────────────────────────────────╮╭───────────────────────────────────────────────────────╮
│Addons  2/32                              ││ Details                                               │
│ ○ ai-tools       AI — LLM helpers: sgpt… ││   archives                                            │
│▌● archives       FILES — Extract any ar… ││  Extract any archive with one command, pack           │
│ ● clipboard      CLIPBOARD,CORE — copy … ││  directories into 7z/zip/rar (optionally encrypted)   │
│ ● colorized-man  EYECANDY,CORE — Colore… ││  • state ● on (default on)                            │
│ ● core-aliases   CORE,FILES,EYECANDY — … ││  • deps ✔ tar · ✔ unzip · ✔ 7z · · unrar · ✔ zstd     │
╰──────────────────────────────────────────╯╰───────────────────────────────────────────────────────╯
 ␣ on/off  a add  e edit  d delete  / filter  F1 help  ? keys  : cmd  q quit
```

## Install

> The installer **never runs without a snapshot**: it first copies every path in
> [`shell/targets.list`](shell/targets.list) (`~/.zshrc`, `~/.nanorc`,
> `~/.tmux.conf`, `~/.config/msh`, the `msh` binary and its completions) to
> `~/.BACKUP/msh/<timestamp>_pre-install`, and it only ever writes to those paths.

```sh
git clone https://github.com/sernik77/modern-shell && cd modern-shell
./install.sh --dry-run     # see what would happen
./install.sh               # do it (asks before installing packages, via pkexec)
exec zsh
```

| Distro | |
|---|---|
| **Arch** | `cd packaging/arch && makepkg -si`, then run `msh-setup` as your user |
| **Nix** | `nix run github:sernik77/modern-shell` (msh), `nix run github:sernik77/modern-shell#setup` |
| **Any** | `./install.sh` — needs `zsh git fzf zoxide`; `go` to build `msh` |

Installer flags: `-y/--yes`, `-n/--dry-run`, `--no-deps`, `--no-nano`, `--no-tmux`,
`--no-binary`, `--no-chsh`. Undo everything: `./uninstall.sh` (restores the newest
`pre-install` snapshot, after taking a `pre-uninstall` one).

### Coming from an existing `~/.zshrc`

Your old `~/.zshrc` is inside the pre-install snapshot (`snapshot show 1`).
The new `~/.zshrc` is a 3-line stub; machine-specific lines (Hyprland hooks,
extra `PATH`s, one-off tool installers) go to `~/.config/msh/user/local.zsh`
(`msh-edit-local`). Secret files such as `~/.zsh/secure.zsh` keep working: they
are sourced last via `MSH_EXTERNAL_SECRETS` and **never read, copied or modified** by msh.

## Using `msh`

`msh` with no arguments opens the TUI. Keys: `tab`/`1-7` tabs · `↑↓` move ·
`space` on/off · `a` add · `e` edit · `d` delete · `/` filter · `:` command palette ·
**`F1` help for whatever is selected or open** · `?` all keys · `q` quit.
Enter on a directory in the *Dirs* tab `cd`s your shell there.

```sh
msh addon list                       # table; --json for scripts
msh addon disable eyecandy
msh addon edit clipboard             # shipped addon → copied to your layer, then $EDITOR
msh alias add gs 'git status -sb' -d 'short status'
msh func add greet -b 'echo "hi ${1:-world}"'
msh env set PAGER less
msh secret set GITHUB_TOKEN          # hidden prompt, stored mode 600, masked in lists
msh dir list -n 10                   # zoxide database
msh snapshot create -l before-experiment
msh doctor                           # check deps + installation
msh completion zsh|bash|fish
```

Every command has colored `--help`; global flags: `--json`, `--no-color`
(or `NO_COLOR=1`), `-y/--yes`.

### Snapshots from the shell

```sh
snapshot create [-l label]   # also: snap-new
snapshot list                # #1 = newest
snapshot diff 1              # what changed since
snapshot restore [id|#]      # full revert; picker without an id; takes a pre-restore snapshot first
snapshot rm [id|#...]        # picker + confirmation
```

## Layout

```
~/.zshrc                     3-line stub → ~/.config/msh/zshrc
~/.config/msh/
├── zshrc  rc.d/             loader + 00-init … 90-prompt (refreshed on upgrade)
├── addons/                  shipped addons
├── conf/p10k.zsh            minimal prompt
└── user/                    YOURS — never overwritten
    ├── msh.conf             settings
    ├── addons.state         addon on/off
    ├── addons/              your addons (same name = override)
    ├── aliases.zsh env.zsh secrets.zsh functions/
    └── local.zsh            machine-specific, sourced last
~/.BACKUP/msh/<id>/          snapshots (mode 700)
```

> The Bible's canonical root is `~/.zsh/`; Modern Shell uses `~/.config/msh` so it
> can never collide with a hand-made `~/.zsh/` (or the private files kept there).
> Inside it, the Bible's layout and load order are followed exactly.

Load order and every file format are specified in **[docs/ADDON-SPEC.md](docs/ADDON-SPEC.md)**.

### Settings (`user/msh.conf`)

| Setting | Default | |
|---|---|---|
| `MSH_ZINIT` | `1` | load zinit + plugins (`0` = plain zsh + addons) |
| `MSH_ZINIT_AUTOINSTALL` | `1` | clone zinit on first start |
| `MSH_PROMPT` | `p10k` | `p10k` or `minimal` (built-in, no plugins) |
| `MSH_P10K_CONFIG` | `conf/p10k.zsh` | point at your own `p10k configure` output |
| `MSH_THEFUCK` | `1` | lazy `fuck` |
| `MSH_EXTERNAL_SECRETS` | `(~/.zsh/secure.zsh)` | read-only secret files, sourced last |
| `MSH_TUI_TAB` | `addons` | TUI start tab |
| `MSH_TUI_ADDON_DEFS` | `1` | show addon aliases/functions in the TUI |

## Development

```sh
make build        # bin/msh
make test         # Go unit + headless TUI tests, shell tests in a throwaway $HOME
make tui-capture  # text screenshots of the real TUI via tmux
make lint         # zsh -n + addon header contract
make arch-pkg     # build the Arch package from HEAD
make vendor-hash  # refresh flake.nix vendorHash (no nix required)
```

Writing an addon: copy any file in `shell/addons/`, follow
[docs/ADDON-SPEC.md](docs/ADDON-SPEC.md) (header, doc comment above every
alias/function, no side effects on source, `pkexec` never `sudo`), run `make lint`.

## License

[MIT](LICENSE) © SilverX (serainox420)
