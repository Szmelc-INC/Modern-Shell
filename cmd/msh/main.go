// Command msh is the Modern Shell manager: a CLI and an interactive TUI for
// zsh addons, aliases, functions, environment, secrets, zoxide directories and
// snapshots.
package main

import (
	"os"

	"github.com/sernik77/modern-shell/internal/cli"
)

// version is set at build time: -ldflags "-X main.version=…".
var version = "dev"

func main() {
	os.Exit(cli.Execute(cli.Root(version), os.Args[1:]))
}
