// Package tui is the interactive `msh` interface: tabs for addons, aliases,
// functions, env, secrets, zoxide dirs and snapshots, with context help (F1),
// a command palette (:) and add/edit/toggle/delete for every item type.
package tui

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"

	"github.com/Szmelc-INC/Modern-Shell/internal/store"
)

type model struct {
	p    store.Paths
	conf map[string]string
	w, h int

	tab    int
	rows   [tabCount][]row
	loaded [tabCount]bool
	cursor [tabCount]int
	offset [tabCount]int
	filter [tabCount]string
	errs   [tabCount]string

	filtering bool
	filterIn  textinput.Model

	detail      viewport.Model
	detailKey   string
	focusDetail bool

	modal modal

	status    string
	statusErr bool
	statusAt  time.Time

	addons        []store.Addon
	showAddonDefs bool
	reveal        map[string]bool
	revealAll     bool
	snapInfo      map[string]string
	cdFile        string
	quitting      bool
}

// messages
type actionMsg struct {
	status string
	err    error
	reload []int
	tab    int // -1 keep
	selKey string
}
type snapInfoMsg struct{ id, md string }
type editorDoneMsg struct {
	err    error
	reload []int
	note   string
}

// Run starts the TUI.
func Run(p store.Paths, startTab string) error {
	m := newModel(p)
	if startTab == "" {
		startTab = m.conf["MSH_TUI_TAB"]
	}
	if t, ok := tabByName(startTab); ok {
		m.tab = t
	}
	if err := m.loadTab(m.tab); err != nil {
		m.errs[m.tab] = err.Error()
	}
	_, err := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion()).Run()
	return err
}

func newModel(p store.Paths) *model {
	fi := textinput.New()
	fi.Prompt = "/ "
	fi.PromptStyle = sFilter
	m := &model{p: p, conf: store.Conf(p), filterIn: fi, showAddonDefs: true,
		reveal: map[string]bool{}, snapInfo: map[string]string{}, cdFile: os.Getenv("MSH_CD_FILE")}
	if m.conf["MSH_TUI_ADDON_DEFS"] == "0" {
		m.showAddonDefs = false
	}
	return m
}

func (m *model) Init() tea.Cmd { return m.selectionChanged() }

// ── helpers ───────────────────────────────────────────────────────────────

func (m *model) visible() []int {
	var idx []int
	for i, r := range m.rows[m.tab] {
		if r.matches(m.filter[m.tab]) {
			idx = append(idx, i)
		}
	}
	return idx
}

func (m *model) selected() *row {
	vis := m.visible()
	c := m.cursor[m.tab]
	if c < 0 || c >= len(vis) {
		return nil
	}
	return &m.rows[m.tab][vis[c]]
}

func (m *model) setStatus(s string, isErr bool) {
	m.status, m.statusErr, m.statusAt = s, isErr, time.Now()
}

func (m *model) listHeight() int { return max(m.h-5, 3) }

func (m *model) clamp() {
	n := len(m.visible())
	c := &m.cursor[m.tab]
	if *c >= n {
		*c = n - 1
	}
	if *c < 0 {
		*c = 0
	}
	h := m.listHeight() - 2
	o := &m.offset[m.tab]
	if *c < *o {
		*o = *c
	}
	if *c >= *o+h {
		*o = *c - h + 1
	}
	if *o < 0 {
		*o = 0
	}
}

func (m *model) selectKey(key string) {
	for vi, i := range m.visible() {
		if m.rows[m.tab][i].key == key {
			m.cursor[m.tab] = vi
			return
		}
	}
}

// selectionChanged refreshes the detail pane and lazily loads snapshot info.
func (m *model) selectionChanged() tea.Cmd {
	m.clamp()
	m.detailKey = "" // force re-render
	r := m.selected()
	if r != nil && r.sess != nil {
		key := "sess:" + r.sess.Name
		if _, ok := m.snapInfo[key]; !ok {
			name, p := r.sess.Name, m.p
			return func() tea.Msg {
				show, _ := store.SessionCmd(p, "show", name)
				return snapInfoMsg{key, "## Windows\n\n```\n" + show + "\n```"}
			}
		}
	}
	if r != nil && r.snap != nil {
		if _, ok := m.snapInfo[r.snap.ID]; !ok {
			id, p := r.snap.ID, m.p
			return func() tea.Msg {
				show, _ := store.SnapshotCmd(p, "show", id)
				diff, _ := store.SnapshotCmd(p, "diff", id)
				return snapInfoMsg{id, "## Contents\n\n```\n" + show + "\n```\n\n## Changed since then\n\n```\n" + diff + "\n```"}
			}
		}
	}
	return nil
}

func (m *model) switchTab(t int) tea.Cmd {
	m.tab = (t + tabCount) % tabCount
	m.focusDetail, m.filtering = false, false
	if !m.loaded[m.tab] {
		if err := m.loadTab(m.tab); err != nil {
			m.errs[m.tab] = err.Error()
		} else {
			m.errs[m.tab] = ""
		}
	}
	return m.selectionChanged()
}

func (m *model) reload(tabs ...int) {
	if len(tabs) == 0 {
		for t := range tabCount {
			m.loaded[t] = false
		}
		m.addons = nil
		tabs = []int{m.tab}
	}
	for _, t := range tabs {
		if t == tabAddons || t == tabAliases || t == tabFunctions {
			m.addons = nil
		}
		if t == tabSnapshots || t == tabSessions {
			m.snapInfo = map[string]string{}
		}
		m.loaded[t] = false
		if err := m.loadTab(t); err != nil {
			m.errs[t] = err.Error()
		} else {
			m.errs[t] = ""
		}
	}
	// Tabs that show addon definitions depend on the addons tab.
	for _, t := range []int{tabAliases, tabFunctions} {
		if m.loaded[t] && m.addons == nil {
			m.loadTab(t)
		}
	}
}

func act(status string, err error, reload ...int) tea.Cmd {
	return func() tea.Msg { return actionMsg{status: status, err: err, reload: reload, tab: -1} }
}

// ── update ────────────────────────────────────────────────────────────────

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.detailKey = ""
		m.clamp()
		return m, nil
	case actionMsg:
		if msg.err != nil {
			m.setStatus("✘ "+msg.err.Error(), true)
		} else if msg.status != "" {
			m.setStatus("✔ "+msg.status, false)
		}
		if len(msg.reload) > 0 {
			key := msg.selKey
			if key == "" {
				if r := m.selected(); r != nil {
					key = r.key
				}
			}
			m.reload(msg.reload...)
			m.selectKey(key)
		}
		return m, m.selectionChanged()
	case editorDoneMsg:
		if msg.err != nil {
			m.setStatus("✘ editor: "+msg.err.Error(), true)
		} else if msg.note != "" {
			m.setStatus("✔ "+msg.note, false)
		}
		m.reload(msg.reload...)
		return m, m.selectionChanged()
	case snapInfoMsg:
		m.snapInfo[msg.id] = msg.md
		m.detailKey = ""
		return m, nil
	}

	if m.modal != nil {
		if k, ok := msg.(tea.KeyMsg); ok && k.String() == "f1" {
			if _, isText := m.modal.(*textModal); !isText {
				m.modal = newTextModal("Help", m.modal.helpText())
				return m, nil
			}
		}
		var cmd tea.Cmd
		m.modal, cmd = m.modal.update(m, msg)
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.MouseMsg:
		return m, m.mouse(msg)
	case tea.KeyMsg:
		if m.filtering {
			return m, m.filterKey(msg)
		}
		return m, m.key(msg)
	}
	return m, nil
}

func (m *model) filterKey(k tea.KeyMsg) tea.Cmd {
	switch k.String() {
	case "esc":
		m.filtering = false
		m.filter[m.tab] = ""
		m.filterIn.SetValue("")
		return m.selectionChanged()
	case "enter", "down", "up":
		m.filtering = false
		m.filterIn.Blur()
		return m.selectionChanged()
	}
	var cmd tea.Cmd
	m.filterIn, cmd = m.filterIn.Update(k)
	m.filter[m.tab] = m.filterIn.Value()
	m.cursor[m.tab] = 0
	return tea.Batch(cmd, m.selectionChanged())
}

func (m *model) key(k tea.KeyMsg) tea.Cmd {
	s := k.String()
	if m.focusDetail {
		switch s {
		case "esc", "enter", "q", "left", "h":
			m.focusDetail = false
			return nil
		case "j", "down":
			m.detail.ScrollDown(1)
			return nil
		case "k", "up":
			m.detail.ScrollUp(1)
			return nil
		case "pgdown", " ", "ctrl+d":
			m.detail.HalfPageDown()
			return nil
		case "pgup", "ctrl+u":
			m.detail.HalfPageUp()
			return nil
		case "g", "home":
			m.detail.GotoTop()
			return nil
		case "G", "end":
			m.detail.GotoBottom()
			return nil
		}
	}
	n := len(m.visible())
	switch s {
	case "ctrl+c", "q":
		m.quitting = true
		return tea.Quit
	case "tab", "right", "l":
		return m.switchTab(m.tab + 1)
	case "shift+tab", "left", "h":
		return m.switchTab(m.tab - 1)
	case "1", "2", "3", "4", "5", "6", "7", "8":
		return m.switchTab(int(s[0] - '1'))
	case "j", "down":
		m.cursor[m.tab]++
		return m.selectionChanged()
	case "k", "up":
		m.cursor[m.tab]--
		return m.selectionChanged()
	case "pgdown":
		m.cursor[m.tab] += m.listHeight() - 2
		return m.selectionChanged()
	case "pgup":
		m.cursor[m.tab] -= m.listHeight() - 2
		return m.selectionChanged()
	case "home", "g":
		m.cursor[m.tab] = 0
		return m.selectionChanged()
	case "end", "G":
		m.cursor[m.tab] = n - 1
		return m.selectionChanged()
	case "ctrl+d":
		m.detail.HalfPageDown()
	case "ctrl+u":
		m.detail.HalfPageUp()
	case "enter":
		if r := m.selected(); r != nil && r.dir != nil {
			return m.jump(r)
		}
		m.focusDetail = true
	case "/":
		m.filtering = true
		m.filterIn.SetValue(m.filter[m.tab])
		m.filterIn.Focus()
		return textinput.Blink
	case "esc":
		if m.filter[m.tab] != "" {
			m.filter[m.tab] = ""
			return m.selectionChanged()
		}
	case "f1":
		m.modal = newTextModal("Help — "+tabTitles[m.tab], m.itemHelp(m.selected())+tabHelp[m.tab])
	case "?":
		m.modal = newTextModal("Keys", keysHelp)
	case ":":
		m.modal = newPalette()
		return textinput.Blink
	case "ctrl+r", "f5":
		m.reload()
		m.setStatus("✔ reloaded", false)
		return m.selectionChanged()
	case " ":
		return m.toggle()
	case "a", "n", "insert":
		if s == "n" && m.tab != tabSnapshots && m.tab != tabSessions {
			return nil
		}
		return m.add()
	case "e":
		return m.edit(false)
	case "E":
		return m.edit(true)
	case "d", "delete":
		return m.remove()
	case "v":
		if r := m.selected(); r != nil && r.item != nil && m.tab == tabSecrets {
			m.reveal[r.name] = !m.reveal[r.name]
			key := r.key
			m.loadTab(tabSecrets)
			m.selectKey(key)
			return m.selectionChanged()
		}
	case "A":
		if m.tab == tabAliases || m.tab == tabFunctions {
			m.showAddonDefs = !m.showAddonDefs
			m.loadTab(m.tab)
			return m.selectionChanged()
		}
	case "r":
		if m.tab == tabSnapshots {
			return m.restore()
		}
		if m.tab == tabSessions {
			return m.restoreSession(false)
		}
	case "s":
		if m.tab == tabSessions {
			return m.restoreSession(true)
		}
	case "x":
		if m.tab == tabDirs {
			return m.exclude()
		}
	case "p":
		if m.tab == tabDirs {
			return m.prune()
		}
	}
	return nil
}

func (m *model) mouse(e tea.MouseMsg) tea.Cmd {
	switch e.Button {
	case tea.MouseButtonWheelUp:
		if m.inDetail(e.X) {
			m.detail.ScrollUp(3)
			return nil
		}
		m.cursor[m.tab]--
		return m.selectionChanged()
	case tea.MouseButtonWheelDown:
		if m.inDetail(e.X) {
			m.detail.ScrollDown(3)
			return nil
		}
		m.cursor[m.tab]++
		return m.selectionChanged()
	case tea.MouseButtonLeft:
		if e.Action != tea.MouseActionPress {
			return nil
		}
		if e.Y == 0 {
			x := lipgloss.Width(m.logo())
			for t := range tabCount {
				w := lipgloss.Width(m.tabLabel(t))
				if e.X >= x && e.X < x+w {
					return m.switchTab(t)
				}
				x += w
			}
			return nil
		}
		if !m.inDetail(e.X) && e.Y >= 3 && e.Y < 3+m.listHeight()-2 {
			m.cursor[m.tab] = m.offset[m.tab] + e.Y - 3
			m.focusDetail = false
			return m.selectionChanged()
		}
		if m.inDetail(e.X) {
			m.focusDetail = true
		}
	}
	return nil
}

func (m *model) inDetail(x int) bool { return m.wide() && x >= m.listWidth() }

// ── actions ───────────────────────────────────────────────────────────────

func (m *model) kindOfTab() store.Kind {
	return map[int]store.Kind{tabAliases: store.KindAlias, tabEnv: store.KindEnv, tabSecrets: store.KindSecret}[m.tab]
}

func (m *model) toggle() tea.Cmd {
	r := m.selected()
	if r == nil {
		return nil
	}
	switch {
	case r.addon != nil:
		on := !r.addon.Enabled
		err := store.SetAddonState(m.p, r.addon.Name, on)
		return act(fmt.Sprintf("%s %s — run 'reload' in open shells", r.name, onWord(on)), err, tabAddons, tabAliases, tabFunctions)
	case r.def != nil:
		m.setStatus(fmt.Sprintf("'%s' belongs to addon %s — toggle the addon (tab 1) or press e to override", r.name, r.def.Addon), true)
	case r.item != nil:
		mf, err := m.managed(m.kindOfTab())
		if err != nil {
			return act("", err)
		}
		on, err := mf.Toggle(r.name, nil)
		if err == nil {
			err = mf.Save()
		}
		return act(fmt.Sprintf("%s %s", r.name, onWord(on)), err, m.tab)
	case r.fn != nil:
		on, err := store.ToggleUserFunc(*r.fn, nil)
		return act(fmt.Sprintf("%s %s", r.name, onWord(on)), err, tabFunctions)
	case r.dir != nil:
		m.setStatus("zoxide directories have no on/off — d forgets, x excludes forever (F1)", true)
	case r.snap != nil:
		m.setStatus("snapshots have no on/off — r restores, d deletes (F1)", true)
	case r.sess != nil:
		m.setStatus("sessions have no on/off — r restores, s switches, d deletes (F1)", true)
	}
	return nil
}

func onWord(on bool) string {
	if on {
		return "enabled"
	}
	return "disabled"
}

func (m *model) add() tea.Cmd {
	switch m.tab {
	case tabAddons:
		m.modal = newForm("New addon", "addon", []*field{
			newField("Name", "", "lowercase-with-dashes"),
			newField("Description", "", "one line"),
			newField("Tags", "DEV", "comma separated, e.g. FILES, GIT"),
		}, func(v []string) (tea.Cmd, error) {
			path, err := store.NewUserAddon(m.p, strings.TrimSpace(v[0]), strings.TrimSpace(v[1]), strings.TrimSpace(v[2]))
			if err != nil {
				return nil, err
			}
			return m.editor(path, "addon "+v[0]+" created", tabAddons, tabAliases, tabFunctions), nil
		})
	case tabAliases, tabEnv, tabSecrets:
		m.modal = m.itemForm(nil, "")
	case tabFunctions:
		m.modal = m.funcForm(nil, "")
	case tabDirs:
		cwd, _ := os.Getwd()
		m.modal = newForm("Add directory to zoxide", "dir", []*field{newField("Path", m.p.Tilde(cwd), "absolute or ~/…")},
			func(v []string) (tea.Cmd, error) {
				p := expandHome(m.p, strings.TrimSpace(v[0]))
				if err := store.AddDir(p); err != nil {
					return nil, err
				}
				return func() tea.Msg {
					return actionMsg{status: "added " + m.p.Tilde(p), reload: []int{tabDirs}, tab: -1, selKey: "dir:" + p}
				}, nil
			})
	case tabSessions:
		m.modal = newForm("Save desktop session", "session", []*field{
			newField("Name", "", "e.g. work, music (empty = timestamp; same name replaces)"),
			newField("Note", "", "optional")},
			func(v []string) (tea.Cmd, error) {
				name, note := strings.TrimSpace(v[0]), strings.TrimSpace(v[1])
				m.setStatus("saving the desktop session…", false)
				return func() tea.Msg {
					args := []string{"save", "-y"}
					if name != "" {
						args = append(args, name)
					}
					if note != "" {
						args = append(args, "-m", note)
					}
					out, err := store.SessionCmd(m.p, args...)
					return actionMsg{status: firstLine(out), err: err, reload: []int{tabSessions}, tab: -1}
				}, nil
			})
	case tabSnapshots:
		m.modal = newForm("Create snapshot", "snapshot", []*field{newField("Label", "", "optional, e.g. before-experiment")},
			func(v []string) (tea.Cmd, error) {
				label := strings.TrimSpace(v[0])
				m.setStatus("creating snapshot…", false)
				return func() tea.Msg {
					args := []string{"create", "-r", "msh tui"}
					if label != "" {
						args = append(args, "-l", label)
					}
					out, err := store.SnapshotCmd(m.p, args...)
					return actionMsg{status: lastLine(out), err: err, reload: []int{tabSnapshots}, tab: -1}
				}, nil
			})
	}
	return nil
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return strings.TrimLeft(lines[len(lines)-1], "✔ ")
}

// itemForm builds the add/edit form for aliases, env vars and secrets.
func (m *model) itemForm(existing *store.Item, prefillFrom string) modal {
	kind := m.kindOfTab()
	it := store.Item{Enabled: true}
	oldName := ""
	title := "New " + string(kind)
	if existing != nil {
		it = *existing
		if prefillFrom == "" {
			oldName, title = it.Name, "Edit "+string(kind)+" "+it.Name
		} else {
			title = "Override " + it.Name + " (from addon " + prefillFrom + ")"
		}
	}
	valueLabel := map[store.Kind]string{store.KindAlias: "Command", store.KindEnv: "Value", store.KindSecret: "Value"}[kind]
	var valueField *field
	if kind == store.KindSecret {
		valueField = newSecretField(valueLabel, it.Value, "hidden · ctrl+r shows")
	} else {
		valueField = newField(valueLabel, it.Value, map[store.Kind]string{store.KindAlias: "what it expands to", store.KindEnv: "stored literally"}[kind])
	}
	return newForm(title, string(kind), []*field{
		newField("Name", it.Name, map[store.Kind]string{store.KindAlias: "what you type", store.KindEnv: "UPPER_CASE", store.KindSecret: "e.g. GITHUB_TOKEN"}[kind]),
		valueField,
		newField("Description", it.Desc, "optional"),
	}, func(v []string) (tea.Cmd, error) {
		mf, err := m.managed(kind)
		if err != nil {
			return nil, err
		}
		name := strings.TrimSpace(v[0])
		if name == "" {
			return nil, fmt.Errorf("name is required")
		}
		if _, exists := mf.Get(name); exists && name != oldName {
			return nil, fmt.Errorf("%s %q already exists — edit that one instead", kind, name)
		}
		nit := store.Item{Name: name, Value: v[1], Desc: strings.TrimSpace(v[2]), Enabled: it.Enabled}
		if err := mf.Set(oldName, nit); err != nil {
			return nil, err
		}
		if err := mf.Save(); err != nil {
			return nil, err
		}
		return func() tea.Msg {
			return actionMsg{status: fmt.Sprintf("%s %s saved — new shells pick it up", kind, name), reload: []int{m.tab}, tab: -1, selKey: string(kind) + ":" + name}
		}, nil
	})
}

func (m *model) funcForm(existing *store.UserFunc, fromAddon string) modal {
	uf := store.UserFunc{Enabled: true, Body: "# $1, $2… are the arguments\nmsh::ok \"hello\""}
	oldName, title := "", "New function"
	if existing != nil {
		uf = *existing
		if fromAddon == "" {
			oldName, title = uf.Name, "Edit function "+uf.Name
		} else {
			title = "Override " + uf.Name + " (from addon " + fromAddon + ")"
		}
	}
	return newForm(title, "function", []*field{
		newField("Name", uf.Name, "how you call it"),
		newField("Description", uf.Desc, "one line"),
		newAreaField("Body", uf.Body, "code inside name() { … } — enter = newline, ctrl+s saves"),
	}, func(v []string) (tea.Cmd, error) {
		nf := store.UserFunc{Name: strings.TrimSpace(v[0]), Desc: strings.TrimSpace(v[1]), Body: v[2], Enabled: uf.Enabled}
		if nf.Name == "" {
			return nil, fmt.Errorf("name is required")
		}
		if oldName != nf.Name {
			if _, err := store.FindUserFunc(m.p, nf.Name); err == nil {
				return nil, fmt.Errorf("function %q already exists", nf.Name)
			}
		}
		if err := store.SaveUserFunc(m.p, oldName, nf); err != nil {
			return nil, err
		}
		return func() tea.Msg {
			return actionMsg{status: "function " + nf.Name + " saved", reload: []int{tabFunctions}, tab: -1, selKey: "func:" + nf.Name}
		}, nil
	})
}

func (m *model) edit(external bool) tea.Cmd {
	r := m.selected()
	if r == nil {
		return nil
	}
	switch {
	case r.addon != nil:
		path, err := store.OverrideAddon(m.p, *r.addon)
		if err != nil {
			return act("", err)
		}
		note := "saved " + r.name
		if !r.addon.User {
			note = "your copy of " + r.name + " is in " + m.p.Tilde(path) + " (it wins over the shipped one)"
		}
		return m.editor(path, note, tabAddons, tabAliases, tabFunctions)
	case r.def != nil && r.def.Kind == store.KindAlias:
		m.modal = m.itemForm(&store.Item{Name: r.def.Name, Value: r.def.Value, Desc: r.def.Summary(), Enabled: true}, r.def.Addon)
	case r.def != nil:
		m.modal = m.funcForm(&store.UserFunc{Name: r.def.Name, Desc: r.def.Summary(), Body: store.FuncInner(r.def.Name, r.def.Value), Enabled: true}, r.def.Addon)
	case r.item != nil:
		m.modal = m.itemForm(r.item, "")
	case r.fn != nil:
		if external {
			return m.editor(r.fn.File, "saved "+r.name, tabFunctions)
		}
		m.modal = m.funcForm(r.fn, "")
	case r.snap != nil, r.dir != nil, r.sess != nil:
		m.setStatus("nothing to edit here — F1 shows what you can do", true)
	}
	return nil
}

func (m *model) editor(path, note string, reload ...int) tea.Cmd {
	ed := os.Getenv("VISUAL")
	if ed == "" {
		ed = os.Getenv("EDITOR")
	}
	if ed == "" {
		ed = "nano"
	}
	parts := strings.Fields(ed)
	c := exec.Command(parts[0], append(parts[1:], path)...)
	return tea.ExecProcess(c, func(err error) tea.Msg { return editorDoneMsg{err: err, reload: reload, note: note} })
}

func (m *model) confirm(title, body string, danger bool, yes func() tea.Cmd) {
	m.modal = &confirmModal{title: title, body: body, danger: danger, yes: yes}
}

func (m *model) remove() tea.Cmd {
	r := m.selected()
	if r == nil {
		return nil
	}
	switch {
	case r.addon != nil && !r.addon.User:
		m.setStatus(r.name+" is shipped with msh — switch it off with space instead", true)
	case r.addon != nil:
		a := *r.addon
		extra := ""
		if a.Overrides {
			extra = "\n\nThe shipped version of this addon will be used again."
		}
		m.confirm("Delete addon "+a.Name+"?", "Removes "+m.p.Tilde(a.File)+"."+extra, true, func() tea.Cmd {
			return act("deleted addon "+a.Name, store.DeleteUserAddon(m.p, a), tabAddons, tabAliases, tabFunctions)
		})
	case r.def != nil:
		m.setStatus("'"+r.name+"' comes from addon "+r.def.Addon+" — disable the addon instead", true)
	case r.item != nil:
		kind, name, tab := m.kindOfTab(), r.name, m.tab
		m.confirm(fmt.Sprintf("Delete %s %s?", kind, name), "It is removed from "+m.p.Tilde(m.managedPath(kind))+".\nTip: space switches it off instead.", true, func() tea.Cmd {
			mf, err := m.managed(kind)
			if err == nil {
				if err = mf.Delete(name); err == nil {
					err = mf.Save()
				}
			}
			return act(fmt.Sprintf("deleted %s %s", kind, name), err, tab)
		})
	case r.fn != nil:
		f := *r.fn
		m.confirm("Delete function "+f.Name+"?", "Removes "+m.p.Tilde(f.File)+".", true, func() tea.Cmd {
			return act("deleted function "+f.Name, os.Remove(f.File), tabFunctions)
		})
	case r.dir != nil:
		d := *r.dir
		m.confirm("Forget "+m.p.Tilde(d.Path)+"?", "zoxide forgets it until you visit it again.\nUse x to exclude it forever.", false, func() tea.Cmd {
			return act("forgot "+m.p.Tilde(d.Path), store.RemoveDir(d.Path), tabDirs)
		})
	case r.sess != nil:
		name := r.sess.Name
		m.confirm("Delete session "+name+"?", "The snapshot and its saved unsaved-data copies are removed from "+
			m.p.Tilde(r.sess.Path)+".", true, func() tea.Cmd {
			return func() tea.Msg {
				out, err := store.SessionCmd(m.p, "rm", name, "-y")
				return actionMsg{status: lastLine(out), err: err, reload: []int{tabSessions}, tab: -1}
			}
		})
	case r.snap != nil:
		id := r.snap.ID
		m.confirm("Delete snapshot "+id+"?", "This backup is removed permanently from "+m.p.Tilde(m.p.Backup)+".", true, func() tea.Cmd {
			return func() tea.Msg {
				out, err := store.SnapshotCmd(m.p, "rm", id, "-y")
				return actionMsg{status: lastLine(out), err: err, reload: []int{tabSnapshots}, tab: -1}
			}
		})
	}
	return nil
}

func (m *model) managedPath(k store.Kind) string {
	switch k {
	case store.KindAlias:
		return m.p.AliasesFile()
	case store.KindEnv:
		return m.p.EnvFile()
	}
	return m.p.SecretsFile()
}

func (m *model) restore() tea.Cmd {
	r := m.selected()
	if r == nil || r.snap == nil {
		return nil
	}
	id := r.snap.ID
	m.confirm("Restore snapshot "+id+"?",
		"Every saved path (~/.zshrc, ~/.config/msh, ~/.nanorc, ~/.tmux.conf, msh binary, completions) is replaced by this copy, "+
			"and paths that did not exist then are removed.\n\nA pre-restore snapshot is taken first, so you can undo this. "+
			"Open shells keep running the old config until 'reload'.", true, func() tea.Cmd {
			m.setStatus("restoring "+id+"…", false)
			return func() tea.Msg {
				out, err := store.SnapshotCmd(m.p, "restore", id, "-y")
				return actionMsg{status: lastLine(out), err: err, reload: []int{tabSnapshots, tabAddons, tabAliases, tabFunctions, tabEnv, tabSecrets}, tab: -1}
			}
		})
	return nil
}

// restoreSession restores (or, with switching, switches to) the selected desktop session.
func (m *model) restoreSession(switching bool) tea.Cmd {
	r := m.selected()
	if r == nil || r.sess == nil {
		return nil
	}
	name, verb, body := r.sess.Name, "Restore", "Windows of this session that are open are reused and moved back; "+
		"missing ones are launched. Nothing else is closed."
	if switching {
		verb, body = "Switch to", "Windows that are NOT in this session are closed (apps may ask to save), then it is restored.\n\n"+
			"The current session is saved as an automatic snapshot first, so you can switch back."
	}
	m.confirm(verb+" session "+name+"?", body, switching, func() tea.Cmd {
		m.setStatus(strings.ToLower(verb)+" "+name+"…", false)
		return func() tea.Msg {
			sub := "restore"
			if switching {
				sub = "switch"
			}
			out, err := store.SessionCmd(m.p, sub, name, "-y")
			return actionMsg{status: lastLine(out), err: err, reload: []int{tabSessions}, tab: -1}
		}
	})
	return nil
}

func firstLine(s string) string {
	return strings.SplitN(strings.TrimSpace(s), "\n", 2)[0]
}

func (m *model) exclude() tea.Cmd {
	r := m.selected()
	if r == nil || r.dir == nil {
		return nil
	}
	path := r.dir.Path
	m.confirm("Exclude "+m.p.Tilde(path)+" forever?", "It is added to _ZO_EXCLUDE_DIRS in your Env tab and removed from zoxide.\nUndo by editing that variable.", false, func() tea.Cmd {
		return act("excluded "+m.p.Tilde(path)+" (new shells)", store.ExcludeDir(m.p, path), tabDirs, tabEnv)
	})
	return nil
}

func (m *model) prune() tea.Cmd {
	var missing []string
	for _, r := range m.rows[tabDirs] {
		if r.dir != nil && !r.dir.Exists {
			missing = append(missing, r.dir.Path)
		}
	}
	if len(missing) == 0 {
		m.setStatus("no missing directories", false)
		return nil
	}
	m.confirm(fmt.Sprintf("Forget %d missing directories?", len(missing)), strings.Join(missing, "\n"), false, func() tea.Cmd {
		var err error
		for _, p := range missing {
			if e := store.RemoveDir(p); e != nil {
				err = e
			}
		}
		return act(fmt.Sprintf("pruned %d", len(missing)), err, tabDirs)
	})
	return nil
}

func (m *model) jump(r *row) tea.Cmd {
	if m.cdFile == "" {
		m.setStatus("start msh from zsh (the msh wrapper) to jump — or run: cd "+m.p.Tilde(r.dir.Path), true)
		return nil
	}
	if err := os.WriteFile(m.cdFile, []byte(r.dir.Path), 0o600); err != nil {
		return act("", err)
	}
	m.quitting = true
	return tea.Quit
}

func (m *model) runPalette(cmd, arg string) tea.Cmd {
	if t, ok := tabByName(cmd); ok && cmd != "add" && cmd != "all" {
		return m.switchTab(t)
	}
	switch cmd {
	case "add":
		return m.add()
	case "edit":
		return m.edit(false)
	case "delete":
		return m.remove()
	case "toggle":
		return m.toggle()
	case "filter":
		m.filter[m.tab] = arg
		m.cursor[m.tab] = 0
		return m.selectionChanged()
	case "clear":
		m.filter[m.tab] = ""
		return m.selectionChanged()
	case "all":
		m.showAddonDefs = !m.showAddonDefs
		m.loaded[tabAliases], m.loaded[tabFunctions] = false, false
		m.loadTab(m.tab)
		return m.selectionChanged()
	case "reveal":
		m.revealAll = !m.revealAll
		m.loadTab(tabSecrets)
		return m.selectionChanged()
	case "snapshot":
		m.setStatus("creating snapshot…", false)
		return func() tea.Msg {
			args := []string{"create", "-r", "msh tui"}
			if arg != "" {
				args = append(args, "-l", arg)
			}
			out, err := store.SnapshotCmd(m.p, args...)
			return actionMsg{status: lastLine(out), err: err, reload: []int{tabSnapshots}, tab: -1}
		}
	case "session-save":
		m.setStatus("saving the desktop session…", false)
		return func() tea.Msg {
			args := []string{"save", "-y"}
			if arg != "" {
				args = append(args, arg)
			}
			out, err := store.SessionCmd(m.p, args...)
			return actionMsg{status: firstLine(out), err: err, reload: []int{tabSessions}, tab: -1}
		}
	case "edit-config":
		return m.editor(m.p.ConfFile(), "saved msh.conf — new shells pick it up")
	case "edit-local":
		return m.editor(m.p.LocalFile(), "saved local.zsh — new shells pick it up")
	case "reload":
		m.reload()
		return act("reloaded", nil)
	case "help":
		m.modal = newTextModal("Help — "+tabTitles[m.tab], m.itemHelp(m.selected())+tabHelp[m.tab])
	case "keys":
		m.modal = newTextModal("Keys", keysHelp)
	case "quit":
		m.quitting = true
		return tea.Quit
	default:
		m.setStatus("unknown command: "+cmd+" (F1 in the palette lists them)", true)
	}
	return nil
}

// ── view ──────────────────────────────────────────────────────────────────

func (m *model) wide() bool     { return m.w >= 100 }
func (m *model) listWidth() int { return max(m.w*44/100, 40) }
func (m *model) logo() string   { return sLogo.Render("◆ msh") + " " }
func (m *model) tabLabel(t int) string {
	label := fmt.Sprintf("%d %s", t+1, tabTitles[t])
	count := ""
	if m.loaded[t] {
		count = " " + strconv.Itoa(len(m.rows[t]))
	}
	if t == m.tab {
		// No nested styles here: underline is applied per rune and would split escapes.
		return sTabActive.Render(label + count)
	}
	return sTab.Render(label + sTabCount.Render(count))
}

func (m *model) View() string {
	if m.quitting || m.w == 0 {
		return ""
	}
	header := m.logo()
	for t := range tabCount {
		header += m.tabLabel(t)
	}
	if v := m.p.Version(); v != "" && lipgloss.Width(header)+len(v)+3 < m.w {
		header += strings.Repeat(" ", m.w-lipgloss.Width(header)-len(v)-2) + sVersion.Render("v"+v)
	}
	header = lipgloss.NewStyle().MaxWidth(m.w).Render(header)

	bodyH := m.h - 3
	var body string
	if m.wide() {
		lw := m.listWidth()
		body = lipgloss.JoinHorizontal(lipgloss.Top, m.listView(lw, bodyH), m.detailView(m.w-lw, bodyH))
	} else if m.focusDetail {
		body = m.detailView(m.w, bodyH)
	} else {
		body = m.listView(m.w, bodyH)
	}
	view := lipgloss.JoinVertical(lipgloss.Left, header, "", body, m.footer())

	if m.modal != nil {
		box := m.modal.view(m.w, m.h)
		return placeOver(view, box, m.w, m.h)
	}
	return view
}

func (m *model) listView(w, h int) string {
	style := sPane
	if !m.focusDetail {
		style = sPaneActive
	}
	inner := w - 2
	lines := []string{}
	title := sPaneTitle.Render(tabTitles[m.tab])
	if f := m.filter[m.tab]; f != "" || m.filtering {
		if m.filtering {
			title += "  " + m.filterIn.View()
		} else {
			title += "  " + sFilter.Render("/"+f)
		}
	}
	vis := m.visible()
	title += sRowDesc.Render(fmt.Sprintf("  %d/%d", min(m.cursor[m.tab]+1, len(vis)), len(vis)))
	lines = append(lines, lipgloss.NewStyle().MaxWidth(inner).Render(title))

	if e := m.errs[m.tab]; e != "" {
		lines = append(lines, sStatusEr.Render("✘ "+e))
	}
	if len(vis) == 0 && m.errs[m.tab] == "" {
		lines = append(lines, "", sHint.Render(emptyHint(m.tab, m.filter[m.tab] != "")))
	}
	rowsH := h - 3
	start := m.offset[m.tab]
	for i := start; i < len(vis) && i < start+rowsH; i++ {
		lines = append(lines, m.rowLine(&m.rows[m.tab][vis[i]], i == m.cursor[m.tab], inner))
	}
	for len(lines) < h-2 {
		lines = append(lines, "")
	}
	return style.Width(inner).Height(h - 2).Render(strings.Join(lines[:h-2], "\n"))
}

func emptyHint(t int, filtered bool) string {
	if filtered {
		return "nothing matches the filter — esc clears it"
	}
	switch t {
	case tabAliases:
		return "no aliases yet — press a to add one"
	case tabFunctions:
		return "no functions yet — press a to write one"
	case tabEnv:
		return "no variables yet — press a to add one"
	case tabSecrets:
		return "no secrets yet — press a to add one (stored mode 600)"
	case tabDirs:
		return "zoxide has no directories yet — cd around, or press a"
	case tabSnapshots:
		return "no snapshots yet — press a to create one"
	case tabSessions:
		return "no desktop sessions yet — press a to save the current one"
	}
	return "nothing here"
}

func (m *model) rowLine(r *row, sel bool, w int) string {
	mark := "  "
	switch {
	case r.on != nil && *r.on:
		mark = sOn.Render("● ")
	case r.on != nil:
		mark = sOff.Render("○ ")
	case r.dir != nil && !r.dir.Exists:
		mark = sStatusEr.Render("✘ ")
	case r.snap != nil:
		mark = sRowDesc.Render("◷ ")
	case r.sess != nil && r.sess.Active:
		mark = sOn.Render("● ")
	case r.sess != nil:
		mark = sRowDesc.Render("▣ ")
	case r.dir != nil:
		mark = sRowDesc.Render("▸ ")
	}
	nameW := min(max(w/3, 12), 28)
	name := truncate(r.name, nameW)
	src := ""
	if r.def != nil {
		src = sRO.Render(" ⌁" + strings.TrimPrefix(r.source, "addon:"))
	} else if r.addon != nil && r.source != "shipped" {
		src = sRO.Render(" " + r.source)
	}
	rest := r.value
	if r.desc != "" {
		if rest != "" {
			rest += " — "
		}
		rest += r.desc
	}
	restW := w - 3 - nameW - lipgloss.Width(src) - 2
	if sel {
		line := "▌" + strings.TrimSpace(stripANSI(mark)) + " " + pad(name, nameW) + stripANSI(src) + "  " + truncate(rest, max(restW, 0))
		return sRowSel.Width(w).Render(line)
	}
	return " " + mark + sRowName.Render(pad(name, nameW)) + src + "  " + sRowValue.Render(truncate(rest, max(restW, 0)))
}

func (m *model) detailView(w, h int) string {
	style := sPane
	if m.focusDetail {
		style = sPaneActive
	}
	inner := w - 2
	r := m.selected()
	key := fmt.Sprintf("tab:%d|%d", m.tab, w) // empty tab: show the tab's help, not stale details
	if r != nil {
		key = fmt.Sprintf("%s|%d|%v|%v|%d", r.key, w, m.reveal[r.name], m.revealAll, len(m.snapInfo))
	}
	if m.detail.Width != inner-2 || m.detail.Height != h-3 {
		m.detail = viewport.New(inner-2, h-3)
		m.detailKey = ""
	}
	if key != m.detailKey {
		md := tabHelp[m.tab]
		if r != nil {
			md = m.detailMD(r)
		}
		m.detail.SetContent(renderMarkdown(md, inner-4))
		m.detail.GotoTop()
		m.detailKey = key
	}
	title := sPaneTitle.Render("Details")
	if m.detail.TotalLineCount() > m.detail.Height {
		title += sRowDesc.Render(fmt.Sprintf("  %d%%", int(m.detail.ScrollPercent()*100)))
	}
	return style.Width(inner).Height(h - 2).Render(" " + title + "\n" + m.detail.View())
}

func (m *model) footer() string {
	if m.status != "" && time.Since(m.statusAt) < 8*time.Second {
		st := sStatusOK
		if m.statusErr {
			st = sStatusEr
		}
		return lipgloss.NewStyle().MaxWidth(m.w).Render(" " + st.Render(m.status))
	}
	k := func(key, label string) string { return sKey.Render(key) + sFooter.Render(" "+label+"  ") }
	var parts []string
	switch m.tab {
	case tabSnapshots:
		parts = []string{k("a", "create"), k("r", "restore"), k("d", "delete")}
	case tabSessions:
		parts = []string{k("a", "save"), k("r", "restore"), k("s", "switch"), k("d", "delete")}
	case tabDirs:
		parts = []string{k("enter", "jump"), k("a", "add"), k("d", "forget"), k("x", "exclude"), k("p", "prune")}
	case tabSecrets:
		parts = []string{k("␣", "on/off"), k("a", "add"), k("e", "edit"), k("v", "reveal"), k("d", "delete")}
	default:
		parts = []string{k("␣", "on/off"), k("a", "add"), k("e", "edit"), k("d", "delete")}
		if m.tab == tabAliases || m.tab == tabFunctions {
			parts = append(parts, k("A", "addon items"))
		}
	}
	parts = append(parts, k("/", "filter"), k("F1", "help"), k("?", "keys"), k(":", "cmd"), k("q", "quit"))
	return lipgloss.NewStyle().MaxWidth(m.w).Render(" " + strings.Join(parts, ""))
}

// ── rendering helpers ─────────────────────────────────────────────────────

var mdCache = map[string]string{}

func renderMarkdown(md string, width int) string {
	width = max(width, 20)
	key := strconv.Itoa(width) + "\x00" + md
	if out, ok := mdCache[key]; ok {
		return out
	}
	style := "dark"
	if s := os.Getenv("MSH_TUI_THEME"); s != "" {
		style = s
	}
	r, err := glamour.NewTermRenderer(glamour.WithStandardStyle(style), glamour.WithWordWrap(width))
	if err != nil {
		return md
	}
	out, err := r.Render(md)
	if err != nil {
		return md
	}
	out = strings.Trim(out, "\n")
	if len(mdCache) > 300 {
		mdCache = map[string]string{}
	}
	mdCache[key] = out
	return out
}

func truncate(s string, w int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if lipgloss.Width(s) <= w {
		return s
	}
	if w <= 1 {
		return ""
	}
	r := []rune(s)
	for len(r) > 0 && lipgloss.Width(string(r)) > w-1 {
		r = r[:len(r)-1]
	}
	return string(r) + "…"
}

func pad(s string, w int) string {
	return s + strings.Repeat(" ", max(w-lipgloss.Width(s), 0))
}

func stripANSI(s string) string {
	var b strings.Builder
	in := false
	for _, c := range s {
		switch {
		case c == '\x1b':
			in = true
		case in && (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'):
			in = false
		case !in:
			b.WriteRune(c)
		}
	}
	return b.String()
}

func itoa(n int) string { return strconv.Itoa(n) }

// placeOver centers box on top of the base view.
func placeOver(base, box string, w, h int) string {
	baseLines := strings.Split(base, "\n")
	for len(baseLines) < h {
		baseLines = append(baseLines, "")
	}
	boxLines := strings.Split(box, "\n")
	bw := lipgloss.Width(box)
	top := max((h-len(boxLines))/2, 0)
	left := max((w-bw)/2, 0)
	for i, bl := range boxLines {
		y := top + i
		if y >= len(baseLines) {
			break
		}
		baseLines[y] = strings.Repeat(" ", left) + bl
	}
	return strings.Join(baseLines[:h], "\n")
}

func expandHome(p store.Paths, s string) string {
	if strings.HasPrefix(s, "~/") || s == "~" {
		return filepath.Join(p.HomeDir, strings.TrimPrefix(s, "~"))
	}
	if abs, err := filepath.Abs(s); err == nil {
		return abs
	}
	return s
}

func dirListing(path string, limit int) string {
	entries, err := os.ReadDir(path)
	if err != nil {
		return ""
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir() != entries[j].IsDir() {
			return entries[i].IsDir()
		}
		return entries[i].Name() < entries[j].Name()
	})
	var out []string
	for i, e := range entries {
		if i >= limit {
			out = append(out, fmt.Sprintf("… %d more", len(entries)-limit))
			break
		}
		n := e.Name()
		if e.IsDir() {
			n += "/"
		}
		out = append(out, n)
	}
	return strings.Join(out, "\n")
}
