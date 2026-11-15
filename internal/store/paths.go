// Package store reads and writes everything msh manages: addons, user
// aliases/env/secrets/functions, zoxide directories and snapshots. The file
// formats are specified in docs/ADDON-SPEC.md and shared with the zsh runtime.
package store

import (
	"os"
	"path/filepath"
	"strings"
)

// Paths holds every location msh works with.
type Paths struct {
	Home    string // $MSH_HOME — framework (refreshed on install)
	User    string // $MSH_USER — the user's layer (never overwritten)
	Cache   string
	Backup  string // snapshot storage
	Source  string // repo/install source recorded by install.sh (may be empty)
	HomeDir string
}

// DefaultPaths resolves paths from the environment exactly like rc.d/00-init.zsh.
func DefaultPaths() Paths {
	home, _ := os.UserHomeDir()
	env := func(k, def string) string {
		if v := os.Getenv(k); v != "" {
			return v
		}
		return def
	}
	cfg := env("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	cache := env("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	p := Paths{HomeDir: home}
	p.Home = env("MSH_HOME", filepath.Join(cfg, "msh"))
	p.User = env("MSH_USER", filepath.Join(p.Home, "user"))
	p.Cache = env("MSH_CACHE", filepath.Join(cache, "msh"))
	p.Backup = env("MSH_BACKUP", filepath.Join(home, ".BACKUP", "msh"))
	if b, err := os.ReadFile(filepath.Join(p.Home, ".source")); err == nil {
		p.Source = strings.TrimSpace(string(b))
	}
	return p
}

func (p Paths) AddonsDir() string      { return filepath.Join(p.Home, "addons") }
func (p Paths) UserAddonsDir() string  { return filepath.Join(p.User, "addons") }
func (p Paths) AddonState() string     { return filepath.Join(p.User, "addons.state") }
func (p Paths) AliasesFile() string    { return filepath.Join(p.User, "aliases.zsh") }
func (p Paths) EnvFile() string        { return filepath.Join(p.User, "env.zsh") }
func (p Paths) SecretsFile() string    { return filepath.Join(p.User, "secrets.zsh") }
func (p Paths) FunctionsDir() string   { return filepath.Join(p.User, "functions") }
func (p Paths) ConfFile() string       { return filepath.Join(p.User, "msh.conf") }
func (p Paths) LocalFile() string      { return filepath.Join(p.User, "local.zsh") }
func (p Paths) SnapshotScript() string { return filepath.Join(p.Home, "addons", "snapshot.zsh") }
func (p Paths) SessionScript() string  { return filepath.Join(p.Home, "bin", "msh-session") }
func (p Paths) Version() string {
	b, err := os.ReadFile(filepath.Join(p.Home, "VERSION"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// Tilde shortens an absolute path under $HOME to ~/… for display.
func (p Paths) Tilde(path string) string {
	if p.HomeDir != "" && strings.HasPrefix(path, p.HomeDir+"/") {
		return "~" + path[len(p.HomeDir):]
	}
	return path
}

// writeFileAtomic writes data to path via a temp file + rename, keeping mode.
func writeFileAtomic(path string, data []byte, mode os.FileMode) error {
	if fi, err := os.Stat(path); err == nil {
		mode = fi.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".msh-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
