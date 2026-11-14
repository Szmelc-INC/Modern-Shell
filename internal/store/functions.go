package store

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// UserFunc is one file in user/functions (<name>.zsh, disabled: <name>.zsh.off).
type UserFunc struct {
	Name    string `json:"name"`
	File    string `json:"file"`
	Desc    string `json:"description,omitempty"`
	Body    string `json:"body"` // the inside of name() { … }
	Raw     string `json:"-"`    // the whole file
	Enabled bool   `json:"enabled"`
}

// LoadUserFuncs lists user functions.
func LoadUserFuncs(p Paths) ([]UserFunc, error) {
	var out []UserFunc
	entries, err := os.ReadDir(p.FunctionsDir())
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		n := e.Name()
		enabled := strings.HasSuffix(n, ".zsh")
		if !enabled && !strings.HasSuffix(n, ".zsh.off") {
			continue
		}
		f := filepath.Join(p.FunctionsDir(), n)
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		uf := UserFunc{Name: strings.TrimSuffix(strings.TrimSuffix(n, ".off"), ".zsh"), File: f, Raw: string(data), Enabled: enabled}
		uf.Desc, uf.Body = splitFuncFile(uf.Name, string(data))
		out = append(out, uf)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// splitFuncFile extracts `# DESC:` and the body between `name() {` and the last `}`.
func splitFuncFile(name, s string) (desc, body string) {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	start := -1
	for i, ln := range lines {
		if strings.HasPrefix(ln, "# DESC:") {
			desc = strings.TrimSpace(strings.TrimPrefix(ln, "# DESC:"))
		}
		if start < 0 && funcName(ln) == name {
			start = i
		}
	}
	if start >= 0 && len(lines) > start+1 && strings.TrimSpace(lines[len(lines)-1]) == "}" {
		inner := lines[start+1 : len(lines)-1]
		for i, ln := range inner {
			inner[i] = strings.TrimPrefix(ln, "  ")
		}
		return desc, strings.Join(inner, "\n")
	}
	return desc, s
}

// SaveUserFunc writes a function file (renaming when oldName differs).
func SaveUserFunc(p Paths, oldName string, uf UserFunc) error {
	if !ValidName(KindFunction, uf.Name) {
		return fmt.Errorf("invalid function name %q", uf.Name)
	}
	dir := p.FunctionsDir()
	enabledPath := filepath.Join(dir, uf.Name+".zsh")
	path := enabledPath
	if !uf.Enabled {
		path += ".off"
	}
	if oldName != "" && oldName != uf.Name {
		for _, suf := range []string{".zsh", ".zsh.off"} {
			if _, err := os.Stat(filepath.Join(dir, uf.Name+suf)); err == nil {
				return fmt.Errorf("function %q already exists", uf.Name)
			}
		}
	}
	var b strings.Builder
	b.WriteString("# DESC: " + strings.ReplaceAll(uf.Desc, "\n", " ") + "\n")
	b.WriteString(uf.Name + "() {\n")
	for _, ln := range strings.Split(strings.TrimRight(uf.Body, "\n"), "\n") {
		if ln == "" {
			b.WriteString("\n")
		} else {
			b.WriteString("  " + ln + "\n")
		}
	}
	b.WriteString("}\n")
	if err := writeFileAtomic(path, []byte(b.String()), 0o644); err != nil {
		return err
	}
	if oldName != "" && oldName != uf.Name {
		os.Remove(filepath.Join(dir, oldName+".zsh"))
		os.Remove(filepath.Join(dir, oldName+".zsh.off"))
	}
	return nil
}

// ToggleUserFunc renames <name>.zsh ↔ <name>.zsh.off.
func ToggleUserFunc(uf UserFunc, on *bool) (bool, error) {
	want := !uf.Enabled
	if on != nil {
		want = *on
	}
	if want == uf.Enabled {
		return want, nil
	}
	base := strings.TrimSuffix(uf.File, ".off")
	if want {
		return true, os.Rename(uf.File, base)
	}
	return false, os.Rename(uf.File, base+".off")
}

// FuncInner returns the body of a `name() { … }` definition (for overriding addon functions).
func FuncInner(name, src string) string {
	_, body := splitFuncFile(name, src+"\n")
	return body
}

// FindUserFunc looks a user function up by name.
func FindUserFunc(p Paths, name string) (UserFunc, error) {
	all, err := LoadUserFuncs(p)
	if err != nil {
		return UserFunc{}, err
	}
	for _, f := range all {
		if f.Name == name {
			return f, nil
		}
	}
	return UserFunc{}, fmt.Errorf("function %q not found in %s", name, p.Tilde(p.FunctionsDir()))
}
