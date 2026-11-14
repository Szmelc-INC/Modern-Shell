package store

import (
	"regexp"
	"strings"
)

var (
	envNameRe   = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
	aliasNameRe = regexp.MustCompile(`^[A-Za-z0-9_.:+@%^-]+$`)
	funcNameRe  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_.:-]*$`)
	addonNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)
)

// ValidName reports whether name is valid for the given item kind.
func ValidName(kind Kind, name string) bool {
	switch kind {
	case KindEnv, KindSecret:
		return envNameRe.MatchString(name)
	case KindAlias:
		return aliasNameRe.MatchString(name)
	case KindFunction:
		return funcNameRe.MatchString(name)
	case KindAddon:
		return addonNameRe.MatchString(name)
	}
	return false
}

// Quote returns s as a zsh single-quoted word ('it'\''s').
func Quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// Unquote parses a zsh word made of '…', "…", \x and bare segments.
func Unquote(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch c {
		case '\'':
			j := strings.IndexByte(s[i+1:], '\'')
			if j < 0 {
				b.WriteString(s[i+1:])
				return b.String()
			}
			b.WriteString(s[i+1 : i+1+j])
			i += j + 1
		case '"':
			i++
			for ; i < len(s) && s[i] != '"'; i++ {
				if s[i] == '\\' && i+1 < len(s) && strings.ContainsRune("\"\\$`", rune(s[i+1])) {
					i++
				}
				b.WriteByte(s[i])
			}
		case '\\':
			if i+1 < len(s) {
				i++
				b.WriteByte(s[i])
			}
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}

// splitAssign splits `NAME=VALUE…` respecting quotes; the value keeps its quoting.
func splitAssign(s string) (name, raw string, ok bool) {
	i := strings.IndexByte(s, '=')
	if i <= 0 {
		return "", "", false
	}
	return s[:i], s[i+1:], true
}

// cutTrailingComment removes an unquoted trailing `# comment` from a zsh word list.
func cutTrailingComment(s string) string {
	inS, inD := false, false
	for i := 0; i < len(s); i++ {
		switch c := s[i]; {
		case c == '\\' && !inS:
			i++
		case c == '\'' && !inD:
			inS = !inS
		case c == '"' && !inS:
			inD = !inD
		case c == '#' && !inS && !inD && i > 0 && (s[i-1] == ' ' || s[i-1] == '\t'):
			return strings.TrimRight(s[:i], " \t")
		}
	}
	return s
}
