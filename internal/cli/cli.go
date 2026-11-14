// Package cli implements the `msh` command line: a small command tree with
// per-command colored help, global flags (--json, --no-color, --yes) and
// shell completion generated from the same tree.
package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/sernik77/modern-shell/internal/store"
	"github.com/sernik77/modern-shell/internal/ui"
)

// Flag is a command-specific option. Arg != "" means it takes a value.
type Flag struct {
	Long, Short, Arg, Help string
}

// Command is a node in the command tree.
type Command struct {
	Name     string
	Aliases  []string
	Summary  string
	Usage    string // after "msh <path>"
	Long     string
	Flags    []Flag
	Examples []string
	Sub      []*Command
	Hidden   bool
	Complete string // dynamic completion kind for positional args
	Run      func(c *Ctx, args []string) error

	parent *Command
}

// Ctx carries parsed global state into a command.
type Ctx struct {
	P     store.Paths
	JSON  bool
	Yes   bool
	Out   io.Writer
	vals  map[string]string
	bools map[string]bool
	cmd   *Command
}

// Str / Bool read command flags by long name.
func (c *Ctx) Str(name string) string { return c.vals[name] }
func (c *Ctx) Bool(name string) bool  { return c.bools[name] }
func (c *Ctx) Has(name string) bool {
	_, ok := c.vals[name]
	return ok || c.bools[name]
}

// PrintJSON writes v as indented JSON.
func (c *Ctx) PrintJSON(v any) error {
	enc := json.NewEncoder(c.Out)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

// Confirm asks unless --yes was given.
func (c *Ctx) Confirm(q string) bool {
	if c.Yes {
		return true
	}
	if !ui.IsTTY() {
		ui.Err("refusing without confirmation in a non-interactive shell — pass --yes")
		return false
	}
	return ui.Confirm(q)
}

var globalFlags = []Flag{
	{Long: "json", Help: "machine-readable JSON output (list/show/info commands)"},
	{Long: "no-color", Help: "disable colors (also: NO_COLOR=1)"},
	{Long: "yes", Short: "y", Help: "assume yes for confirmations"},
	{Long: "help", Short: "h", Help: "help for any command"},
}

// errUsage marks errors that should be followed by the command's usage line.
type errUsage struct{ msg string }

func (e errUsage) Error() string { return e.msg }

func usageErr(format string, a ...any) error { return errUsage{fmt.Sprintf(format, a...)} }

func needArgs(args []string, n int, what string) error {
	if len(args) < n {
		return usageErr("missing %s", what)
	}
	return nil
}

func (cmd *Command) path() string {
	if cmd.parent == nil {
		return cmd.Name
	}
	return cmd.parent.path() + " " + cmd.Name
}

func (cmd *Command) find(name string) *Command {
	for _, s := range cmd.Sub {
		if s.Name == name {
			return s
		}
		for _, a := range s.Aliases {
			if a == name {
				return s
			}
		}
	}
	return nil
}

func link(cmd *Command) {
	for _, s := range cmd.Sub {
		s.parent = cmd
		link(s)
	}
}

// Execute runs msh with the given arguments and returns the exit code.
func Execute(root *Command, args []string) int {
	link(root)
	ctx := &Ctx{P: store.DefaultPaths(), Out: os.Stdout, vals: map[string]string{}, bools: map[string]bool{}}
	help := false

	// Completion requests carry raw, partial words: never parse them as flags.
	if len(args) > 0 && args[0] == "__complete" {
		for _, s := range completeWords(ctx, root, args[1:]) {
			fmt.Fprintln(ctx.Out, s)
		}
		return 0
	}

	// Pull global flags out wherever they appear (before a lone "--").
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			rest = append(rest, args[i:]...)
			break
		}
		switch a {
		case "--json":
			ctx.JSON = true
		case "--no-color":
			ui.Color = false
		case "-y", "--yes":
			ctx.Yes = true
		case "-h", "--help":
			help = true
		case "-v", "--version":
			if len(rest) == 0 {
				rest = append(rest, "version")
			} else {
				rest = append(rest, a)
			}
		default:
			rest = append(rest, a)
		}
	}

	cmd := root
	for len(rest) > 0 {
		if strings.HasPrefix(rest[0], "-") {
			break
		}
		next := cmd.find(rest[0])
		if next == nil {
			break
		}
		cmd, rest = next, rest[1:]
	}
	ctx.cmd = cmd

	if rest, err := parseFlags(ctx, cmd, rest); err != nil {
		ui.Err("%v", err)
		fmt.Fprintln(os.Stderr, ui.GrayText("usage: msh "+strings.TrimPrefix(cmd.path()+" "+cmd.Usage, "msh ")))
		return 2
	} else {
		if help || (cmd.Run == nil && len(rest) == 0 && cmd != root) {
			printHelp(os.Stdout, cmd)
			return 0
		}
		if cmd.Run == nil {
			ui.Err("unknown command: %s", strings.Join(rest, " "))
			suggest(cmd, rest[0])
			return 2
		}
		if err := cmd.Run(ctx, rest); err != nil {
			var ue errUsage
			if errors.As(err, &ue) {
				ui.Err("%v", err)
				fmt.Fprintln(os.Stderr, ui.GrayText("usage: msh "+strings.TrimPrefix(cmd.path()+" "+cmd.Usage, "msh ")))
				fmt.Fprintln(os.Stderr, ui.GrayText("help:  msh "+strings.TrimPrefix(cmd.path(), "msh ")+" --help"))
				return 2
			}
			ui.Err("%v", err)
			return 1
		}
	}
	return 0
}

func parseFlags(ctx *Ctx, cmd *Command, args []string) ([]string, error) {
	var pos []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			pos = append(pos, args[i+1:]...)
			break
		}
		if !strings.HasPrefix(a, "-") || a == "-" {
			pos = append(pos, a)
			continue
		}
		name, val, hasVal := strings.Cut(strings.TrimLeft(a, "-"), "=")
		var f *Flag
		for j := range cmd.Flags {
			if cmd.Flags[j].Long == name || (cmd.Flags[j].Short != "" && cmd.Flags[j].Short == name && !strings.HasPrefix(a, "--")) {
				f = &cmd.Flags[j]
			}
		}
		if f == nil {
			return nil, fmt.Errorf("unknown flag %s for 'msh %s'", a, strings.TrimPrefix(cmd.path(), "msh "))
		}
		if f.Arg == "" {
			ctx.bools[f.Long] = true
			continue
		}
		if !hasVal {
			if i+1 >= len(args) {
				return nil, fmt.Errorf("flag --%s needs a value (%s)", f.Long, f.Arg)
			}
			i++
			val = args[i]
		}
		ctx.vals[f.Long] = val
	}
	return pos, nil
}

func suggest(cmd *Command, typed string) {
	var names []string
	for _, s := range cmd.Sub {
		if !s.Hidden && (strings.HasPrefix(s.Name, typed[:min(2, len(typed))]) || strings.Contains(s.Name, typed)) {
			names = append(names, s.Name)
		}
	}
	if len(names) > 0 {
		fmt.Fprintln(os.Stderr, ui.GrayText("did you mean: "+strings.Join(names, ", ")+"?"))
	}
	fmt.Fprintln(os.Stderr, ui.GrayText("run 'msh --help' for the command list"))
}

func printHelp(w io.Writer, cmd *Command) {
	title := ui.Bold(ui.Blue(cmd.path()))
	fmt.Fprintf(w, "%s — %s\n", title, cmd.Summary)
	if cmd.Long != "" {
		fmt.Fprintln(w)
		for _, ln := range strings.Split(strings.TrimSpace(cmd.Long), "\n") {
			fmt.Fprintln(w, "  "+ln)
		}
	}
	section := func(s string) { fmt.Fprintln(w, "\n"+ui.Bold(s)) }

	section("USAGE")
	usage := cmd.Usage
	if usage == "" && len(cmd.Sub) > 0 {
		usage = "<command> [flags]"
	}
	fmt.Fprintf(w, "  %s %s\n", cmd.path(), ui.Lilac(usage))

	if len(cmd.Sub) > 0 {
		section("COMMANDS")
		width := 0
		for _, s := range cmd.Sub {
			if !s.Hidden {
				width = max(width, len(s.Name))
			}
		}
		for _, s := range cmd.Sub {
			if s.Hidden {
				continue
			}
			alias := ""
			if len(s.Aliases) > 0 {
				alias = ui.GrayText(" (" + strings.Join(s.Aliases, ", ") + ")")
			}
			fmt.Fprintf(w, "  %s%s  %s%s\n", ui.Green(s.Name), strings.Repeat(" ", width-len(s.Name)), s.Summary, alias)
		}
	}
	printFlags := func(name string, flags []Flag) {
		if len(flags) == 0 {
			return
		}
		section(name)
		var rows [][2]string
		width := 0
		for _, f := range flags {
			left := "    --" + f.Long
			if f.Short != "" {
				left = "-" + f.Short + ", --" + f.Long
			}
			if f.Arg != "" {
				left += " " + f.Arg
			}
			rows = append(rows, [2]string{left, f.Help})
			width = max(width, len(left))
		}
		for _, r := range rows {
			fmt.Fprintf(w, "  %s%s  %s\n", ui.Yellow(r[0]), strings.Repeat(" ", width-len(r[0])), r[1])
		}
	}
	printFlags("FLAGS", cmd.Flags)
	printFlags("GLOBAL FLAGS", globalFlags)
	if len(cmd.Examples) > 0 {
		section("EXAMPLES")
		for _, e := range cmd.Examples {
			if strings.HasPrefix(e, "#") {
				fmt.Fprintln(w, "  "+ui.GrayText(e))
			} else {
				fmt.Fprintln(w, "  "+ui.Green("$")+" "+e)
			}
		}
	}
	if len(cmd.Sub) > 0 {
		fmt.Fprintln(w, "\n"+ui.GrayText("Run '"+cmd.path()+" <command> --help' for details on a command."))
	}
}

// sortedKeys is a small helper for deterministic output.
func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
