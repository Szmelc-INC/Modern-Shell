package store

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
)

// Kind is the type of a manageable shell item.
type Kind string

const (
	KindAddon    Kind = "addon"
	KindAlias    Kind = "alias"
	KindFunction Kind = "function"
	KindEnv      Kind = "env"
	KindSecret   Kind = "secret"
	KindDir      Kind = "dir"
	KindSnapshot Kind = "snapshot"
)

const offMarker = "#off# "

// Item is one alias / env var / secret in a managed file.
type Item struct {
	Name    string `json:"name"`
	Value   string `json:"value"`
	Desc    string `json:"description,omitempty"`
	Enabled bool   `json:"enabled"`
}

// entry is either a raw line (comments, blank lines, hand-written code) or an item.
type entry struct {
	raw  string
	item *Item
}

// ManagedFile is user/aliases.zsh, user/env.zsh or user/secrets.zsh.
type ManagedFile struct {
	Path    string
	Kind    Kind // KindAlias, KindEnv or KindSecret
	Mode    os.FileMode
	entries []entry
}

func (k Kind) keyword() string {
	if k == KindAlias {
		return "alias"
	}
	return "export"
}

// LoadManaged parses a managed file; a missing file is an empty one.
func LoadManaged(path string, kind Kind) (*ManagedFile, error) {
	mode := os.FileMode(0o644)
	if kind == KindSecret {
		mode = 0o600
	}
	mf := &ManagedFile{Path: path, Kind: kind, Mode: mode}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return mf, nil
	}
	if err != nil {
		return nil, err
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	kw := kind.keyword() + " "
	pendingDesc := ""
	hasDesc := false
	for _, ln := range lines {
		body, enabled := ln, true
		if strings.HasPrefix(ln, offMarker) {
			body, enabled = strings.TrimPrefix(ln, offMarker), false
		}
		if strings.HasPrefix(body, kw) {
			if name, raw, ok := splitAssign(strings.TrimSpace(strings.TrimPrefix(body, kw))); ok {
				it := &Item{Name: name, Value: Unquote(cutTrailingComment(raw)), Enabled: enabled}
				if hasDesc {
					it.Desc = pendingDesc
					mf.entries = mf.entries[:len(mf.entries)-1] // the ## line belongs to the item
				}
				mf.entries = append(mf.entries, entry{item: it})
				hasDesc = false
				continue
			}
		}
		if strings.HasPrefix(ln, "## ") {
			pendingDesc, hasDesc = strings.TrimPrefix(ln, "## "), true
		} else {
			hasDesc = false
		}
		mf.entries = append(mf.entries, entry{raw: ln})
	}
	return mf, nil
}

// Items returns the items in file order.
func (m *ManagedFile) Items() []Item {
	var out []Item
	for _, e := range m.entries {
		if e.item != nil {
			out = append(out, *e.item)
		}
	}
	return out
}

// Get returns the item with the given name.
func (m *ManagedFile) Get(name string) (Item, bool) {
	for _, e := range m.entries {
		if e.item != nil && e.item.Name == name {
			return *e.item, true
		}
	}
	return Item{}, false
}

// Set adds or replaces an item (renaming when oldName differs from it.Name).
func (m *ManagedFile) Set(oldName string, it Item) error {
	if !ValidName(m.Kind, it.Name) {
		return fmt.Errorf("invalid %s name %q", m.Kind, it.Name)
	}
	if strings.ContainsAny(it.Desc, "\n") {
		it.Desc = strings.ReplaceAll(it.Desc, "\n", " ")
	}
	if oldName == "" {
		oldName = it.Name
	}
	if oldName != it.Name {
		if _, exists := m.Get(it.Name); exists {
			return fmt.Errorf("%s %q already exists", m.Kind, it.Name)
		}
	}
	for i, e := range m.entries {
		if e.item != nil && e.item.Name == oldName {
			cp := it
			m.entries[i].item = &cp
			return nil
		}
	}
	cp := it
	m.entries = append(m.entries, entry{item: &cp})
	return nil
}

// Toggle flips (or sets) an item's enabled state.
func (m *ManagedFile) Toggle(name string, on *bool) (bool, error) {
	for _, e := range m.entries {
		if e.item != nil && e.item.Name == name {
			if on != nil {
				e.item.Enabled = *on
			} else {
				e.item.Enabled = !e.item.Enabled
			}
			return e.item.Enabled, nil
		}
	}
	return false, fmt.Errorf("%s %q not found", m.Kind, name)
}

// Delete removes an item.
func (m *ManagedFile) Delete(name string) error {
	for i, e := range m.entries {
		if e.item != nil && e.item.Name == name {
			m.entries = append(m.entries[:i], m.entries[i+1:]...)
			return nil
		}
	}
	return fmt.Errorf("%s %q not found", m.Kind, name)
}

// Save writes the file back (atomically, keeping permissions; secrets stay 600).
func (m *ManagedFile) Save() error {
	var b strings.Builder
	kw := m.Kind.keyword()
	for _, e := range m.entries {
		if e.item == nil {
			b.WriteString(e.raw + "\n")
			continue
		}
		if e.item.Desc != "" {
			b.WriteString("## " + e.item.Desc + "\n")
		}
		if !e.item.Enabled {
			b.WriteString(offMarker)
		}
		fmt.Fprintf(&b, "%s %s=%s\n", kw, e.item.Name, Quote(e.item.Value))
	}
	mode := m.Mode
	if m.Kind == KindSecret {
		mode = 0o600
	}
	if err := writeFileAtomic(m.Path, []byte(b.String()), mode); err != nil {
		return err
	}
	if m.Kind == KindSecret {
		return os.Chmod(m.Path, 0o600)
	}
	return nil
}

// SortedNames is a helper for completions.
func (m *ManagedFile) SortedNames() []string {
	var out []string
	for _, it := range m.Items() {
		out = append(out, it.Name)
	}
	sort.Strings(out)
	return out
}

// Mask hides a secret value, keeping a hint of its length.
func Mask(v string) string {
	switch n := len([]rune(v)); {
	case n == 0:
		return "(empty)"
	default:
		return strings.Repeat("•", min(n, 12)) + fmt.Sprintf(" (%d chars)", n)
	}
}
