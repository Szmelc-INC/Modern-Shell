package store

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// ── zoxide ────────────────────────────────────────────────────────────────

// Dir is one zoxide database entry.
type Dir struct {
	Path   string  `json:"path"`
	Score  float64 `json:"score"`
	Exists bool    `json:"exists"`
}

// ZoxideAvailable reports whether zoxide is on PATH.
func ZoxideAvailable() bool {
	_, err := exec.LookPath("zoxide")
	return err == nil
}

// ListDirs returns zoxide entries, highest score first.
func ListDirs() ([]Dir, error) {
	if !ZoxideAvailable() {
		return nil, fmt.Errorf("zoxide is not installed")
	}
	out, err := exec.Command("zoxide", "query", "--list", "--score").Output()
	if err != nil {
		// An empty database exits non-zero on some versions.
		return nil, nil
	}
	var dirs []Dir
	sc := bufio.NewScanner(bytes.NewReader(out))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) < 2 {
			continue
		}
		score, _ := strconv.ParseFloat(f[0], 64)
		path := strings.TrimSpace(strings.TrimPrefix(sc.Text(), f[0]))
		_, statErr := os.Stat(path)
		dirs = append(dirs, Dir{Path: path, Score: score, Exists: statErr == nil})
	}
	return dirs, nil
}

// AddDir adds (or bumps) a directory in zoxide.
func AddDir(path string) error {
	if fi, err := os.Stat(path); err != nil || !fi.IsDir() {
		return fmt.Errorf("not a directory: %s", path)
	}
	return runQuiet("zoxide", "add", path)
}

// RemoveDir removes a directory from zoxide.
func RemoveDir(path string) error { return runQuiet("zoxide", "remove", path) }

// ExcludeDir adds path to _ZO_EXCLUDE_DIRS in user/env.zsh (applies to new shells).
func ExcludeDir(p Paths, path string) error {
	env, err := LoadManaged(p.EnvFile(), KindEnv)
	if err != nil {
		return err
	}
	it, ok := env.Get("_ZO_EXCLUDE_DIRS")
	if !ok {
		it = Item{Name: "_ZO_EXCLUDE_DIRS", Value: p.HomeDir, Desc: "zoxide never records these directories (colon-separated globs)", Enabled: true}
	}
	for _, part := range strings.Split(it.Value, ":") {
		if part == path {
			return nil
		}
	}
	it.Value += ":" + path
	if err := env.Set("", it); err != nil {
		return err
	}
	if err := env.Save(); err != nil {
		return err
	}
	_ = RemoveDir(path)
	return nil
}

func runQuiet(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("%s %s: %s", name, args[0], msg)
	}
	return nil
}

// ── snapshots (delegated to the snapshot addon — one implementation) ─────

// Snapshot is one entry of `snapshot list --porcelain`.
type Snapshot struct {
	ID      string `json:"id"`
	Created string `json:"created"`
	Label   string `json:"label,omitempty"`
	Reason  string `json:"reason,omitempty"`
	Items   int    `json:"items"`
	Size    string `json:"size"`
}

// SnapshotCmd runs the snapshot addon non-interactively (confirmations pre-approved).
func SnapshotCmd(p Paths, args ...string) (string, error) {
	if _, err := os.Stat(p.SnapshotScript()); err != nil {
		return "", fmt.Errorf("snapshot addon not found at %s — is Modern Shell installed?", p.Tilde(p.SnapshotScript()))
	}
	cmd := exec.Command("zsh", append([]string{p.SnapshotScript()}, args...)...)
	cmd.Env = append(os.Environ(), "MSH_YES=1", "NO_COLOR=1", "MSH_HOME="+p.Home, "MSH_BACKUP="+p.Backup)
	cmd.Stdin = nil
	out, err := cmd.CombinedOutput()
	s := strings.TrimRight(string(out), "\n")
	if err != nil {
		if s == "" {
			s = err.Error()
		}
		return s, fmt.Errorf("%s", s)
	}
	return s, nil
}

// ListSnapshots returns snapshots, newest first.
func ListSnapshots(p Paths) ([]Snapshot, error) {
	out, err := SnapshotCmd(p, "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	var snaps []Snapshot
	for _, ln := range strings.Split(out, "\n") {
		f := strings.Split(ln, "\t")
		if len(f) < 6 {
			continue
		}
		n, _ := strconv.Atoi(f[4])
		snaps = append(snaps, Snapshot{ID: f[0], Created: f[1], Label: f[2], Reason: f[3], Items: n, Size: f[5]})
	}
	return snaps, nil
}

// ── settings (user/msh.conf, simple KEY=value lines) ─────────────────────

// Conf reads KEY=value pairs from user/msh.conf (comments and arrays ignored).
func Conf(p Paths) map[string]string {
	m := map[string]string{}
	data, err := os.ReadFile(p.ConfFile())
	if err != nil {
		return m
	}
	for _, ln := range strings.Split(string(data), "\n") {
		ln = strings.TrimSpace(ln)
		if ln == "" || strings.HasPrefix(ln, "#") {
			continue
		}
		k, v, ok := strings.Cut(ln, "=")
		if !ok || strings.HasPrefix(v, "(") {
			continue
		}
		m[strings.TrimSpace(k)] = Unquote(cutTrailingComment(strings.TrimSpace(v)))
	}
	return m
}
