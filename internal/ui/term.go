// Package ui holds the Midnight palette and terminal output helpers shared by
// the CLI and the TUI.
package ui

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"golang.org/x/term"
)

// Midnight palette (same values the shell exports as MIDNIGHT_*).
const (
	Bg        = "#1e1e2e"
	BgAlt     = "#232339"
	Fg        = "#cdd6f4"
	Accent    = "#7aa2f7"
	AccentAlt = "#b4befe"
	Border    = "#313244"
	Gray      = "#6c7086"
	Alert     = "#f38ba8"
	Success   = "#a6e3a1"
	Warning   = "#f9e2af"
	Cursor    = "#f5e0dc"
)

// Color reports whether CLI output should be colored.
var Color = os.Getenv("NO_COLOR") == "" && term.IsTerminal(int(os.Stdout.Fd()))

// IsTTY reports whether stdin is an interactive terminal.
func IsTTY() bool { return term.IsTerminal(int(os.Stdin.Fd())) }

func paint(code, s string) string {
	if !Color || s == "" {
		return s
	}
	return "\x1b[" + code + "m" + s + "\x1b[0m"
}

func Bold(s string) string    { return paint("1", s) }
func Dim(s string) string     { return paint("2", s) }
func Blue(s string) string    { return paint("1;38;2;122;162;247", s) }
func Lilac(s string) string   { return paint("38;2;180;190;254", s) }
func Green(s string) string   { return paint("38;2;166;227;161", s) }
func Yellow(s string) string  { return paint("38;2;249;226;175", s) }
func Red(s string) string     { return paint("38;2;243;139;168", s) }
func GrayText(s string) string { return paint("38;2;108;112;134", s) }

// Status helpers (stderr for warnings/errors).
func Ok(format string, a ...any)   { fmt.Println(Green("✔") + " " + fmt.Sprintf(format, a...)) }
func Info(format string, a ...any) { fmt.Println(Blue("::") + " " + fmt.Sprintf(format, a...)) }
func Warn(format string, a ...any) {
	fmt.Fprintln(os.Stderr, Yellow("!")+" "+fmt.Sprintf(format, a...))
}
func Err(format string, a ...any) {
	fmt.Fprintln(os.Stderr, Red("✘")+" "+fmt.Sprintf(format, a...))
}

// OnOff renders an enabled flag.
func OnOff(on bool) string {
	if on {
		return Green("● on ")
	}
	return GrayText("○ off")
}

// Table prints aligned columns with a colored header (ANSI-aware widths).
type Table struct {
	Headers []string
	Rows    [][]string
	MaxCol  int // truncate cells wider than this (0 = 60)
}

func (t Table) Render(w io.Writer) {
	maxCol := t.MaxCol
	if maxCol == 0 {
		maxCol = 60
	}
	widths := make([]int, len(t.Headers))
	cell := func(s string) string {
		s = strings.ReplaceAll(s, "\n", " ")
		if lipgloss.Width(s) > maxCol && !strings.Contains(s, "\x1b") {
			r := []rune(s)
			if len(r) > maxCol-1 {
				s = string(r[:maxCol-1]) + "…"
			}
		}
		return s
	}
	for i, h := range t.Headers {
		widths[i] = lipgloss.Width(h)
	}
	for _, r := range t.Rows {
		for i := range r {
			if i < len(widths) {
				r[i] = cell(r[i])
				widths[i] = max(widths[i], lipgloss.Width(r[i]))
			}
		}
	}
	line := func(cols []string, style func(string) string) {
		var b strings.Builder
		for i, c := range cols {
			if i >= len(widths) {
				break
			}
			pad := widths[i] - lipgloss.Width(c)
			if i == len(cols)-1 {
				pad = 0
			}
			b.WriteString(style(c) + strings.Repeat(" ", max(pad, 0)))
			if i < len(cols)-1 {
				b.WriteString("  ")
			}
		}
		fmt.Fprintln(w, strings.TrimRight(b.String(), " "))
	}
	line(t.Headers, func(s string) string { return Bold(Blue(s)) })
	for _, r := range t.Rows {
		line(r, func(s string) string { return s })
	}
}

// Confirm asks a y/N question on the terminal (false when not interactive).
func Confirm(q string) bool {
	if !IsTTY() {
		return false
	}
	fmt.Fprint(os.Stderr, Yellow("?")+" "+q+" [y/N] ")
	var a string
	fmt.Scanln(&a)
	return strings.HasPrefix(strings.ToLower(a), "y")
}

// ReadSecret reads a value without echo (falls back to a plain line from a pipe).
func ReadSecret(prompt string) (string, error) {
	if IsTTY() {
		fmt.Fprint(os.Stderr, Yellow("?")+" "+prompt+": ")
		b, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		return string(b), err
	}
	b, err := io.ReadAll(os.Stdin)
	return strings.TrimRight(string(b), "\r\n"), err
}
