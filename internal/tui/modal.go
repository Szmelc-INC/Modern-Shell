package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// modal is a dialog drawn over the main view; it owns all keys while open.
type modal interface {
	update(m *model, msg tea.Msg) (modal, tea.Cmd) // return nil modal to close
	view(w, h int) string
	helpText() string
}

// ── form ──────────────────────────────────────────────────────────────────

type field struct {
	label  string
	hint   string
	input  textinput.Model
	area   *textarea.Model // multi-line field when set
	secret bool
}

func (f *field) value() string {
	if f.area != nil {
		return f.area.Value()
	}
	return f.input.Value()
}

type formModal struct {
	title   string
	helpKey string
	fields  []*field
	focus   int
	err     string
	submit  func(vals []string) (tea.Cmd, error) // error keeps the form open
	width   int
}

func newField(label, value, hint string) *field {
	ti := textinput.New()
	ti.SetValue(value)
	ti.Prompt = ""
	ti.CharLimit = 4096
	ti.Cursor.Style = lipgloss.NewStyle().Foreground(cAccentAlt)
	return &field{label: label, hint: hint, input: ti}
}

func newSecretField(label, value, hint string) *field {
	f := newField(label, value, hint)
	f.secret = true
	f.input.EchoMode = textinput.EchoPassword
	f.input.EchoCharacter = '•'
	return f
}

func newAreaField(label, value, hint string) *field {
	f := newField(label, "", hint)
	ta := textarea.New()
	ta.SetValue(value)
	ta.ShowLineNumbers = true
	ta.Prompt = ""
	ta.CharLimit = 0
	ta.MaxHeight = 0
	ta.FocusedStyle.CursorLine = lipgloss.NewStyle().Background(cBgAlt)
	f.area = &ta
	return f
}

func newForm(title, helpKey string, fields []*field, submit func([]string) (tea.Cmd, error)) *formModal {
	fm := &formModal{title: title, helpKey: helpKey, fields: fields, submit: submit}
	fm.setFocus(0)
	return fm
}

func (f *formModal) setFocus(i int) {
	f.focus = (i + len(f.fields)) % len(f.fields)
	for j, fl := range f.fields {
		if fl.area != nil {
			if j == f.focus {
				fl.area.Focus()
			} else {
				fl.area.Blur()
			}
			continue
		}
		if j == f.focus {
			fl.input.Focus()
			fl.input.CursorEnd()
		} else {
			fl.input.Blur()
		}
	}
}

func (f *formModal) helpText() string {
	if h, ok := formHelp[f.helpKey]; ok {
		return h
	}
	return "# Form\n\n`tab` next field · `ctrl+s` save · `esc` cancel"
}

func (f *formModal) update(m *model, msg tea.Msg) (modal, tea.Cmd) {
	cur := f.fields[f.focus]
	if k, ok := msg.(tea.KeyMsg); ok {
		switch k.String() {
		case "esc":
			return nil, nil
		case "tab", "down":
			if cur.area == nil || k.String() == "tab" {
				f.setFocus(f.focus + 1)
				return f, nil
			}
		case "shift+tab", "up":
			if cur.area == nil || k.String() == "shift+tab" {
				f.setFocus(f.focus - 1)
				return f, nil
			}
		case "ctrl+r":
			if cur.secret {
				if cur.input.EchoMode == textinput.EchoPassword {
					cur.input.EchoMode = textinput.EchoNormal
				} else {
					cur.input.EchoMode = textinput.EchoPassword
				}
				return f, nil
			}
		case "ctrl+s":
			return f.save()
		case "enter":
			if cur.area == nil {
				if f.focus == len(f.fields)-1 {
					return f.save()
				}
				f.setFocus(f.focus + 1)
				return f, nil
			}
		}
	}
	var cmd tea.Cmd
	if cur.area != nil {
		var ta textarea.Model
		ta, cmd = cur.area.Update(msg)
		cur.area = &ta
	} else {
		cur.input, cmd = cur.input.Update(msg)
	}
	f.err = ""
	return f, cmd
}

func (f *formModal) save() (modal, tea.Cmd) {
	vals := make([]string, len(f.fields))
	for i, fl := range f.fields {
		vals[i] = fl.value()
	}
	cmd, err := f.submit(vals)
	if err != nil {
		f.err = err.Error()
		return f, nil
	}
	return nil, cmd
}

func (f *formModal) view(w, h int) string {
	width := min(max(w-10, 40), 100)
	inner := width - 6
	var b strings.Builder
	b.WriteString(sModalTitle.Render(f.title) + "\n\n")
	for i, fl := range f.fields {
		ls := sLabel
		if i == f.focus {
			ls = sLabelFocus
		}
		b.WriteString(ls.Render(fl.label))
		if fl.hint != "" {
			b.WriteString("  " + sHint.Render(fl.hint))
		}
		b.WriteString("\n")
		if fl.area != nil {
			fl.area.SetWidth(inner)
			fl.area.SetHeight(max(min(h-16-2*len(f.fields), 18), 4))
			b.WriteString(fl.area.View() + "\n\n")
			continue
		}
		fl.input.Width = inner - 2
		box := lipgloss.NewStyle().Border(lipgloss.NormalBorder(), false, false, true, false).BorderForeground(cBorder)
		if i == f.focus {
			box = box.BorderForeground(cAccent)
		}
		b.WriteString(box.Width(inner).Render(fl.input.View()) + "\n")
	}
	if f.err != "" {
		b.WriteString("\n" + sErr.Render("✘ "+f.err) + "\n")
	}
	keys := "tab next · ctrl+s save · esc cancel · F1 help"
	for _, fl := range f.fields {
		if fl.secret {
			keys = "tab next · ctrl+r show/hide · ctrl+s save · esc cancel · F1 help"
		}
	}
	b.WriteString("\n" + sHint.Render(keys))
	return sModal.Width(width).Render(b.String())
}

// ── confirm ───────────────────────────────────────────────────────────────

type confirmModal struct {
	title, body string
	danger      bool
	yes         func() tea.Cmd
}

func (c *confirmModal) helpText() string { return confirmHelp }

func (c *confirmModal) update(m *model, msg tea.Msg) (modal, tea.Cmd) {
	if k, ok := msg.(tea.KeyMsg); ok {
		switch strings.ToLower(k.String()) {
		case "y":
			return nil, c.yes()
		case "n", "esc", "q", "enter":
			m.setStatus("cancelled", false)
			return nil, nil
		}
	}
	return c, nil
}

func (c *confirmModal) view(w, h int) string {
	width := min(max(w-20, 40), 80)
	st := sModal
	if c.danger {
		st = sModalWarn
	}
	body := sModalTitle.Render(c.title) + "\n\n" + lipgloss.NewStyle().Width(width-6).Render(c.body) +
		"\n\n" + sKey.Render("y") + sHint.Render(" yes   ") + sKey.Render("n") + sHint.Render("/esc no   F1 help")
	return st.Width(width).Render(body)
}

// ── scrollable text (help, keys, command output) ──────────────────────────

type textModal struct {
	title string
	md    string
	vp    viewport.Model
	ready bool
	w     int
}

func newTextModal(title, md string) *textModal { return &textModal{title: title, md: md} }

func (t *textModal) helpText() string { return keysHelp }

func (t *textModal) update(m *model, msg tea.Msg) (modal, tea.Cmd) {
	if k, ok := msg.(tea.KeyMsg); ok {
		switch k.String() {
		case "esc", "q", "f1", "?", "enter":
			return nil, nil
		case "j", "down":
			t.vp.ScrollDown(1)
		case "k", "up":
			t.vp.ScrollUp(1)
		case "pgdown", " ", "ctrl+d":
			t.vp.HalfPageDown()
		case "pgup", "ctrl+u":
			t.vp.HalfPageUp()
		case "home", "g":
			t.vp.GotoTop()
		case "end", "G":
			t.vp.GotoBottom()
		}
		return t, nil
	}
	if mm, ok := msg.(tea.MouseMsg); ok {
		var cmd tea.Cmd
		t.vp, cmd = t.vp.Update(mm)
		return t, cmd
	}
	return t, nil
}

func (t *textModal) view(w, h int) string {
	width := min(max(w-8, 40), 110)
	height := max(h-6, 8)
	if !t.ready || t.w != width {
		t.vp = viewport.New(width-4, height-4)
		t.vp.SetContent(renderMarkdown(t.md, width-6))
		t.ready, t.w = true, width
	}
	pct := ""
	if t.vp.TotalLineCount() > t.vp.Height {
		pct = sHint.Render(" " + percent(t.vp.ScrollPercent()))
	}
	head := sModalTitle.Render(t.title) + pct
	foot := sHint.Render("↑↓ scroll · esc close")
	return sModal.Padding(0, 1).Width(width).Render(head + "\n" + t.vp.View() + "\n" + foot)
}

func percent(f float64) string {
	return strings.TrimSpace(lipgloss.NewStyle().Render(itoa(int(f*100)) + "%"))
}

// ── command palette ───────────────────────────────────────────────────────

type paletteCmd struct{ name, desc string }

var paletteCmds = []paletteCmd{
	{"addons", "go to the Addons tab"}, {"aliases", "go to the Aliases tab"}, {"functions", "go to the Functions tab"},
	{"env", "go to the Env tab"}, {"secrets", "go to the Secrets tab"}, {"dirs", "go to the Directories tab"},
	{"snapshots", "go to the Snapshots tab"},
	{"add", "add a new item here"}, {"edit", "edit the selection"}, {"delete", "delete the selection"},
	{"toggle", "switch the selection on/off"}, {"filter", "filter <text>"}, {"clear", "clear the filter"},
	{"all", "show/hide addon aliases & functions"}, {"reveal", "reveal/hide all secrets"},
	{"snapshot", "create a snapshot: snapshot [label]"}, {"edit-config", "open user/msh.conf in $EDITOR"},
	{"edit-local", "open user/local.zsh in $EDITOR"}, {"reload", "re-read everything from disk"},
	{"help", "help for the current tab"}, {"keys", "key bindings"}, {"quit", "leave msh"},
}

type paletteModal struct {
	in  textinput.Model
	sel int
}

func newPalette() *paletteModal {
	ti := textinput.New()
	ti.Prompt = ": "
	ti.PromptStyle = sKey
	ti.Placeholder = "command (tab completes)"
	ti.Focus()
	return &paletteModal{in: ti}
}

func (p *paletteModal) helpText() string { return paletteHelp }

func (p *paletteModal) matches() []paletteCmd {
	word, _, _ := strings.Cut(strings.TrimSpace(p.in.Value()), " ")
	var out []paletteCmd
	for _, c := range paletteCmds {
		if strings.HasPrefix(c.name, word) {
			out = append(out, c)
		}
	}
	return out
}

func (p *paletteModal) update(m *model, msg tea.Msg) (modal, tea.Cmd) {
	if k, ok := msg.(tea.KeyMsg); ok {
		ms := p.matches()
		switch k.String() {
		case "esc":
			return nil, nil
		case "up":
			p.sel = max(p.sel-1, 0)
			return p, nil
		case "down":
			p.sel = min(p.sel+1, max(len(ms)-1, 0))
			return p, nil
		case "tab":
			if len(ms) > 0 {
				p.in.SetValue(ms[min(p.sel, len(ms)-1)].name + " ")
				p.in.CursorEnd()
			}
			return p, nil
		case "enter":
			line := strings.TrimSpace(p.in.Value())
			word, arg, _ := strings.Cut(line, " ")
			if len(ms) > 0 && !isPaletteCmd(word) {
				word = ms[min(p.sel, len(ms)-1)].name
			}
			return nil, m.runPalette(word, strings.TrimSpace(arg))
		}
	}
	var cmd tea.Cmd
	p.in, cmd = p.in.Update(msg)
	p.sel = 0
	return p, cmd
}

func isPaletteCmd(s string) bool {
	for _, c := range paletteCmds {
		if c.name == s {
			return true
		}
	}
	return false
}

func (p *paletteModal) view(w, h int) string {
	width := min(max(w-20, 40), 70)
	var b strings.Builder
	b.WriteString(p.in.View() + "\n\n")
	for i, c := range p.matches() {
		if i >= 10 {
			break
		}
		line := sKey.Render(pad(c.name, 12)) + " " + sRowDesc.Render(c.desc)
		if i == p.sel {
			line = sRowSel.Render("▌" + pad(c.name, 12) + " " + c.desc)
		} else {
			line = " " + line
		}
		b.WriteString(line + "\n")
	}
	b.WriteString(sHint.Render("\nenter run · tab complete · esc close · F1 help"))
	return sModal.Padding(0, 1).Width(width).Render(b.String())
}
