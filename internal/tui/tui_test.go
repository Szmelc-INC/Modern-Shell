package tui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Szmelc-INC/Modern-Shell/internal/store"
)

func testModel(t *testing.T) *model {
	t.Helper()
	shell, _ := filepath.Abs("../../shell")
	p := store.Paths{Home: shell, User: t.TempDir(), Backup: t.TempDir(), HomeDir: t.TempDir()}
	os.MkdirAll(filepath.Join(p.User, "functions"), 0o755)
	m := newModel(p)
	m.loadTab(tabAddons)
	m.Update(tea.WindowSizeMsg{Width: 120, Height: 36})
	return m
}

func key(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "tab":
		return tea.KeyMsg{Type: tea.KeyTab}
	case "space":
		return tea.KeyMsg{Type: tea.KeySpace, Runes: []rune{' '}}
	case "f1":
		return tea.KeyMsg{Type: tea.KeyF1}
	case "ctrl+s":
		return tea.KeyMsg{Type: tea.KeyCtrlS}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
}

func typeText(m *model, s string) {
	for _, r := range s {
		m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
}

// run executes a command returned by Update and feeds its message back.
func feed(m *model, cmd tea.Cmd) {
	for i := 0; cmd != nil && i < 5; i++ {
		msg := cmd()
		if msg == nil {
			return
		}
		if _, ok := msg.(tea.BatchMsg); ok {
			return
		}
		_, cmd = m.Update(msg)
	}
}

func press(m *model, k string) {
	_, cmd := m.Update(key(k))
	feed(m, cmd)
}

func checkWidth(t *testing.T, view string, w int, ctx string) {
	t.Helper()
	for i, ln := range strings.Split(view, "\n") {
		if lw := lipgloss.Width(ln); lw > w {
			t.Fatalf("%s: line %d is %d wide (> %d): %q", ctx, i, lw, w, ln)
		}
	}
}

func TestRenderEveryTabAndSize(t *testing.T) {
	m := testModel(t)
	for _, size := range [][2]int{{120, 36}, {80, 24}, {200, 50}, {60, 20}} {
		m.Update(tea.WindowSizeMsg{Width: size[0], Height: size[1]})
		for tab := range tabCount {
			m.switchTab(tab)
			v := m.View()
			if v == "" {
				t.Fatalf("empty view tab %d", tab)
			}
			checkWidth(t, v, size[0], tabTitles[tab])
		}
	}
}

func TestAddonsTabShowsShippedAddons(t *testing.T) {
	m := testModel(t)
	v := m.View()
	for _, want := range []string{"core-aliases", "snapshot", "Addons"} {
		if !strings.Contains(v, want) {
			t.Errorf("view lacks %q", want)
		}
	}
}

func TestModalsOpenAndClose(t *testing.T) {
	m := testModel(t)
	for _, k := range []string{"f1", "?", ":"} {
		press(m, k)
		if m.modal == nil {
			t.Fatalf("%s did not open a modal", k)
		}
		checkWidth(t, m.View(), 120, "modal "+k)
		press(m, "esc")
		if m.modal != nil {
			t.Fatalf("esc did not close modal opened by %s", k)
		}
	}
	// F1 inside a form shows the form's help.
	m.switchTab(tabAliases)
	press(m, "a")
	press(m, "f1")
	tm, ok := m.modal.(*textModal)
	if !ok || !strings.Contains(tm.md, "Alias form") {
		t.Fatalf("F1 in alias form should show form help, got %T", m.modal)
	}
}

func TestAliasLifecycleThroughKeys(t *testing.T) {
	m := testModel(t)
	m.switchTab(tabAliases)
	m.showAddonDefs = false
	m.loadTab(tabAliases)

	press(m, "a")
	typeText(m, "gs")
	press(m, "tab")
	typeText(m, "git status -sb")
	press(m, "tab")
	typeText(m, "short status")
	press(m, "enter") // last field → save
	if m.modal != nil {
		t.Fatalf("form still open: %s", m.modal.(*formModal).err)
	}
	mf, _ := store.LoadManaged(m.p.AliasesFile(), store.KindAlias)
	it, ok := mf.Get("gs")
	if !ok || it.Value != "git status -sb" || it.Desc != "short status" || !it.Enabled {
		t.Fatalf("alias not saved: %+v", it)
	}

	press(m, "space")
	mf, _ = store.LoadManaged(m.p.AliasesFile(), store.KindAlias)
	if it, _ := mf.Get("gs"); it.Enabled {
		t.Fatal("toggle did not disable")
	}

	press(m, "d")
	if _, ok := m.modal.(*confirmModal); !ok {
		t.Fatal("delete must ask for confirmation")
	}
	press(m, "y")
	mf, _ = store.LoadManaged(m.p.AliasesFile(), store.KindAlias)
	if _, ok := mf.Get("gs"); ok {
		t.Fatal("alias not deleted")
	}
}

func TestSecretsAreMasked(t *testing.T) {
	m := testModel(t)
	mf, _ := store.LoadManaged(m.p.SecretsFile(), store.KindSecret)
	mf.Set("", store.Item{Name: "TOKEN", Value: "supersecretvalue", Enabled: true})
	mf.Save()
	m.switchTab(tabSecrets)
	if v := m.View(); strings.Contains(v, "supersecretvalue") {
		t.Fatal("secret visible without reveal")
	}
	press(m, "v")
	if v := m.View(); !strings.Contains(v, "supersecretvalue") {
		t.Fatal("v did not reveal")
	}
}

func TestAddonToggleWritesState(t *testing.T) {
	m := testModel(t)
	m.switchTab(tabAddons)
	m.selectKey("addon:core-aliases")
	press(m, "space")
	if st := store.LoadAddonState(m.p); st["core-aliases"] != false || len(st) != 1 {
		t.Fatalf("state: %v", st)
	}
	// Shipped addons cannot be deleted.
	press(m, "d")
	if m.modal != nil || !m.statusErr {
		t.Fatal("deleting a shipped addon must be refused with a message")
	}
}

func TestFunctionFormMultiline(t *testing.T) {
	m := testModel(t)
	m.switchTab(tabFunctions)
	press(m, "a")
	f := m.modal.(*formModal)
	f.fields[0].input.SetValue("greet")
	f.fields[2].area.SetValue("echo one\necho two")
	press(m, "ctrl+s")
	uf, err := store.FindUserFunc(m.p, "greet")
	if err != nil || uf.Body != "echo one\necho two" {
		t.Fatalf("function: %+v %v", uf, err)
	}
}

func TestPaletteSwitchesTab(t *testing.T) {
	m := testModel(t)
	press(m, ":")
	typeText(m, "secr")
	press(m, "enter")
	if m.tab != tabSecrets {
		t.Fatalf("tab = %d", m.tab)
	}
}
