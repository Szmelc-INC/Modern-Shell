package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/Szmelc-INC/Modern-Shell/internal/store"
	"github.com/Szmelc-INC/Modern-Shell/internal/tui"
	"github.com/Szmelc-INC/Modern-Shell/internal/ui"
)

// Root builds the full msh command tree.
func Root(version string) *Command {
	root := &Command{
		Name:    "msh",
		Summary: "Modern Shell — manage your zsh: addons, aliases, functions, env, secrets, dirs, snapshots",
		Usage:   "[command] [flags]",
		Long: `Without a command, msh opens the interactive TUI (F1 = help, ? = keys, : = commands).
Every change is written to your layer in ~/.config/msh/user and applies to new shells
(run 'reload' or 'exec zsh' in an open one).`,
		Flags: []Flag{{Long: "tab", Short: "t", Arg: "TAB", Help: "TUI: start on a tab (addons, aliases, functions, env, secrets, dirs, snapshots)"}},
		Examples: []string{
			"msh                         # open the TUI",
			"msh addon list --json",
			"msh alias add gs 'git status -sb' -d 'short git status'",
			"msh secret set OPENAI_API_KEY   # prompts without echo",
			"msh snapshot create -l before-experiment",
		},
	}
	root.Run = func(c *Ctx, args []string) error {
		if len(args) > 0 {
			return usageErr("unknown command %q (see: msh --help)", args[0])
		}
		return runTUI(c, c.Str("tab"))
	}
	root.Sub = []*Command{
		{Name: "tui", Summary: "Open the interactive TUI", Usage: "[TAB]", Complete: "tab",
			Run: func(c *Ctx, args []string) error {
				tab := ""
				if len(args) > 0 {
					tab = args[0]
				}
				return runTUI(c, tab)
			}},
		addonCmd(),
		managedCmd(store.KindAlias),
		funcCmd(),
		managedCmd(store.KindEnv),
		managedCmd(store.KindSecret),
		dirCmd(),
		snapshotCmd(),
		{Name: "doctor", Summary: "Check the installation and dependencies", Run: doctor},
		{Name: "paths", Summary: "Show where msh keeps everything", Run: paths},
		{Name: "update", Aliases: []string{"install"}, Summary: "Re-run the installer from the recorded source (takes a snapshot first)",
			Flags: []Flag{{Long: "dry-run", Short: "n", Help: "show what would change"}},
			Run:   update},
		{Name: "completion", Summary: "Print a shell completion script (zsh, bash, fish)", Usage: "<zsh|bash|fish>", Complete: "shell",
			Examples: []string{"msh completion zsh > ~/.config/msh/completions/_msh", "msh completion fish > ~/.config/fish/completions/msh.fish"},
			Run: func(c *Ctx, args []string) error {
				if err := needArgs(args, 1, "shell name"); err != nil {
					return err
				}
				return printCompletion(c, root, args[0])
			}},
		{Name: "version", Summary: "Print the version",
			Run: func(c *Ctx, args []string) error {
				if c.JSON {
					return c.PrintJSON(map[string]string{"msh": version, "framework": c.P.Version(), "go": runtime.Version()})
				}
				fmt.Fprintf(c.Out, "%s %s %s\n", ui.Bold("msh"), version, ui.GrayText("(framework "+orDash(c.P.Version())+", "+runtime.Version()+")"))
				return nil
			}},
		{Name: "help", Summary: "Help for a command", Usage: "[command...]",
			Run: func(c *Ctx, args []string) error {
				cmd := root
				for _, a := range args {
					if n := cmd.find(a); n != nil {
						cmd = n
					}
				}
				printHelp(c.Out, cmd)
				return nil
			}},
		{Name: "__complete", Hidden: true, Summary: "internal: print completion candidates",
			Run: func(c *Ctx, args []string) error {
				for _, s := range completeWords(c, root, args) {
					fmt.Fprintln(c.Out, s)
				}
				return nil
			}},
	}
	return root
}

func runTUI(c *Ctx, tab string) error {
	if !ui.IsTTY() {
		return fmt.Errorf("the TUI needs an interactive terminal — try 'msh --help' for commands")
	}
	return tui.Run(c.P, tab)
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

// ── addon ─────────────────────────────────────────────────────────────────

func addonCmd() *Command {
	stateArgs := func(on bool) func(c *Ctx, args []string) error {
		return func(c *Ctx, args []string) error {
			if err := needArgs(args, 1, "addon name"); err != nil {
				return err
			}
			for _, name := range args {
				if _, err := store.FindAddon(c.P, name); err != nil {
					return err
				}
				if err := store.SetAddonState(c.P, name, on); err != nil {
					return err
				}
				ui.Ok("%s %s %s", name, map[bool]string{true: "enabled", false: "disabled"}[on], ui.GrayText("(new shells; 'reload' here)"))
			}
			return nil
		}
	}
	return &Command{
		Name: "addon", Aliases: []string{"addons", "a"}, Summary: "List, inspect, enable/disable, create, edit and remove addons",
		Sub: []*Command{
			{Name: "list", Aliases: []string{"ls"}, Summary: "List addons",
				Flags: []Flag{{Long: "enabled", Help: "only enabled"}, {Long: "disabled", Help: "only disabled"}, {Long: "tag", Arg: "TAG", Help: "filter by tag"}},
				Run: func(c *Ctx, args []string) error {
					all, err := store.LoadAddons(c.P)
					if err != nil {
						return err
					}
					var list []store.Addon
					for _, a := range all {
						if (c.Bool("enabled") && !a.Enabled) || (c.Bool("disabled") && a.Enabled) {
							continue
						}
						if t := c.Str("tag"); t != "" && !containsFold(a.Tags, t) {
							continue
						}
						list = append(list, a)
					}
					if c.JSON {
						return c.PrintJSON(list)
					}
					t := ui.Table{Headers: []string{"STATE", "ADDON", "SOURCE", "TAGS", "DESCRIPTION"}, MaxCol: 70}
					for _, a := range list {
						src := "shipped"
						if a.Overrides {
							src = ui.Yellow("override")
						} else if a.User {
							src = ui.Lilac("user")
						}
						t.Rows = append(t.Rows, []string{ui.OnOff(a.Enabled), ui.Bold(a.Name), src, ui.GrayText(strings.Join(a.Tags, ",")), a.Desc})
					}
					t.Render(c.Out)
					return nil
				}},
			{Name: "info", Aliases: []string{"show"}, Summary: "Show an addon: header, dependencies, aliases, functions", Usage: "<name>", Complete: "addon",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					a, err := store.FindAddon(c.P, args[0])
					if err != nil {
						return err
					}
					if c.JSON {
						return c.PrintJSON(a)
					}
					printAddon(c, a)
					return nil
				}},
			{Name: "enable", Aliases: []string{"on"}, Summary: "Enable addons", Usage: "<name>...", Complete: "addon", Run: stateArgs(true)},
			{Name: "disable", Aliases: []string{"off"}, Summary: "Disable addons", Usage: "<name>...", Complete: "addon", Run: stateArgs(false)},
			{Name: "toggle", Summary: "Flip an addon on/off", Usage: "<name>", Complete: "addon",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					a, err := store.FindAddon(c.P, args[0])
					if err != nil {
						return err
					}
					return stateArgs(!a.Enabled)(c, args[:1])
				}},
			{Name: "new", Aliases: []string{"add", "create"}, Summary: "Create a user addon from a template and open it in $EDITOR", Usage: "<name>",
				Flags: []Flag{{Long: "desc", Short: "d", Arg: "TEXT", Help: "one-line description"}, {Long: "tags", Arg: "LIST", Help: "comma-separated tags"}, {Long: "no-edit", Help: "do not open an editor"}},
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					path, err := store.NewUserAddon(c.P, args[0], c.Str("desc"), c.Str("tags"))
					if err != nil {
						return err
					}
					ui.Ok("created %s", c.P.Tilde(path))
					if !c.Bool("no-edit") && ui.IsTTY() {
						return openEditor(path)
					}
					return nil
				}},
			{Name: "edit", Summary: "Edit an addon in $EDITOR (shipped ones are copied to your layer first)", Usage: "<name>", Complete: "addon",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					a, err := store.FindAddon(c.P, args[0])
					if err != nil {
						return err
					}
					path, err := store.OverrideAddon(c.P, a)
					if err != nil {
						return err
					}
					if !a.User {
						ui.Info("copied shipped addon to %s (your copy wins; delete it to go back)", c.P.Tilde(path))
					}
					return openEditor(path)
				}},
			{Name: "rm", Aliases: []string{"remove", "delete"}, Summary: "Delete a user addon (shipped addons can only be disabled)", Usage: "<name>", Complete: "addon",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					a, err := store.FindAddon(c.P, args[0])
					if err != nil {
						return err
					}
					if !a.User {
						return fmt.Errorf("%q is shipped with msh — use 'msh addon disable %s'", a.Name, a.Name)
					}
					if !c.Confirm(fmt.Sprintf("Delete %s?", c.P.Tilde(a.File))) {
						return fmt.Errorf("cancelled")
					}
					if err := store.DeleteUserAddon(c.P, a); err != nil {
						return err
					}
					ui.Ok("deleted %s", a.Name)
					return nil
				}},
			{Name: "path", Summary: "Print an addon's file path", Usage: "<name>", Complete: "addon",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "addon name"); err != nil {
						return err
					}
					a, err := store.FindAddon(c.P, args[0])
					if err != nil {
						return err
					}
					fmt.Fprintln(c.Out, a.File)
					return nil
				}},
		},
	}
}

func printAddon(c *Ctx, a store.Addon) {
	w := c.Out
	fmt.Fprintf(w, "%s %s  %s\n", ui.Bold(ui.Blue(a.Name)), ui.OnOff(a.Enabled), ui.GrayText(a.Version))
	fmt.Fprintln(w, "  "+a.Desc)
	kv := func(k, v string) {
		if v != "" {
			fmt.Fprintf(w, "  %s %s\n", ui.Yellow(fmt.Sprintf("%-9s", k)), v)
		}
	}
	kv("tags", strings.Join(a.Tags, ", "))
	kv("default", map[bool]string{true: "on", false: "off"}[a.Default])
	kv("file", c.P.Tilde(a.File))
	kv("author", a.Dev)
	if deps := a.DepStatus(); len(deps) > 0 {
		var parts []string
		for _, d := range deps {
			mark := ui.Green("✔")
			if !d.Installed {
				mark = ui.Red("✘")
				if d.Optional {
					mark = ui.Yellow("·")
				}
			}
			parts = append(parts, mark+" "+d.Name)
		}
		kv("deps", strings.Join(parts, "  "))
	}
	for _, e := range a.Examples {
		kv("example", ui.Green(e))
	}
	if fns := a.Functions(); len(fns) > 0 {
		fmt.Fprintln(w, "\n"+ui.Bold("Functions"))
		for _, d := range fns {
			fmt.Fprintf(w, "  %s  %s\n", ui.Green(fmt.Sprintf("%-18s", d.Name)), ui.GrayText(d.Summary()))
		}
	}
	if al := a.Aliases(); len(al) > 0 {
		fmt.Fprintln(w, "\n"+ui.Bold("Aliases"))
		for _, d := range al {
			fmt.Fprintf(w, "  %s  %s %s\n", ui.Lilac(fmt.Sprintf("%-12s", d.Name)), d.Value, ui.GrayText(summarySuffix(d.Summary())))
		}
	}
	if a.Help != "" {
		fmt.Fprintln(w, "\n"+ui.Bold("Help"))
		for _, ln := range strings.Split(a.Help, "\n") {
			fmt.Fprintln(w, "  "+ln)
		}
	}
}

func summarySuffix(s string) string {
	if s == "" {
		return ""
	}
	return "— " + s
}

func containsFold(list []string, s string) bool {
	for _, x := range list {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

// ── alias / env / secret (shared logic) ───────────────────────────────────

func managedFile(p store.Paths, k store.Kind) (*store.ManagedFile, error) {
	switch k {
	case store.KindAlias:
		return store.LoadManaged(p.AliasesFile(), k)
	case store.KindEnv:
		return store.LoadManaged(p.EnvFile(), k)
	default:
		return store.LoadManaged(p.SecretsFile(), k)
	}
}

func managedCmd(k store.Kind) *Command {
	noun := string(k)
	secret := k == store.KindSecret
	load := func(c *Ctx) (*store.ManagedFile, error) { return managedFile(c.P, k) }
	toggle := func(on bool) func(c *Ctx, args []string) error {
		return func(c *Ctx, args []string) error {
			if err := needArgs(args, 1, noun+" name"); err != nil {
				return err
			}
			mf, err := load(c)
			if err != nil {
				return err
			}
			for _, n := range args {
				if _, err := mf.Toggle(n, &on); err != nil {
					return err
				}
			}
			if err := mf.Save(); err != nil {
				return err
			}
			ui.Ok("%s %s", strings.Join(args, ", "), map[bool]string{true: "enabled", false: "disabled"}[on])
			return nil
		}
	}
	valueHelp := map[store.Kind]string{store.KindAlias: "command the alias expands to", store.KindEnv: "value", store.KindSecret: "value (omit to type it hidden)"}[k]
	setCmd := &Command{
		Name: "set", Aliases: []string{"add"}, Summary: "Add or change a " + noun, Usage: "<NAME> <VALUE>", Complete: noun,
		Flags: []Flag{{Long: "desc", Short: "d", Arg: "TEXT", Help: "description shown in the TUI"}, {Long: "disabled", Help: "add it switched off"}, {Long: "rename", Arg: "OLD", Help: "rename OLD to NAME while setting"}},
		Run: func(c *Ctx, args []string) error {
			if err := needArgs(args, 1, noun+" name"); err != nil {
				return err
			}
			var value string
			switch {
			case len(args) >= 2:
				value = strings.Join(args[1:], " ")
			case secret:
				v, err := ui.ReadSecret("value for " + args[0])
				if err != nil {
					return err
				}
				value = v
			default:
				return usageErr("missing %s", valueHelp)
			}
			mf, err := load(c)
			if err != nil {
				return err
			}
			old := c.Str("rename")
			it, exists := mf.Get(args[0])
			if old != "" {
				it, exists = mf.Get(old)
				if !exists {
					return fmt.Errorf("%s %q not found", noun, old)
				}
			}
			it.Name, it.Value = args[0], value
			if c.Has("desc") {
				it.Desc = c.Str("desc")
			}
			if !exists {
				it.Enabled = !c.Bool("disabled")
			}
			if err := mf.Set(old, it); err != nil {
				return err
			}
			if err := mf.Save(); err != nil {
				return err
			}
			shown := value
			if secret {
				shown = store.Mask(value)
			}
			ui.Ok("%s %s = %s %s", noun, ui.Bold(args[0]), shown, ui.GrayText("(new shells; 'reload' here)"))
			return nil
		},
	}
	if k == store.KindAlias {
		setCmd.Examples = []string{"msh alias add gs 'git status -sb' -d 'short status'", "msh alias set ll 'eza -la' --disabled"}
	} else if secret {
		setCmd.Examples = []string{"msh secret set GITHUB_TOKEN          # hidden prompt", "pass show gh | msh secret set GITHUB_TOKEN   # from a pipe"}
		setCmd.Long = "Secrets are exported to every new shell from ~/.config/msh/user/secrets.zsh (mode 600).\nPrefer the hidden prompt or a pipe: a value on the command line lands in your history."
	}
	cmd := &Command{
		Name: noun, Summary: map[store.Kind]string{
			store.KindAlias:  "Manage your aliases (user/aliases.zsh)",
			store.KindEnv:    "Manage environment variables (user/env.zsh)",
			store.KindSecret: "Manage secrets — masked, mode 600 (user/secrets.zsh)",
		}[k],
		Sub: []*Command{
			{Name: "list", Aliases: []string{"ls"}, Summary: "List " + noun + "es",
				Flags: managedListFlags(k),
				Run: func(c *Ctx, args []string) error {
					mf, err := load(c)
					if err != nil {
						return err
					}
					items := mf.Items()
					reveal := secret && c.Bool("reveal")
					if c.JSON {
						if secret && !reveal {
							for i := range items {
								items[i].Value = store.Mask(items[i].Value)
							}
						}
						if k == store.KindAlias && c.Bool("all") {
							addons, _ := store.LoadAddons(c.P)
							return c.PrintJSON(map[string]any{"user": items, "addons": store.AllDefs(addons, store.KindAlias)})
						}
						return c.PrintJSON(items)
					}
					t := ui.Table{Headers: []string{"STATE", "NAME", "VALUE", "DESCRIPTION"}, MaxCol: 60}
					for _, it := range items {
						v := it.Value
						if secret && !reveal {
							v = ui.GrayText(store.Mask(v))
						}
						t.Rows = append(t.Rows, []string{ui.OnOff(it.Enabled), ui.Bold(it.Name), v, ui.GrayText(it.Desc)})
					}
					if k == store.KindAlias && c.Bool("all") {
						addons, _ := store.LoadAddons(c.P)
						on := map[string]bool{}
						for _, a := range addons {
							on[a.Name] = a.Enabled
						}
						t.Headers = []string{"STATE", "NAME", "VALUE", "SOURCE"}
						for i := range t.Rows {
							t.Rows[i][3] = ui.Lilac("user")
						}
						for _, d := range store.AllDefs(addons, store.KindAlias) {
							t.Rows = append(t.Rows, []string{ui.OnOff(on[d.Addon]), d.Name, d.Value, ui.GrayText("addon:" + d.Addon)})
						}
					}
					if len(t.Rows) == 0 {
						ui.Info("no %ses yet — add one with: msh %s set NAME VALUE", noun, noun)
						return nil
					}
					t.Render(c.Out)
					return nil
				}},
			setCmd,
			{Name: "show", Aliases: []string{"get"}, Summary: "Print one " + noun + "'s value", Usage: "<NAME>", Complete: noun,
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, noun+" name"); err != nil {
						return err
					}
					mf, err := load(c)
					if err != nil {
						return err
					}
					it, ok := mf.Get(args[0])
					if !ok {
						return fmt.Errorf("%s %q not found", noun, args[0])
					}
					if secret && !c.Bool("reveal") {
						it.Value = store.Mask(it.Value)
					}
					if c.JSON {
						return c.PrintJSON(it)
					}
					fmt.Fprintln(c.Out, it.Value)
					return nil
				},
				Flags: secretRevealFlag(secret)},
			{Name: "rm", Aliases: []string{"remove", "delete", "unset"}, Summary: "Delete a " + noun, Usage: "<NAME>...", Complete: noun,
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, noun+" name"); err != nil {
						return err
					}
					mf, err := load(c)
					if err != nil {
						return err
					}
					for _, n := range args {
						if _, ok := mf.Get(n); !ok {
							return fmt.Errorf("%s %q not found", noun, n)
						}
					}
					if !c.Confirm(fmt.Sprintf("Delete %s %s?", noun, strings.Join(args, ", "))) {
						return fmt.Errorf("cancelled")
					}
					for _, n := range args {
						mf.Delete(n)
					}
					if err := mf.Save(); err != nil {
						return err
					}
					ui.Ok("deleted %s", strings.Join(args, ", "))
					return nil
				}},
			{Name: "enable", Aliases: []string{"on"}, Summary: "Switch on", Usage: "<NAME>...", Complete: noun, Run: toggle(true)},
			{Name: "disable", Aliases: []string{"off"}, Summary: "Switch off (kept, commented with #off#)", Usage: "<NAME>...", Complete: noun, Run: toggle(false)},
		},
	}
	switch k {
	case store.KindAlias:
		cmd.Aliases = []string{"aliases", "al"}
	case store.KindEnv:
		cmd.Aliases = []string{"var", "vars"}
	case store.KindSecret:
		cmd.Aliases = []string{"secrets", "sec"}
	}
	return cmd
}

func managedListFlags(k store.Kind) []Flag {
	switch k {
	case store.KindAlias:
		return []Flag{{Long: "all", Short: "a", Help: "include aliases defined by addons"}}
	case store.KindSecret:
		return secretRevealFlag(true)
	}
	return nil
}

func secretRevealFlag(secret bool) []Flag {
	if !secret {
		return nil
	}
	return []Flag{{Long: "reveal", Help: "show values in clear text"}}
}

// ── func ──────────────────────────────────────────────────────────────────

func funcCmd() *Command {
	toggle := func(on bool) func(c *Ctx, args []string) error {
		return func(c *Ctx, args []string) error {
			if err := needArgs(args, 1, "function name"); err != nil {
				return err
			}
			for _, n := range args {
				f, err := store.FindUserFunc(c.P, n)
				if err != nil {
					return err
				}
				if _, err := store.ToggleUserFunc(f, &on); err != nil {
					return err
				}
			}
			ui.Ok("%s %s", strings.Join(args, ", "), map[bool]string{true: "enabled", false: "disabled"}[on])
			return nil
		}
	}
	return &Command{
		Name: "func", Aliases: []string{"function", "functions", "fn"}, Summary: "Manage your functions (user/functions/<name>.zsh)",
		Sub: []*Command{
			{Name: "list", Aliases: []string{"ls"}, Summary: "List functions",
				Flags: []Flag{{Long: "all", Short: "a", Help: "include functions defined by addons"}},
				Run: func(c *Ctx, args []string) error {
					fns, err := store.LoadUserFuncs(c.P)
					if err != nil {
						return err
					}
					var addons []store.Addon
					if c.Bool("all") {
						addons, _ = store.LoadAddons(c.P)
					}
					if c.JSON {
						if c.Bool("all") {
							return c.PrintJSON(map[string]any{"user": fns, "addons": store.AllDefs(addons, store.KindFunction)})
						}
						return c.PrintJSON(fns)
					}
					t := ui.Table{Headers: []string{"STATE", "FUNCTION", "SOURCE", "DESCRIPTION"}, MaxCol: 70}
					for _, f := range fns {
						t.Rows = append(t.Rows, []string{ui.OnOff(f.Enabled), ui.Bold(f.Name), ui.Lilac("user"), f.Desc})
					}
					on := map[string]bool{}
					for _, a := range addons {
						on[a.Name] = a.Enabled
					}
					for _, d := range store.AllDefs(addons, store.KindFunction) {
						t.Rows = append(t.Rows, []string{ui.OnOff(on[d.Addon]), d.Name, ui.GrayText("addon:" + d.Addon), d.Summary()})
					}
					if len(t.Rows) == 0 {
						ui.Info("no functions yet — add one with: msh func add NAME")
						return nil
					}
					t.Render(c.Out)
					return nil
				}},
			{Name: "show", Summary: "Print a function's source", Usage: "<name>", Complete: "func",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "function name"); err != nil {
						return err
					}
					if f, err := store.FindUserFunc(c.P, args[0]); err == nil {
						if c.JSON {
							return c.PrintJSON(f)
						}
						fmt.Fprint(c.Out, f.Raw)
						return nil
					}
					addons, _ := store.LoadAddons(c.P)
					for _, d := range store.AllDefs(addons, store.KindFunction) {
						if d.Name == args[0] {
							if c.JSON {
								return c.PrintJSON(d)
							}
							fmt.Fprintln(c.Out, ui.GrayText("# from addon "+d.Addon))
							fmt.Fprintln(c.Out, d.Value)
							return nil
						}
					}
					return fmt.Errorf("function %q not found", args[0])
				}},
			{Name: "add", Aliases: []string{"new", "set"}, Summary: "Create or replace a function (body from --body, stdin or $EDITOR)", Usage: "<name>",
				Flags: []Flag{{Long: "desc", Short: "d", Arg: "TEXT", Help: "description"}, {Long: "body", Short: "b", Arg: "CODE", Help: "function body (the part inside { })"}},
				Examples: []string{
					`msh func add greet -d 'say hi' -b 'echo "hi ${1:-world}"'`,
					`printf 'local d=$1\nmkdir -p -- "$d" && cd -- "$d"' | msh func add mcd`,
					"msh func add backup-notes        # opens $EDITOR",
				},
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "function name"); err != nil {
						return err
					}
					uf := store.UserFunc{Name: args[0], Desc: c.Str("desc"), Body: c.Str("body"), Enabled: true}
					if old, err := store.FindUserFunc(c.P, args[0]); err == nil {
						uf.Enabled = old.Enabled
						if !c.Has("desc") {
							uf.Desc = old.Desc
						}
						if !c.Has("body") {
							uf.Body = old.Body
						}
					}
					if !c.Has("body") && !ui.IsTTY() {
						b, _ := readAll(os.Stdin)
						uf.Body = b
					}
					if uf.Body == "" {
						uf.Body = "# write your code here; $1, $2… are the arguments\nmsh::ok \"hello from " + uf.Name + "\""
					}
					if err := store.SaveUserFunc(c.P, "", uf); err != nil {
						return err
					}
					f, _ := store.FindUserFunc(c.P, uf.Name)
					ui.Ok("function %s saved → %s", ui.Bold(uf.Name), c.P.Tilde(f.File))
					if !c.Has("body") && ui.IsTTY() {
						return openEditor(f.File)
					}
					return nil
				}},
			{Name: "edit", Summary: "Edit a function file in $EDITOR", Usage: "<name>", Complete: "func",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "function name"); err != nil {
						return err
					}
					f, err := store.FindUserFunc(c.P, args[0])
					if err != nil {
						return fmt.Errorf("%v (addon functions: msh addon edit <addon>)", err)
					}
					return openEditor(f.File)
				}},
			{Name: "rm", Aliases: []string{"remove", "delete"}, Summary: "Delete a function", Usage: "<name>", Complete: "func",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "function name"); err != nil {
						return err
					}
					f, err := store.FindUserFunc(c.P, args[0])
					if err != nil {
						return err
					}
					if !c.Confirm("Delete function " + f.Name + "?") {
						return fmt.Errorf("cancelled")
					}
					if err := os.Remove(f.File); err != nil {
						return err
					}
					ui.Ok("deleted %s", f.Name)
					return nil
				}},
			{Name: "enable", Aliases: []string{"on"}, Summary: "Switch on", Usage: "<name>...", Complete: "func", Run: toggle(true)},
			{Name: "disable", Aliases: []string{"off"}, Summary: "Switch off (renamed to .zsh.off)", Usage: "<name>...", Complete: "func", Run: toggle(false)},
		},
	}
}

// ── dir (zoxide) ──────────────────────────────────────────────────────────

func dirCmd() *Command {
	return &Command{
		Name: "dir", Aliases: []string{"dirs", "z"}, Summary: "Manage zoxide directories (what 'cd <keyword>' jumps to)",
		Sub: []*Command{
			{Name: "list", Aliases: []string{"ls"}, Summary: "List known directories by score",
				Flags: []Flag{{Long: "limit", Short: "n", Arg: "N", Help: "show only the top N"}},
				Run: func(c *Ctx, args []string) error {
					dirs, err := store.ListDirs()
					if err != nil {
						return err
					}
					if n := atoi(c.Str("limit")); n > 0 && n < len(dirs) {
						dirs = dirs[:n]
					}
					if c.JSON {
						return c.PrintJSON(dirs)
					}
					t := ui.Table{Headers: []string{"SCORE", "DIRECTORY"}, MaxCol: 100}
					for _, d := range dirs {
						path := c.P.Tilde(d.Path)
						if !d.Exists {
							path = ui.Red(path + " (missing)")
						}
						t.Rows = append(t.Rows, []string{ui.Yellow(fmt.Sprintf("%7.1f", d.Score)), path})
					}
					t.Render(c.Out)
					return nil
				}},
			{Name: "add", Summary: "Add or bump a directory", Usage: "<path>...", Complete: "dirpath",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "path"); err != nil {
						return err
					}
					for _, a := range args {
						abs, _ := filepath.Abs(a)
						if err := store.AddDir(abs); err != nil {
							return err
						}
						ui.Ok("added %s", c.P.Tilde(abs))
					}
					return nil
				}},
			{Name: "rm", Aliases: []string{"remove"}, Summary: "Forget a directory", Usage: "<path>...", Complete: "dir",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "path"); err != nil {
						return err
					}
					for _, a := range args {
						if err := store.RemoveDir(expandHome(c.P, a)); err != nil {
							return err
						}
						ui.Ok("removed %s", a)
					}
					return nil
				}},
			{Name: "exclude", Summary: "Never record a directory again (_ZO_EXCLUDE_DIRS in user/env.zsh)", Usage: "<path>", Complete: "dir",
				Run: func(c *Ctx, args []string) error {
					if err := needArgs(args, 1, "path"); err != nil {
						return err
					}
					p := expandHome(c.P, args[0])
					if err := store.ExcludeDir(c.P, p); err != nil {
						return err
					}
					ui.Ok("excluded %s %s", c.P.Tilde(p), ui.GrayText("(new shells)"))
					return nil
				}},
			{Name: "prune", Summary: "Remove entries whose directory no longer exists",
				Run: func(c *Ctx, args []string) error {
					dirs, err := store.ListDirs()
					if err != nil {
						return err
					}
					n := 0
					for _, d := range dirs {
						if !d.Exists {
							if err := store.RemoveDir(d.Path); err == nil {
								n++
							}
						}
					}
					ui.Ok("removed %d missing director%s", n, map[bool]string{true: "y", false: "ies"}[n == 1])
					return nil
				}},
		},
	}
}

// ── snapshot (delegates to the snapshot addon) ────────────────────────────

func snapshotCmd() *Command {
	passthrough := func(sub string) func(c *Ctx, args []string) error {
		return func(c *Ctx, args []string) error {
			if c.Yes {
				args = append(args, "-y")
			}
			return runSnapshot(c, append([]string{sub}, args...)...)
		}
	}
	return &Command{
		Name: "snapshot", Aliases: []string{"snap", "backup"}, Summary: "Snapshots of everything msh modifies (~/.BACKUP/msh)",
		Long: "Same engine as the zsh 'snapshot' command. The installer takes one automatically\nbefore every install, and restore takes a safety snapshot before reverting.",
		Sub: []*Command{
			{Name: "list", Aliases: []string{"ls"}, Summary: "List snapshots, newest first (#1 = latest)",
				Run: func(c *Ctx, args []string) error {
					if c.JSON {
						snaps, err := store.ListSnapshots(c.P)
						if err != nil {
							return err
						}
						return c.PrintJSON(snaps)
					}
					return runSnapshot(c, "list")
				}},
			{Name: "create", Aliases: []string{"new"}, Summary: "Snapshot the current state",
				Flags: []Flag{{Long: "label", Short: "l", Arg: "NAME", Help: "short label added to the id"}, {Long: "reason", Short: "r", Arg: "TEXT", Help: "why (shown in list)"}},
				Run: func(c *Ctx, args []string) error {
					a := []string{"create"}
					if v := c.Str("label"); v != "" {
						a = append(a, "-l", v)
					}
					if v := c.Str("reason"); v != "" {
						a = append(a, "-r", v)
					}
					return runSnapshot(c, append(a, args...)...)
				}},
			{Name: "show", Aliases: []string{"info"}, Summary: "Metadata and contents", Usage: "<id|#>", Complete: "snapshot", Run: passthrough("show")},
			{Name: "diff", Summary: "What changed since a snapshot", Usage: "<id|#>", Complete: "snapshot", Run: passthrough("diff")},
			{Name: "restore", Aliases: []string{"revert"}, Summary: "Fully revert to a snapshot (picker without id)", Usage: "[id|#]", Complete: "snapshot", Run: passthrough("restore")},
			{Name: "rm", Aliases: []string{"remove", "delete"}, Summary: "Delete snapshots (picker without id)", Usage: "[id|#...]", Complete: "snapshot", Run: passthrough("rm")},
			{Name: "prune", Summary: "Keep only the newest N", Flags: []Flag{{Long: "keep", Short: "k", Arg: "N", Help: "how many to keep (default 5)"}},
				Run: func(c *Ctx, args []string) error {
					a := []string{"prune"}
					if v := c.Str("keep"); v != "" {
						a = append(a, "--keep", v)
					}
					if c.Yes {
						a = append(a, "-y")
					}
					return runSnapshot(c, a...)
				}},
			{Name: "path", Summary: "Print the snapshot directory", Run: func(c *Ctx, args []string) error { fmt.Fprintln(c.Out, c.P.Backup); return nil }},
		},
	}
}

// runSnapshot runs the zsh snapshot addon attached to the terminal (keeps its prompts and pickers).
func runSnapshot(c *Ctx, args ...string) error {
	script := c.P.SnapshotScript()
	if _, err := os.Stat(script); err != nil {
		return fmt.Errorf("snapshot addon not found (%s) — is Modern Shell installed? run ./install.sh", c.P.Tilde(script))
	}
	cmd := exec.Command("zsh", append([]string{script}, args...)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = append(os.Environ(), "MSH_HOME="+c.P.Home)
	if !ui.Color {
		cmd.Env = append(cmd.Env, "NO_COLOR=1")
	}
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("snapshot %s failed", args[0])
	}
	return nil
}

// ── doctor / paths / update ───────────────────────────────────────────────

type check struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Level  string `json:"level"` // required | optional | info
	Detail string `json:"detail"`
}

func doctor(c *Ctx, args []string) error {
	var checks []check
	add := func(name, level string, ok bool, detail string) {
		checks = append(checks, check{name, ok, level, detail})
	}
	for _, b := range []string{"zsh", "git", "fzf", "zoxide"} {
		p, err := exec.LookPath(b)
		add(b, "required", err == nil, orDash(p))
	}
	for _, b := range []string{"eza", "bat", "fd", "rg", "highlight", "tmux", "nano", "thefuck", "tldr", "delta"} {
		p, err := exec.LookPath(b)
		add(b, "optional", err == nil, orDash(p))
	}
	_, err := os.Stat(filepath.Join(c.P.Home, "zshrc"))
	add("framework", "required", err == nil, c.P.Tilde(c.P.Home)+" v"+orDash(c.P.Version()))
	rc, _ := os.ReadFile(filepath.Join(c.P.HomeDir, ".zshrc"))
	add("~/.zshrc stub", "required", strings.Contains(string(rc), "Modern Shell loader stub"), "sources the msh loader")
	fi, err := os.Stat(c.P.SecretsFile())
	add("secrets.zsh mode", "required", err != nil || fi.Mode().Perm() == 0o600, func() string {
		if err != nil {
			return "no secrets file yet"
		}
		return fi.Mode().Perm().String()
	}())
	snaps, _ := store.ListSnapshots(c.P)
	add("snapshots", "info", len(snaps) > 0, fmt.Sprintf("%d in %s", len(snaps), c.P.Tilde(c.P.Backup)))
	addons, err := store.LoadAddons(c.P)
	enabled := 0
	missingDeps := []string{}
	for _, a := range addons {
		if a.Enabled {
			enabled++
			for _, d := range a.DepStatus() {
				if !d.Installed && !d.Optional {
					missingDeps = append(missingDeps, a.Name+"→"+d.Name)
				}
			}
		}
	}
	add("addons", "required", err == nil && len(addons) > 0, fmt.Sprintf("%d enabled / %d total", enabled, len(addons)))
	add("addon deps", "optional", len(missingDeps) == 0, orDash(strings.Join(missingDeps, ", ")))
	if shell := os.Getenv("SHELL"); shell != "" {
		add("login shell", "optional", strings.HasSuffix(shell, "/zsh"), shell)
	}

	if c.JSON {
		return c.PrintJSON(checks)
	}
	fmt.Fprintln(c.Out, ui.Bold(ui.Blue("msh doctor")))
	bad := 0
	for _, ch := range checks {
		mark := ui.Green("✔")
		if !ch.OK {
			switch ch.Level {
			case "required":
				mark, bad = ui.Red("✘"), bad+1
			default:
				mark = ui.Yellow("·")
			}
		}
		fmt.Fprintf(c.Out, "  %s %-18s %s\n", mark, ch.Name, ui.GrayText(ch.Detail))
	}
	if bad > 0 {
		return fmt.Errorf("%d required check(s) failed — run ./install.sh (or msh update)", bad)
	}
	ui.Ok("all required checks passed")
	return nil
}

func paths(c *Ctx, args []string) error {
	m := map[string]string{
		"home": c.P.Home, "user": c.P.User, "cache": c.P.Cache, "backup": c.P.Backup, "source": c.P.Source,
		"aliases": c.P.AliasesFile(), "env": c.P.EnvFile(), "secrets": c.P.SecretsFile(),
		"functions": c.P.FunctionsDir(), "addons": c.P.AddonsDir(), "user_addons": c.P.UserAddonsDir(),
		"addon_state": c.P.AddonState(), "config": c.P.ConfFile(), "local": c.P.LocalFile(),
	}
	if c.JSON {
		return c.PrintJSON(m)
	}
	t := ui.Table{Headers: []string{"WHAT", "PATH"}, MaxCol: 100}
	for _, k := range sortedKeys(m) {
		t.Rows = append(t.Rows, []string{ui.Yellow(k), c.P.Tilde(orDash(m[k]))})
	}
	t.Render(c.Out)
	return nil
}

func update(c *Ctx, args []string) error {
	src := c.P.Source
	if src == "" {
		return fmt.Errorf("unknown install source — run install.sh from your Modern Shell checkout")
	}
	script := filepath.Join(src, "install.sh")
	if _, err := os.Stat(script); err != nil {
		return fmt.Errorf("installer not found at %s", script)
	}
	a := []string{script}
	if c.Yes {
		a = append(a, "--yes")
	}
	if c.Bool("dry-run") {
		a = append(a, "--dry-run")
	}
	cmd := exec.Command("bash", a...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// ── helpers ───────────────────────────────────────────────────────────────

func openEditor(path string) error {
	ed := os.Getenv("VISUAL")
	if ed == "" {
		ed = os.Getenv("EDITOR")
	}
	if ed == "" {
		ed = "nano"
	}
	parts := strings.Fields(ed)
	cmd := exec.Command(parts[0], append(parts[1:], path)...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

func readAll(f *os.File) (string, error) {
	var b strings.Builder
	buf := make([]byte, 4096)
	for {
		n, err := f.Read(buf)
		b.Write(buf[:n])
		if err != nil {
			break
		}
	}
	return strings.TrimRight(b.String(), "\n"), nil
}

func atoi(s string) int {
	n := 0
	for _, r := range s {
		if r < '0' || r > '9' {
			return 0
		}
		n = n*10 + int(r-'0')
	}
	return n
}

func expandHome(p store.Paths, s string) string {
	if strings.HasPrefix(s, "~/") {
		return filepath.Join(p.HomeDir, s[2:])
	}
	if abs, err := filepath.Abs(s); err == nil {
		return abs
	}
	return s
}
