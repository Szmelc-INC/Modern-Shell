package tui

import (
	"github.com/charmbracelet/lipgloss"

	"github.com/Szmelc-INC/Modern-Shell/internal/ui"
)

var (
	cAccent    = lipgloss.Color(ui.Accent)
	cAccentAlt = lipgloss.Color(ui.AccentAlt)
	cBorder    = lipgloss.Color(ui.Border)
	cGray      = lipgloss.Color(ui.Gray)
	cFg        = lipgloss.Color(ui.Fg)
	cBgAlt     = lipgloss.Color(ui.BgAlt)
	cAlert     = lipgloss.Color(ui.Alert)
	cSuccess   = lipgloss.Color(ui.Success)
	cWarning   = lipgloss.Color(ui.Warning)

	sLogo      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color(ui.Bg)).Background(cAccent).Padding(0, 1)
	sVersion   = lipgloss.NewStyle().Foreground(cGray)
	sTab       = lipgloss.NewStyle().Foreground(cGray).Padding(0, 1)
	sTabActive = lipgloss.NewStyle().Bold(true).Foreground(cAccentAlt).Background(cBgAlt).Padding(0, 1).Underline(true)
	sTabCount  = lipgloss.NewStyle().Foreground(cBorder)

	sPane       = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cBorder)
	sPaneActive = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cAccent)
	sPaneTitle  = lipgloss.NewStyle().Bold(true).Foreground(cAccent)

	sRowSel   = lipgloss.NewStyle().Background(cBgAlt).Foreground(lipgloss.Color("#ffffff")).Bold(true)
	sRowName  = lipgloss.NewStyle().Foreground(cFg)
	sRowValue = lipgloss.NewStyle().Foreground(cAccentAlt)
	sRowDesc  = lipgloss.NewStyle().Foreground(cGray)
	sOn       = lipgloss.NewStyle().Foreground(cSuccess)
	sOff      = lipgloss.NewStyle().Foreground(cGray)
	sRO       = lipgloss.NewStyle().Foreground(cWarning)
	sBar      = lipgloss.NewStyle().Foreground(cAccent)

	sFooter   = lipgloss.NewStyle().Foreground(cGray)
	sKey      = lipgloss.NewStyle().Foreground(cAccentAlt).Bold(true)
	sStatusOK = lipgloss.NewStyle().Foreground(cSuccess)
	sStatusEr = lipgloss.NewStyle().Foreground(cAlert).Bold(true)
	sFilter   = lipgloss.NewStyle().Foreground(cWarning)

	sModal      = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cAccent).Padding(1, 2)
	sModalWarn  = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cAlert).Padding(1, 2)
	sModalTitle = lipgloss.NewStyle().Bold(true).Foreground(cAccent)
	sLabel      = lipgloss.NewStyle().Foreground(cGray)
	sLabelFocus = lipgloss.NewStyle().Foreground(cAccentAlt).Bold(true)
	sErr        = lipgloss.NewStyle().Foreground(cAlert)
	sHint       = lipgloss.NewStyle().Foreground(cGray).Italic(true)
)
