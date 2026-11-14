package store

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestQuoteRoundTrip(t *testing.T) {
	for _, s := range []string{"", "plain", "it's", `a "b" $c`, "x'y'z", `back\slash`} {
		if got := Unquote(Quote(s)); got != s {
			t.Errorf("Unquote(Quote(%q)) = %q", s, got)
		}
	}
	if got := Unquote(`"a\"b"c'd'`); got != `a"bcd` {
		t.Errorf("mixed quoting: %q", got)
	}
}

func TestManagedFileRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "aliases.zsh")
	orig := "# header comment\n## git status\nalias gs='git status -sb'\n#off# alias gl='git log'\n\nprint hand-written\n"
	os.WriteFile(path, []byte(orig), 0o644)

	mf, err := LoadManaged(path, KindAlias)
	if err != nil {
		t.Fatal(err)
	}
	items := mf.Items()
	if len(items) != 2 || items[0].Desc != "git status" || items[0].Value != "git status -sb" || items[1].Enabled {
		t.Fatalf("parsed items wrong: %+v", items)
	}
	if err := mf.Save(); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(path); string(b) != orig {
		t.Fatalf("round trip changed file:\n%s", b)
	}

	mf.Set("", Item{Name: "it", Value: "echo it's", Desc: "quote test", Enabled: true})
	mf.Toggle("gl", nil)
	mf.Set("gs", Item{Name: "gst", Value: "git status", Enabled: true})
	mf.Delete("it")
	mf.Set("", Item{Name: "q2", Value: "echo it's", Enabled: true})
	if err := mf.Save(); err != nil {
		t.Fatal(err)
	}
	mf2, _ := LoadManaged(path, KindAlias)
	got := map[string]Item{}
	for _, it := range mf2.Items() {
		got[it.Name] = it
	}
	if !got["gl"].Enabled || got["gst"].Value != "git status" || got["q2"].Value != "echo it's" || len(got) != 3 {
		t.Fatalf("after edits: %+v", got)
	}
	if err := mf2.Set("", Item{Name: "bad name", Value: "x"}); err == nil {
		t.Error("invalid alias name accepted")
	}

	// The file must stay valid zsh and define what we expect.
	if zsh, err := exec.LookPath("zsh"); err == nil {
		out, err := exec.Command(zsh, "-f", "-c", "source "+path+" >/dev/null; alias q2; alias gl").CombinedOutput()
		if err != nil || !strings.Contains(string(out), "q2=") {
			t.Fatalf("zsh could not source the file: %v\n%s", err, out)
		}
	}
}

func TestSecretsStay600(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets.zsh")
	mf, _ := LoadManaged(path, KindSecret)
	mf.Set("", Item{Name: "API_TOKEN", Value: "s3cr3t", Enabled: true})
	if err := mf.Save(); err != nil {
		t.Fatal(err)
	}
	fi, _ := os.Stat(path)
	if fi.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", fi.Mode().Perm())
	}
	if m := Mask("s3cr3t"); strings.Contains(m, "s3") {
		t.Fatalf("mask leaks: %s", m)
	}
}

func TestParseShippedAddons(t *testing.T) {
	p := Paths{Home: "../../shell", User: t.TempDir()}
	addons, err := LoadAddons(p)
	if err != nil {
		t.Fatal(err)
	}
	var core, snap *Addon
	for i := range addons {
		switch addons[i].Name {
		case "core-aliases":
			core = &addons[i]
		case "snapshot":
			snap = &addons[i]
		}
		if addons[i].Desc == "" {
			t.Errorf("%s: empty DESC", addons[i].Name)
		}
	}
	if core == nil || snap == nil {
		t.Fatal("core-aliases or snapshot addon missing")
	}
	if !core.Enabled || len(core.Aliases()) < 10 {
		t.Errorf("core-aliases: enabled=%v aliases=%d", core.Enabled, len(core.Aliases()))
	}
	var ll, cat bool
	for _, d := range core.Defs {
		ll = ll || (d.Name == "ll" && d.Summary() != "")
		cat = cat || (d.Name == "cat" && d.Kind == KindFunction)
	}
	if !ll || !cat {
		t.Errorf("expected documented ll alias and cat function")
	}
	if !strings.Contains(snap.Help, "pre-install") {
		t.Errorf("snapshot long help not parsed")
	}
	var fn bool
	for _, d := range snap.Functions() {
		fn = fn || d.Name == "snapshot"
		if strings.Contains(d.Name, "::") {
			t.Errorf("internal helper %s exposed", d.Name)
		}
	}
	if !fn {
		t.Error("snapshot function not found")
	}
}

func TestAddonStateAndUserAddons(t *testing.T) {
	p := Paths{Home: t.TempDir(), User: t.TempDir()}
	path, err := NewUserAddon(p, "my-tools", "Things", "dev")
	if err != nil {
		t.Fatal(err)
	}
	a, err := FindAddon(p, "my-tools")
	if err != nil || !a.User || !a.Enabled || len(a.Functions()) != 1 {
		t.Fatalf("new addon: %+v %v", a, err)
	}
	SetAddonState(p, "my-tools", false)
	SetAddonState(p, "other", true)
	SetAddonState(p, "my-tools", false)
	if a, _ = FindAddon(p, "my-tools"); a.Enabled {
		t.Fatal("still enabled")
	}
	b, _ := os.ReadFile(p.AddonState())
	if strings.Count(string(b), "my-tools=") != 1 {
		t.Fatalf("duplicate state lines:\n%s", b)
	}
	if err := DeleteUserAddon(p, a); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("not deleted")
	}
}

func TestUserFuncs(t *testing.T) {
	p := Paths{Home: t.TempDir(), User: t.TempDir()}
	uf := UserFunc{Name: "greet", Desc: "say hi", Body: "local who=${1:-world}\necho \"hi $who\"", Enabled: true}
	if err := SaveUserFunc(p, "", uf); err != nil {
		t.Fatal(err)
	}
	got, err := FindUserFunc(p, "greet")
	if err != nil || got.Desc != "say hi" || got.Body != uf.Body {
		t.Fatalf("got %+v %v", got, err)
	}
	if _, err := ToggleUserFunc(got, nil); err != nil {
		t.Fatal(err)
	}
	got, _ = FindUserFunc(p, "greet")
	if got.Enabled || !strings.HasSuffix(got.File, ".zsh.off") {
		t.Fatalf("toggle: %+v", got)
	}
	got.Name = "hello"
	if err := SaveUserFunc(p, "greet", got); err != nil {
		t.Fatal(err)
	}
	all, _ := LoadUserFuncs(p)
	if len(all) != 1 || all[0].Name != "hello" || all[0].Enabled {
		t.Fatalf("rename: %+v", all)
	}
	if zsh, err := exec.LookPath("zsh"); err == nil {
		out, err := exec.Command(zsh, "-f", "-c", "source "+all[0].File+"; hello there").CombinedOutput()
		if err != nil || strings.TrimSpace(string(out)) != "hi there" {
			t.Fatalf("function file broken: %v %s", err, out)
		}
	}
}
