package tui

// Help texts (markdown, rendered with glamour). F1 picks the most specific one:
// open dialog → its help; otherwise the selected item's help on top of the tab's.

var tabHelp = map[int]string{
	tabAddons: `# Addons

An **addon** is one zsh file that adds a themed set of aliases, functions and
settings (clipboard, archives, search, eyecandy…). Shipped addons live in
` + "`~/.config/msh/addons`" + `, your own in ` + "`~/.config/msh/user/addons`" + `.

| Key | Action |
|---|---|
| ` + "`space`" + ` | switch the addon **on/off** (stored in ` + "`user/addons.state`" + `) |
| ` + "`a`" + ` | create a new addon from a template, then edit it |
| ` + "`e`" + ` | edit in ` + "`$EDITOR`" + ` — a *shipped* addon is first **copied to your layer** (your copy wins, survives upgrades) |
| ` + "`d`" + ` | delete — only **your** addons; shipped ones can only be switched off |
| ` + "`enter`" + ` | focus the details pane (scroll with ↑↓) |

**ON/OFF** — an addon that is off is not sourced at all, so none of its aliases
or functions exist. The ` + "`DEFAULT:`" + ` header decides the state until you toggle it.

**Sources** — *shipped* (comes with msh), *user* (yours), *override* (your copy
of a shipped addon with the same name).

Changes apply to **new shells**. In an open one run ` + "`reload`" + `.`,

	tabAliases: `# Aliases

Short names that expand to longer commands. This tab shows **your aliases**
(` + "`user/aliases.zsh`" + `, editable) and, below them, **aliases defined by addons**
(read-only, marked with their addon).

| Key | Action |
|---|---|
| ` + "`a`" + ` | add an alias |
| ` + "`e`" + ` | edit — on an addon alias this creates **your override** with the same name |
| ` + "`space`" + ` | switch on/off (yours: commented out with ` + "`#off#`" + `; addon aliases: toggle the whole addon in the Addons tab) |
| ` + "`d`" + ` | delete (yours only) |
| ` + "`A`" + ` | show/hide addon aliases |

Your aliases load **after** addons, so an override always wins.
Tip: aliases are expanded only at the start of a command line.`,

	tabFunctions: `# Functions

Small shell programs callable by name. **Your functions** live one per file in
` + "`user/functions/<name>.zsh`" + `; functions from addons are listed read-only.

| Key | Action |
|---|---|
| ` + "`a`" + ` | new function (name, description, body) |
| ` + "`e`" + ` | edit in the form — on an addon function this creates **your override** |
| ` + "`E`" + ` | open the file in ` + "`$EDITOR`" + ` |
| ` + "`space`" + ` | on/off — renames the file to ` + "`.zsh.off`" + ` so it is not loaded |
| ` + "`d`" + ` | delete (yours only) |
| ` + "`A`" + ` | show/hide addon functions |

The **body** is what goes between ` + "`name() {`" + ` and ` + "`}`" + `. Arguments are
` + "`$1 $2 …`" + ` (all: ` + "`$@`" + `). Use ` + "`local`" + ` for variables and the helpers
` + "`msh::ok/info/warn/err`" + ` for pretty output.`,

	tabEnv: `# Environment variables

Variables exported to every new shell from ` + "`user/env.zsh`" + `.

| Key | Action |
|---|---|
| ` + "`a`" + ` | add a variable |
| ` + "`e`" + ` | edit name, value or description |
| ` + "`space`" + ` | on/off (kept in the file, commented with ` + "`#off#`" + `) |
| ` + "`d`" + ` | delete |

Values are stored **literally** (single-quoted) — ` + "`$HOME`" + ` is *not* expanded.
Use an absolute path, or put dynamic exports in ` + "`user/local.zsh`" + ` (` + "`:edit-local`" + `).
Passwords and API keys belong in **Secrets**.`,

	tabSecrets: `# Secrets

API keys, tokens and passwords exported to every new shell from
` + "`user/secrets.zsh`" + ` — a file with mode **600** (only you can read it).
Values are **masked** here.

| Key | Action |
|---|---|
| ` + "`a`" + ` | add a secret (typed hidden; ` + "`ctrl+r`" + ` in the field shows it) |
| ` + "`e`" + ` | change it |
| ` + "`v`" + ` | reveal / hide the selected value |
| ` + "`space`" + ` | on/off (` + "`#off#`" + ` marker) |
| ` + "`d`" + ` | delete |

**External secret files** (default ` + "`~/.zsh/secure.zsh`" + `, setting
` + "`MSH_EXTERNAL_SECRETS`" + `) are sourced last but are **never read, shown or
changed** by msh.

Tip: snapshots include ` + "`user/secrets.zsh`" + ` — ` + "`~/.BACKUP`" + ` is kept at mode 700.`,

	tabDirs: `# Directories (zoxide)

zoxide remembers directories you visit and ranks them by **frecency**
(frequency + recency). ` + "`cd foo`" + ` jumps to the best match for *foo*,
` + "`cdi`" + ` opens an interactive picker. This tab is its database.

| Key | Action |
|---|---|
| ` + "`enter`" + ` | jump there (when msh was started from the shell wrapper) |
| ` + "`a`" + ` | add a directory (or bump its score) |
| ` + "`d`" + ` | forget a directory |
| ` + "`x`" + ` | **exclude** it forever (` + "`_ZO_EXCLUDE_DIRS`" + ` in Env) |
| ` + "`p`" + ` | prune entries whose directory no longer exists |

zoxide has **no on/off** per directory: remove it or exclude it.`,

	tabSnapshots: `# Snapshots

A snapshot is a full copy of everything Modern Shell modifies
(` + "`~/.zshrc`" + `, ` + "`~/.nanorc`" + `, ` + "`~/.tmux.conf`" + `, ` + "`~/.config/msh`" + `, the ` + "`msh`" + ` binary and
completions) stored in ` + "`~/.BACKUP/msh/<id>`" + `. Paths that did **not** exist are
recorded too, so a restore is a **complete revert**.

| Key | Action |
|---|---|
| ` + "`a`" + ` / ` + "`n`" + ` | create a snapshot now (optional label) |
| ` + "`r`" + ` | **restore** — fully revert to the selected snapshot |
| ` + "`d`" + ` | delete the snapshot (asks first) |
| ` + "`enter`" + ` | focus details: metadata, contents and what changed since |

Every install takes a ` + "`pre-install`" + ` snapshot automatically, and every restore
takes a ` + "`pre-restore`" + ` one first — so a restore can itself be undone.
Same engine as the ` + "`snapshot`" + ` shell command.`,
}

const keysHelp = `# Keys

| Key | Action |
|---|---|
| ` + "`tab` `shift+tab` `←` `→`" + ` | next / previous tab |
| ` + "`1`…`7`" + ` | jump to a tab |
| ` + "`↑` `↓` `k` `j`" + ` | move |
| ` + "`pgup` `pgdn` `home` `end`" + ` | page / first / last |
| ` + "`enter`" + ` | focus the details pane (` + "`esc`" + ` back) |
| ` + "`ctrl+u` `ctrl+d`" + ` | scroll details |
| ` + "`/`" + ` | filter the list (` + "`esc`" + ` clears) |
| ` + "`space`" + ` | toggle on/off |
| ` + "`a`" + ` | add |
| ` + "`e`" + ` | edit |
| ` + "`d` / `delete`" + ` | delete (asks first) |
| ` + "`ctrl+r` / `F5`" + ` | reload from disk |
| ` + "`:`" + ` | command palette |
| ` + "`F1`" + ` | help for whatever is selected or open |
| ` + "`?`" + ` | this key list |
| ` + "`q` / `ctrl+c`" + ` | quit |

Mouse: click a tab or a row, wheel scrolls.`

const paletteHelp = `# Command palette

Type a command and press ` + "`enter`" + `. ` + "`tab`" + ` completes, ` + "`↑↓`" + ` choose, ` + "`esc`" + ` closes.

| Command | Does |
|---|---|
| ` + "`addons` `aliases` `functions` `env` `secrets` `dirs` `snapshots`" + ` | switch tab |
| ` + "`add` `edit` `delete` `toggle`" + ` | act on the selection |
| ` + "`filter <text>`" + ` / ` + "`clear`" + ` | filter the list |
| ` + "`all`" + ` | show/hide addon-defined aliases and functions |
| ` + "`reveal`" + ` | reveal/hide all secrets |
| ` + "`snapshot [label]`" + ` | create a snapshot |
| ` + "`edit-config`" + ` / ` + "`edit-local`" + ` | open ` + "`user/msh.conf`" + ` / ` + "`user/local.zsh`" + ` in ` + "`$EDITOR`" + ` |
| ` + "`reload`" + ` | re-read everything from disk |
| ` + "`help` / `keys` / `quit`" + ` | … |`

const confirmHelp = `# Confirmation

Press ` + "`y`" + ` to go ahead, ` + "`n`" + ` or ` + "`esc`" + ` to cancel.
Destructive actions (delete, restore) always ask first. Restoring a snapshot
takes a safety snapshot before changing anything.`

var formHelp = map[string]string{
	"alias": `# Alias form

- **Name** — what you type: letters, digits and ` + "`. _ - : + @ %`" + `.
- **Command** — what it expands to, exactly as you would type it.
  Quotes are fine: the value is stored safely single-quoted.
- **Description** — shown in lists and in completion.

` + "`tab`" + ` / ` + "`shift+tab`" + ` move between fields, ` + "`enter`" + ` on the last field (or ` + "`ctrl+s`" + `) saves, ` + "`esc`" + ` cancels.`,
	"env": `# Environment variable form

- **Name** — ` + "`[A-Za-z_][A-Za-z0-9_]*`" + `, conventionally UPPER_CASE.
- **Value** — stored literally; ` + "`$VARS`" + ` and ` + "`~`" + ` are **not** expanded.
- **Description** — optional note.

` + "`ctrl+s`" + ` saves, ` + "`esc`" + ` cancels.`,
	"secret": `# Secret form

- **Name** — the variable name, e.g. ` + "`GITHUB_TOKEN`" + `.
- **Value** — hidden while typing; ` + "`ctrl+r`" + ` toggles visibility.
- **Description** — e.g. where it came from or when it expires.

Stored in ` + "`user/secrets.zsh`" + ` (mode 600). ` + "`ctrl+s`" + ` saves, ` + "`esc`" + ` cancels.`,
	"function": `# Function form

- **Name** — how you call it.
- **Description** — one line, shown in lists.
- **Body** — the code between ` + "`name() {`" + ` and ` + "`}`" + `; multi-line.
  Arguments: ` + "`$1 $2 … $@`" + `. Prefer ` + "`local`" + ` variables.

In the body ` + "`enter`" + ` is a newline: save with ` + "`ctrl+s`" + `. ` + "`esc`" + ` cancels.`,
	"addon": `# New addon

- **Name** — lowercase with dashes, becomes ` + "`user/addons/<name>.zsh`" + `.
- **Description** / **Tags** — fill the header (` + "`DESC:`" + ` / ` + "`TAGS:`" + `).

After saving, the template opens in ` + "`$EDITOR`" + `. Document every alias and
function with a comment line right above it — that text shows up here.
See ` + "`docs/ADDON-SPEC.md`" + ` for the full format.`,
	"dir": `# Add directory

Absolute path, or ` + "`~/…`" + `. It is added to zoxide (or its score bumped).`,
	"snapshot": `# Create snapshot

Optional **label** (letters, digits, ` + "`. _ -`" + `) appended to the id, e.g.
` + "`before-experiment`" + `. Leave empty for a plain timestamp.`,
}
