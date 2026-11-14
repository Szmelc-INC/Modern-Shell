package tui

import (
	"fmt"
	"strings"

	"github.com/Szmelc-INC/Modern-Shell/internal/store"
)

const (
	tabAddons = iota
	tabAliases
	tabFunctions
	tabEnv
	tabSecrets
	tabDirs
	tabSnapshots
	tabCount
)

var tabTitles = [tabCount]string{"Addons", "Aliases", "Functions", "Env", "Secrets", "Dirs", "Snapshots"}

// TabNames lists tab ids for --tab and completion.
func TabNames() []string {
	out := make([]string, tabCount)
	for i, t := range tabTitles {
		out[i] = strings.ToLower(t)
	}
	return out
}

func tabByName(s string) (int, bool) {
	s = strings.ToLower(strings.TrimSpace(s))
	for i, n := range TabNames() {
		if n == s || strings.TrimSuffix(n, "s") == s || (len(s) >= 2 && strings.HasPrefix(n, s)) {
			return i, true
		}
	}
	return 0, false
}

// row is one line in a tab's list plus everything needed to act on it.
type row struct {
	key    string
	name   string
	value  string
	desc   string
	on     *bool // nil: no on/off
	source string
	user   bool // editable/deletable by the user

	addon *store.Addon
	item  *store.Item
	fn    *store.UserFunc
	def   *store.Def
	dir   *store.Dir
	snap  *store.Snapshot
}

func boolp(b bool) *bool { return &b }

func (r row) matches(filter string) bool {
	if filter == "" {
		return true
	}
	f := strings.ToLower(filter)
	return strings.Contains(strings.ToLower(r.name+" "+r.desc+" "+r.source), f) ||
		(r.item == nil || r.source != "secret") && strings.Contains(strings.ToLower(r.value), f)
}

// loadTab reads one tab's rows from disk.
func (m *model) loadTab(t int) error {
	var rows []row
	switch t {
	case tabAddons:
		addons, err := store.LoadAddons(m.p)
		if err != nil {
			return err
		}
		m.addons = addons
		for i := range addons {
			a := &addons[i]
			src := "shipped"
			if a.Overrides {
				src = "override"
			} else if a.User {
				src = "user"
			}
			rows = append(rows, row{key: "addon:" + a.Name, name: a.Name, value: strings.Join(a.Tags, ","), desc: a.Desc,
				on: boolp(a.Enabled), source: src, user: a.User, addon: a})
		}
	case tabAliases, tabEnv, tabSecrets:
		kind := map[int]store.Kind{tabAliases: store.KindAlias, tabEnv: store.KindEnv, tabSecrets: store.KindSecret}[t]
		mf, err := m.managed(kind)
		if err != nil {
			return err
		}
		for _, it := range mf.Items() {
			it := it
			val := it.Value
			if kind == store.KindSecret && !m.reveal[it.Name] && !m.revealAll {
				val = store.Mask(it.Value)
			}
			rows = append(rows, row{key: string(kind) + ":" + it.Name, name: it.Name, value: val, desc: it.Desc,
				on: boolp(it.Enabled), source: string(kind), user: true, item: &it})
		}
		if t == tabAliases && m.showAddonDefs {
			rows = append(rows, m.addonDefRows(store.KindAlias)...)
		}
	case tabFunctions:
		fns, err := store.LoadUserFuncs(m.p)
		if err != nil {
			return err
		}
		for i := range fns {
			f := &fns[i]
			rows = append(rows, row{key: "func:" + f.Name, name: f.Name, desc: f.Desc, on: boolp(f.Enabled), source: "user", user: true, fn: f})
		}
		if m.showAddonDefs {
			rows = append(rows, m.addonDefRows(store.KindFunction)...)
		}
	case tabDirs:
		if !store.ZoxideAvailable() {
			m.rows[t] = nil
			return fmt.Errorf("zoxide is not installed")
		}
		dirs, err := store.ListDirs()
		if err != nil {
			return err
		}
		for i := range dirs {
			d := &dirs[i]
			desc := ""
			if !d.Exists {
				desc = "missing"
			}
			rows = append(rows, row{key: "dir:" + d.Path, name: m.p.Tilde(d.Path), value: fmt.Sprintf("%.1f", d.Score), desc: desc, user: true, dir: d})
		}
	case tabSnapshots:
		snaps, err := store.ListSnapshots(m.p)
		if err != nil {
			return err
		}
		for i := range snaps {
			s := &snaps[i]
			rows = append(rows, row{key: "snap:" + s.ID, name: s.ID, value: s.Size, desc: s.Reason, user: true, snap: s})
		}
	}
	m.rows[t] = rows
	m.loaded[t] = true
	return nil
}

func (m *model) addonDefRows(kind store.Kind) []row {
	if m.addons == nil {
		m.addons, _ = store.LoadAddons(m.p)
	}
	var rows []row
	for _, a := range m.addons {
		for _, d := range a.Defs {
			if d.Kind != kind {
				continue
			}
			d := d
			val := d.Value
			if kind == store.KindFunction {
				val = ""
			}
			rows = append(rows, row{key: string(kind) + "@" + a.Name + ":" + d.Name, name: d.Name, value: val, desc: d.Summary(),
				on: boolp(a.Enabled), source: "addon:" + a.Name, def: &d})
		}
	}
	return rows
}

func (m *model) managed(kind store.Kind) (*store.ManagedFile, error) {
	switch kind {
	case store.KindAlias:
		return store.LoadManaged(m.p.AliasesFile(), kind)
	case store.KindEnv:
		return store.LoadManaged(m.p.EnvFile(), kind)
	default:
		return store.LoadManaged(m.p.SecretsFile(), kind)
	}
}

// ── details (markdown) ────────────────────────────────────────────────────

func code(s string) string {
	if strings.Contains(s, "`") {
		return "`` " + s + " ``"
	}
	return "`" + s + "`"
}

func onOffMD(on bool) string {
	if on {
		return "● **on**"
	}
	return "○ **off**"
}

func (m *model) detailMD(r *row) string {
	var b strings.Builder
	w := func(format string, a ...any) { fmt.Fprintf(&b, format, a...) }
	switch {
	case r.addon != nil:
		a := r.addon
		w("# %s\n\n%s\n\n", a.Name, a.Desc)
		w("- **state** %s (default %s)\n", onOffMD(a.Enabled), map[bool]string{true: "on", false: "off"}[a.Default])
		w("- **source** %s · %s\n", r.source, code(m.p.Tilde(a.File)))
		if len(a.Tags) > 0 {
			w("- **tags** %s\n", strings.Join(a.Tags, ", "))
		}
		if a.Version != "" || a.Dev != "" {
			w("- **version** %s · **author** %s\n", orNone(a.Version), orNone(a.Dev))
		}
		if deps := a.DepStatus(); len(deps) > 0 {
			var parts []string
			for _, d := range deps {
				mark := "✔"
				if !d.Installed {
					mark = "✘"
					if d.Optional {
						mark = "·"
					}
				}
				parts = append(parts, mark+" "+d.Name)
			}
			w("- **deps** %s\n", strings.Join(parts, " · "))
		}
		if len(a.Examples) > 0 {
			w("\n## Examples\n\n")
			for _, e := range a.Examples {
				w("- %s\n", code(e))
			}
		}
		if fns := a.Functions(); len(fns) > 0 {
			w("\n## Functions (%d)\n\n", len(fns))
			for _, d := range fns {
				w("- **%s** — %s\n", d.Name, orNone(d.Summary()))
			}
		}
		if al := a.Aliases(); len(al) > 0 {
			w("\n## Aliases (%d)\n\n", len(al))
			for _, d := range al {
				w("- **%s** → %s %s\n", d.Name, code(d.Value), dash(d.Summary()))
			}
		}
		if a.Help != "" {
			w("\n## About\n\n%s\n", a.Help)
		}
	case r.def != nil:
		d := r.def
		w("# %s\n\n", d.Name)
		if d.Doc != "" {
			w("%s\n\n", d.Doc)
		}
		w("Defined by addon **%s** (line %d) — %s.\n\n", d.Addon, d.Line, onOffMD(*r.on))
		if d.Kind == store.KindAlias {
			w("```zsh\nalias %s=%s\n```\n", d.Name, store.Quote(d.Value))
		} else {
			w("```zsh\n%s\n```\n", d.Value)
		}
		w("\n*Read-only here: press* `e` *to create your own override, or toggle the addon in the Addons tab.*\n")
	case r.item != nil:
		it := r.item
		w("# %s\n\n", it.Name)
		if it.Desc != "" {
			w("%s\n\n", it.Desc)
		}
		w("State: %s\n\n", onOffMD(it.Enabled))
		val := it.Value
		secret := r.source == string(store.KindSecret)
		if secret && !m.reveal[it.Name] && !m.revealAll {
			val = store.Mask(val)
		}
		switch r.source {
		case string(store.KindAlias):
			w("```zsh\nalias %s=%s\n```\n", it.Name, store.Quote(val))
		default:
			w("```zsh\nexport %s=%s\n```\n", it.Name, store.Quote(val))
		}
		if secret {
			w("\n*Masked — press* `v` *to reveal.* Stored in %s (mode 600).\n", code(m.p.Tilde(m.p.SecretsFile())))
		}
	case r.fn != nil:
		f := r.fn
		w("# %s\n\n%s\n\nState: %s · file %s\n\n```zsh\n%s\n```\n", f.Name, orNone(f.Desc), onOffMD(f.Enabled), code(m.p.Tilde(f.File)), strings.TrimRight(f.Raw, "\n"))
	case r.dir != nil:
		d := r.dir
		w("# %s\n\nscore **%.1f**", m.p.Tilde(d.Path), d.Score)
		if !d.Exists {
			w(" · ✘ directory no longer exists (press `p` to prune)")
		}
		w("\n\n")
		if d.Exists {
			if list := dirListing(d.Path, 30); list != "" {
				w("```\n%s\n```\n", list)
			}
		}
		w("\n`enter` jump · `d` forget · `x` exclude forever\n")
	case r.snap != nil:
		s := r.snap
		w("# %s\n\n- **created** %s\n- **reason** %s\n- **label** %s\n- **saved** %d paths · %s\n\n",
			s.ID, s.Created, orNone(s.Reason), orNone(s.Label), s.Items, s.Size)
		if out, ok := m.snapInfo[s.ID]; ok {
			w("%s\n", out)
		} else {
			w("*loading contents…*\n")
		}
		w("\n`r` restore (full revert) · `d` delete\n")
	}
	return b.String()
}

func orNone(s string) string {
	if s == "" {
		return "—"
	}
	return s
}

func dash(s string) string {
	if s == "" {
		return ""
	}
	return "— " + s
}

// itemHelp is the item-specific part shown on top of the tab help for F1.
func (m *model) itemHelp(r *row) string {
	if r == nil {
		return ""
	}
	switch {
	case r.addon != nil:
		a := r.addon
		h := fmt.Sprintf("# Addon: %s\n\n%s\n\n", a.Name, a.Desc)
		if a.Help != "" {
			h += a.Help + "\n\n"
		}
		if len(a.Examples) > 0 {
			h += "**Try:**\n\n"
			for _, e := range a.Examples {
				h += "- " + code(e) + "\n"
			}
			h += "\n"
		}
		if fns := a.Functions(); len(fns) > 0 {
			h += "**Commands it adds:** "
			var names []string
			for _, d := range fns {
				names = append(names, code(d.Name))
			}
			h += strings.Join(names, ", ") + "\n\n"
		}
		return h + "---\n\n"
	case r.def != nil:
		return fmt.Sprintf("# %s (from addon %s)\n\n%s\n\nThis is part of the **%s** addon, so it is read-only here. "+
			"Press `e` to copy it into your own %ss as an override, or switch the addon off in the Addons tab.\n\n---\n\n",
			r.def.Name, r.def.Addon, orNone(r.def.Doc), r.def.Addon, r.def.Kind)
	case r.item != nil && r.source == string(store.KindAlias):
		return fmt.Sprintf("# Alias %s\n\nTyping %s runs %s.\n\n---\n\n", r.name, code(r.name), code(r.item.Value))
	case r.fn != nil:
		return fmt.Sprintf("# Function %s\n\n%s\n\nCall it as %s. `e` edits here, `E` opens %s in $EDITOR.\n\n---\n\n",
			r.name, orNone(r.fn.Desc), code(r.name+" [args]"), code(m.p.Tilde(r.fn.File)))
	case r.snap != nil:
		return fmt.Sprintf("# Snapshot %s\n\nRestoring replaces every saved path with this copy and removes paths that did not exist then. "+
			"A `pre-restore` snapshot is taken first.\n\n---\n\n", r.snap.ID)
	}
	return ""
}
