package store

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Def is an alias or function defined inside an addon (parsed, read-only).
type Def struct {
	Kind  Kind   `json:"kind"`
	Name  string `json:"name"`
	Value string `json:"value,omitempty"` // alias expansion or function body
	Doc   string `json:"doc,omitempty"`   // comment block directly above
	Line  int    `json:"line"`
	Addon string `json:"addon"`
}

// Summary is the first line of the doc comment.
func (d Def) Summary() string {
	s, _, _ := strings.Cut(d.Doc, "\n")
	return s
}

// Addon is one addon file plus its parsed header and definitions.
type Addon struct {
	Name      string   `json:"name"`
	File      string   `json:"file"`
	User      bool     `json:"user"`      // lives in user/addons
	Overrides bool     `json:"overrides"` // user addon shadowing a shipped one
	Desc      string   `json:"description"`
	Tags      []string `json:"tags"`
	Deps      []string `json:"deps,omitempty"`
	Default   bool     `json:"default"`
	Enabled   bool     `json:"enabled"`
	Version   string   `json:"version,omitempty"`
	Dev       string   `json:"dev,omitempty"`
	Examples  []string `json:"examples,omitempty"`
	Help      string   `json:"help,omitempty"`
	Defs      []Def    `json:"defs,omitempty"`
}

// Aliases / Functions filter the addon's definitions by kind.
func (a Addon) Aliases() []Def   { return a.defs(KindAlias) }
func (a Addon) Functions() []Def { return a.defs(KindFunction) }
func (a Addon) defs(k Kind) []Def {
	var out []Def
	for _, d := range a.Defs {
		if d.Kind == k {
			out = append(out, d)
		}
	}
	return out
}

// Dep is a dependency with its install status.
type Dep struct {
	Name      string
	Optional  bool
	Installed bool
}

// DepStatus resolves every DEP entry against $PATH. An entry is `cmd`,
// `cmd (optional)` or `package (cmd1, cmd2[, optional])` — then the listed
// commands are what gets checked.
func (a Addon) DepStatus() []Dep {
	var out []Dep
	for _, d := range a.Deps {
		name, inner, _ := strings.Cut(d, "(")
		name = strings.TrimSpace(name)
		inner = strings.TrimSuffix(strings.TrimSpace(inner), ")")
		opt := false
		var cmds []string
		for _, c := range strings.Split(inner, ",") {
			switch c = strings.TrimSpace(c); {
			case c == "optional":
				opt = true
			case c != "" && !strings.Contains(c, " "):
				cmds = append(cmds, c)
			}
		}
		if len(cmds) == 0 && name != "" {
			cmds = []string{strings.Fields(name)[0]}
		}
		if name == "" || len(cmds) == 0 {
			continue
		}
		installed := true
		for _, c := range cmds {
			if _, err := exec.LookPath(c); err != nil {
				installed = false
			}
		}
		out = append(out, Dep{Name: name, Optional: opt, Installed: installed})
	}
	return out
}

var (
	aliasLineRe = regexp.MustCompile(`^\s*(?:\(\(.*\)\)\s*&&\s*|if .*then\s+)?alias\s+(?:-[gs]\s+)?(.+)$`)
	funcLineRe  = regexp.MustCompile(`^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_.:-]*)\s*\(\)\s*(?:\{|\($|$)`)
	funcKwRe    = regexp.MustCompile(`^\s*function\s+([A-Za-z_][A-Za-z0-9_.:-]*)\s*(?:\(\))?\s*\{`)
)

// ParseAddon reads one addon file.
func ParseAddon(file string) (Addon, error) {
	f, err := os.Open(file)
	if err != nil {
		return Addon{}, err
	}
	defer f.Close()
	a := Addon{Name: strings.TrimSuffix(filepath.Base(file), ".zsh"), File: file, Default: true}
	var lines []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	for sc.Scan() {
		lines = append(lines, sc.Text())
	}

	// Header: first contiguous comment block (after the shebang).
	i := 0
	if len(lines) > 0 && strings.HasPrefix(lines[0], "#!") {
		i = 1
	}
	var help []string
	for ; i < len(lines) && strings.HasPrefix(lines[i], "#"); i++ {
		ln := lines[i]
		if strings.HasPrefix(ln, "# |") {
			help = append(help, strings.TrimPrefix(strings.TrimPrefix(ln, "# |"), " "))
			continue
		}
		key, val, ok := strings.Cut(strings.TrimPrefix(ln, "# "), ":")
		if !ok {
			continue
		}
		val = strings.TrimSpace(val)
		switch strings.TrimSpace(key) {
		case "NAME":
			if val != "" {
				a.Name = val
			}
		case "DESC":
			a.Desc = val
		case "TAGS":
			a.Tags = splitList(val)
		case "DEP", "DEPS":
			a.Deps = splitList(val)
		case "DEFAULT":
			a.Default = !strings.EqualFold(val, "off")
		case "VER":
			a.Version = val
		case "DEV":
			a.Dev = val
		case "EXAMPLE":
			a.Examples = append(a.Examples, val)
		}
	}
	a.Help = strings.Join(help, "\n")
	a.Defs = parseDefs(lines, i, a.Name)
	return a, nil
}

// splitList splits a comma list, keeping commas inside parentheses.
func splitList(s string) []string {
	var out []string
	depth, start := 0, 0
	flush := func(end int) {
		if p := strings.TrimSpace(s[start:end]); p != "" {
			out = append(out, p)
		}
	}
	for i, c := range s {
		switch c {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth <= 0 {
				flush(i)
				start = i + 1
			}
		}
	}
	flush(len(s))
	return out
}

// parseDefs finds documented aliases and functions after the header.
func parseDefs(lines []string, start int, addon string) []Def {
	var defs []Def
	var doc []string
	for i := start; i < len(lines); i++ {
		ln := lines[i]
		trim := strings.TrimSpace(ln)
		if strings.HasPrefix(trim, "#") && !strings.HasPrefix(trim, "#!") {
			doc = append(doc, strings.TrimSpace(strings.TrimLeft(trim, "#")))
			continue
		}
		if m := aliasLineRe.FindStringSubmatch(ln); m != nil {
			for _, w := range splitWords(cutTrailingComment(m[1])) {
				if name, raw, ok := splitAssign(w); ok && !strings.HasPrefix(name, "-") {
					defs = append(defs, Def{Kind: KindAlias, Name: name, Value: Unquote(raw), Doc: strings.Join(doc, "\n"), Line: i + 1, Addon: addon})
				}
			}
		} else if name := funcName(ln); name != "" && !strings.HasPrefix(name, "_") && !strings.Contains(name, "::") {
			body, end := funcBody(lines, i)
			defs = append(defs, Def{Kind: KindFunction, Name: name, Value: body, Doc: strings.Join(doc, "\n"), Line: i + 1, Addon: addon})
			i = end
		}
		doc = nil
	}
	return defs
}

func funcName(ln string) string {
	if m := funcKwRe.FindStringSubmatch(ln); m != nil {
		return m[1]
	}
	if m := funcLineRe.FindStringSubmatch(ln); m != nil {
		return m[1]
	}
	return ""
}

// funcBody returns the full definition text starting at line i (naive brace matching).
func funcBody(lines []string, i int) (string, int) {
	depth, seen := 0, false
	for j := i; j < len(lines) && j < i+400; j++ {
		for _, c := range stripStrings(lines[j]) {
			switch c {
			case '{', '(':
				if c == '{' {
					seen = true
				}
				depth++
			case '}', ')':
				depth--
			}
		}
		if seen && depth <= 0 {
			return strings.Join(lines[i:j+1], "\n"), j
		}
	}
	return lines[i], i
}

// stripStrings blanks quoted text and comments so brace counting ignores them.
func stripStrings(s string) string {
	var b strings.Builder
	inS, inD := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\' && !inS:
			i++
		case c == '\'' && !inD:
			inS = !inS
		case c == '"' && !inS:
			inD = !inD
		case c == '#' && !inS && !inD && (i == 0 || s[i-1] == ' ' || s[i-1] == '\t'):
			return b.String()
		case !inS && !inD:
			b.WriteByte(c)
		}
	}
	return b.String()
}

// splitWords splits a zsh word list on unquoted whitespace.
func splitWords(s string) []string {
	var out []string
	var cur strings.Builder
	inS, inD := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\' && !inS && i+1 < len(s):
			cur.WriteByte(c)
			i++
			cur.WriteByte(s[i])
			continue
		case c == '\'' && !inD:
			inS = !inS
		case c == '"' && !inS:
			inD = !inD
		case (c == ' ' || c == '\t') && !inS && !inD:
			if cur.Len() > 0 {
				out = append(out, cur.String())
				cur.Reset()
			}
			continue
		}
		cur.WriteByte(c)
	}
	if cur.Len() > 0 {
		out = append(out, cur.String())
	}
	return out
}

// LoadAddonState reads user/addons.state (name=on|off).
func LoadAddonState(p Paths) map[string]bool {
	st := map[string]bool{}
	data, err := os.ReadFile(p.AddonState())
	if err != nil {
		return st
	}
	for _, ln := range strings.Split(string(data), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(ln), "=")
		if !ok || strings.HasPrefix(k, "#") || k == "" {
			continue
		}
		st[k] = strings.TrimSpace(v) == "on"
	}
	return st
}

// LoadAddons returns all addons (shipped + user, user overriding by name), sorted.
func LoadAddons(p Paths) ([]Addon, error) {
	byName := map[string]Addon{}
	shipped := map[string]bool{}
	for _, dir := range []string{p.AddonsDir(), p.UserAddonsDir()} {
		files, _ := filepath.Glob(filepath.Join(dir, "*.zsh"))
		for _, f := range files {
			a, err := ParseAddon(f)
			if err != nil {
				return nil, err
			}
			a.Name = strings.TrimSuffix(filepath.Base(f), ".zsh") // the loader keys by file name
			if dir == p.UserAddonsDir() {
				a.User = true
				a.Overrides = shipped[a.Name]
			} else {
				shipped[a.Name] = true
			}
			byName[a.Name] = a
		}
	}
	state := LoadAddonState(p)
	out := make([]Addon, 0, len(byName))
	for name, a := range byName {
		if v, ok := state[name]; ok {
			a.Enabled = v
		} else {
			a.Enabled = a.Default
		}
		for i := range a.Defs {
			a.Defs[i].Addon = name
		}
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// FindAddon returns one addon by name.
func FindAddon(p Paths, name string) (Addon, error) {
	all, err := LoadAddons(p)
	if err != nil {
		return Addon{}, err
	}
	for _, a := range all {
		if a.Name == name {
			return a, nil
		}
	}
	return Addon{}, fmt.Errorf("addon %q not found", name)
}

// SetAddonState writes name=on|off to user/addons.state, keeping other lines.
func SetAddonState(p Paths, name string, on bool) error {
	data, err := os.ReadFile(p.AddonState())
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	val := "off"
	if on {
		val = "on"
	}
	var out []string
	found := false
	for _, ln := range strings.Split(strings.TrimRight(string(data), "\n"), "\n") {
		if k, _, ok := strings.Cut(strings.TrimSpace(ln), "="); ok && k == name {
			ln, found = name+"="+val, true
		}
		if ln != "" || len(out) > 0 {
			out = append(out, ln)
		}
	}
	if !found {
		out = append(out, name+"="+val)
	}
	return writeFileAtomic(p.AddonState(), []byte(strings.Join(out, "\n")+"\n"), 0o644)
}

// NewUserAddon creates user/addons/<name>.zsh from a template.
func NewUserAddon(p Paths, name, desc, tags string) (string, error) {
	if !ValidName(KindAddon, name) {
		return "", fmt.Errorf("invalid addon name %q (lowercase letters, digits, dashes)", name)
	}
	path := filepath.Join(p.UserAddonsDir(), name+".zsh")
	if _, err := os.Stat(path); err == nil {
		return "", fmt.Errorf("user addon %q already exists", name)
	}
	if desc == "" {
		desc = "My addon"
	}
	if tags == "" {
		tags = "DEV"
	}
	tpl := fmt.Sprintf(`#!/usr/bin/env zsh
# NAME: %[1]s
# DESC: %[2]s
# TAGS: %[3]s
# DEFAULT: on
# VER: 0.1
# | Long help for **%[1]s** — markdown, shown in the msh TUI on F1.

# %[1]s-hello — example function, replace me
%[1]s-hello() {
  msh::ok "hello from %[1]s"
}
`, name, desc, strings.ToUpper(tags))
	if err := writeFileAtomic(path, []byte(tpl), 0o644); err != nil {
		return "", err
	}
	return path, nil
}

// OverrideAddon copies a shipped addon into user/addons so it can be edited.
func OverrideAddon(p Paths, a Addon) (string, error) {
	if a.User {
		return a.File, nil
	}
	data, err := os.ReadFile(a.File)
	if err != nil {
		return "", err
	}
	dst := filepath.Join(p.UserAddonsDir(), a.Name+".zsh")
	return dst, writeFileAtomic(dst, data, 0o644)
}

// DeleteUserAddon removes a user addon (shipped addons can only be disabled).
func DeleteUserAddon(p Paths, a Addon) error {
	if !a.User {
		return fmt.Errorf("%q is a shipped addon — disable it instead (it comes back on upgrade)", a.Name)
	}
	return os.Remove(a.File)
}

// AllDefs returns every alias/function from every addon, flagging the addon state.
func AllDefs(addons []Addon, kind Kind) []Def {
	var out []Def
	for _, a := range addons {
		out = append(out, a.defs(kind)...)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}
