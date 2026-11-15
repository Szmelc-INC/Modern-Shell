# Desktop sessions — `msh-session`

`msh-session` saves the **whole graphical session** into a snapshot directory
and brings it back: every window where it was, the program behind it, what it
had open, and the data you never saved. Switching between snapshots takes a
second or two because windows that are already open are reused and only moved.

Shell front-end: the `session` addon (`sess`, `sess-save`, `sess-load`,
`sess-switch`, `sess-list`, `sess-show`). Manager: `msh session …` and the
**Sessions** tab (`8`) of the `msh` TUI.

Current backend: **Arch Linux + Hyprland** (`hyprctl`), with apps relaunched as
**UWSM** units (`uwsm app --`) when the session runs under UWSM. The engine is
split into a compositor backend and per-application handlers, so other
compositors (sway, KDE, GNOME) and systems can be added later.

## Quick start

```sh
msh-session doctor                 # what can be captured here, how to enable the rest
msh-session save work -m "coding"  # snapshot the running session
msh-session list                   # newest first; ● = active
msh-session show work              # windows, saved state, unsaved-data files
msh-session switch music           # close what is not in "music", restore it
msh-session restore work --dry-run # only print the plan (reuse / launch / close)
msh-session diff work              # snapshot vs the live session
```

Hyprland bindings, for example (`install.sh` puts the tool in
`~/.config/msh/bin`, which only zsh has on `PATH` — use the full path there;
with the Arch package it is `/usr/bin/msh-session`):

```ini
$msess = ~/.config/msh/bin/msh-session
bind = SUPER ALT, S, exec, $msess save quick -f -y
bind = SUPER ALT, R, exec, kitty -e $msess switch    # fzf picker
```

## What a snapshot contains

```
~/.local/share/msh/sessions/<name>/        mode 700
├── session.toml        everything below, human-readable (session.json = same data)
├── unsaved/<window>/   unsaved data: Kate buffers, AT-SPI text, kitty scrollback
├── apps/               app state: Kate session + stash, browser session logs, kitty sessions
├── shots/              screenshots of every monitor and every visible window (grim)
├── raw/                raw hyprctl JSON (clients, monitors, workspaces, layers, devices…)
└── config/hypr/        copy of ~/.config/hypr (reference only, never restored)
```

**Per window** (`[[windows]]`): class, initial class, title, workspace (special
workspaces too), monitor, global and monitor-relative position, size,
floating / pinned / fullscreen / grouped / XWayland, focus history, PID, full
command line (secrets redacted), working directory, executable, AppImage path,
open user files, the UWSM unit (`app-*.scope`), and the command that will start
it again (`[windows.restore]`).

**Session state** (`[state]`): active workspace per monitor and the focused one,
keyboard layout, wallpaper per monitor (hyprpaper), default sink volume/mute,
an allowlist of session environment variables, running UWSM app units, and —
only with `clipboard = true` — the clipboard.

## Application handlers

| Programs | Captured | Restored |
|---|---|---|
| **Kate** (`org.kde.kate`) | Kate is told over D-Bus to save its session (`sessions_save`), which also writes its **stash** of unsaved documents; session file + stash are copied, every unsaved buffer is also copied as plain text to `unsaved/` | loaded as Kate session `msh-<name>` — never-saved documents come back **as unsaved documents**, modified ones with their changes; a running Kate switches sessions in place |
| **Chromium family** (Thorium, Chromium, Chrome, Brave, Vivaldi, Edge) | windows → tabs (URL, title, pinned, active tab) from the SNSS session log; the session files are copied | `--new-window` with that window's tabs |
| **Terminals** (kitty, foot, alacritty, wezterm, ghostty, konsole, xterm) | per tab: shell, working directory, foreground command; editors (nano, vim, …) and the files they edit; with kitty remote control on, the full scrollback of every window | kitty: a generated `--session` file (every tab, cwd and command, then back to an interactive shell); others: working directory + command |
| **mpv** | playlist, current item; with `input-ipc-server` also time position, pause, volume | same playlist from the same item (and position) |
| **OBS Studio** | profile, scene collection, current scene | `obs --profile … --collection … --scene …` |
| **File managers** (Thunar, Nautilus, Dolphin, PCManFM, Nemo, Caja) | the open folder (resolved from the title) | opened on that folder |
| **GTK/Qt notepads** (Mousepad, gedit, GNOME Text Editor, KWrite, FeatherPad…) | open files + **unsaved text** through AT-SPI | files reopened, unsaved text opened from `unsaved/` |
| **anything else** (Discord, Electron apps, games…) | generic: command line, cwd, open files, AT-SPI text when exposed, screenshot | config override → command line → AppImage → `.desktop` entry → executable |

## Unsaved data — how far it goes

1. **Native app sessions** (best): apps that keep their own recovery state are
   asked to write it and the state is copied (Kate stash, Chromium session
   logs). Restoring hands the state back, so unsaved documents return unsaved.
2. **Accessibility (AT-SPI)**: editable text of every accessible window is
   copied to `unsaved/<window>/atspi-NN.txt`. GTK apps expose it by default;
   Qt and Electron apps only when accessibility is on — `msh-session a11y on`
   adds `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` to `~/.config/uwsm/env` (effective
   after the next login). Password fields are skipped.
3. **Terminals**: with kitty remote control enabled the scrollback of every
   kitty window is saved (`allow_remote_control socket-only` and
   `listen_on unix:@kitty-{kitty_pid}` in `kitty.conf`).
4. **Always**: a screenshot of each visible window.

Known gaps: buffers of terminal editors (nano, vim) live in their own memory —
only the file and the command are recorded; form contents in browsers would
need remote debugging; mpv's position needs `input-ipc-server`.

## Restore and switch

1. The current session is saved first as `auto-pre-restore-*` /
   `auto-pre-switch-*` (the newest `keep_auto` are kept), so any restore can be
   undone with `switch auto-…`.
2. Snapshot windows are paired with open ones (`same()` per handler: title,
   command line, terminal directory; Kate and OBS are single-instance). A
   browser or file manager whose title changed since (other tab, other folder)
   is still paired when it is the only window of its class on both sides.
3. `switch` (and `restore --close-others`) closes the rest gracefully —
   apps may ask to save; nothing is killed. The terminal that runs
   `msh-session` is never closed (shown as `keep` in the plan).
4. Missing windows are launched at once (`uwsm app --` under UWSM, else
   `hyprctl dispatch exec`); new windows are recognised as they map.
5. Every window is moved to its workspace, (un)floated, resized, positioned
   (floating ones to the exact pixel), pinned and fullscreened; then the active
   workspaces, focus, keyboard layout, wallpaper and volume come back
   (`--no-state` skips this step; `--only CLASS` limits everything to some apps).

Tiled windows return to their workspace; their split order follows the
compositor's layout, not pixels.

## Configuration

`msh-session config init` writes `$MSH_USER/session.toml` (default
`~/.config/msh/user/session.toml`):

```toml
store          = "~/.local/share/msh/sessions"
screenshots    = true
clipboard      = false      # may contain secrets — off by default
atspi          = true
hypr_config    = true
launch_timeout = 20.0
close_timeout  = 10.0
keep_auto      = 10
uwsm           = "auto"     # auto | always | never
exclude        = ["polkit-*"]

[launch]                    # how to start a class when detection is not enough
discord = "discord"
```

Environment: `MSH_SESSIONS` (store), `MSH_SESSION_CONFIG` (config file),
`NO_COLOR`, `MSH_YES=1` (assume yes).

## Privacy

Snapshots are mode 700. Process environments are never stored wholesale (only
an allowlist of desktop variables). Files under the secrets wall
(`~/.zsh/secure.zsh*`, `~/.zsh/llm-keys.zsh`, `~/.zsh/BACKUP/`) are never read,
copied or recorded — a window whose command touches one is stored as
`redacted`. `password=`/`token=`-style arguments are masked.

## Commands

| Command | Does |
|---|---|
| `save [name] [-m note] [-f] [--no-shots] [--only CLASS]` | snapshot the running session |
| `restore [name] [-n] [--close-others] [--no-place] [--no-state] [--no-backup] [--only CLASS]` | reuse + launch + place |
| `switch [name] [-n] [--keep] [-u] [--no-state] [--no-backup] [--only CLASS]` | restore and close everything else |
| `list [-a] [--names]` / `show [name]` / `status` / `diff A [B]` | inspect |
| `rm [names…]` / `prune [--keep N]` / `rename OLD NEW` / `path [name]` | manage |
| `export [name] [-o file]` / `import FILE [--name N]` | move snapshots between machines |
| `doctor` / `a11y on|off|status` / `config [show|init|path]` | setup |
| `completion zsh|bash|fish` | shell completion |

References: `NAME`, a unique prefix, `#N` (N-th newest), `@active`. Without a
name, `restore`/`switch`/`show`/`rm` open an fzf picker. Every command accepts
`--json` where it prints data, `--no-color`, and has its own `--help`.
