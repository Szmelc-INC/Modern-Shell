#!/usr/bin/env bash
# test-pkgbuild.sh — build the Arch package from the working tree (offline) and
# list what it installs. Nothing is installed on the system.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
ver=$(cat "$repo/shell/VERSION")
work=${1:-$(mktemp -d)}
mkdir -p "$work"
cp "$repo/packaging/arch/PKGBUILD" "$repo/packaging/arch/modern-shell.install" "$work/"
tar -C "$repo" --exclude=./.git --exclude=./bin --exclude=./dist --exclude=./.claude \
  --transform "s,^\.,modern-shell-$ver," -czf "$work/modern-shell-$ver.tar.gz" .
cd "$work"
GOPROXY=off makepkg -f --noconfirm --nodeps >makepkg.log 2>&1 || { tail -30 makepkg.log; exit 1; }
pkg=$(ls modern-shell-"$ver"-*.pkg.tar.*)
echo "built: $pkg"
tar -tf "$pkg" | grep -v '/$' | grep -v '^\.' | grep -E 'bin/|site-functions|completions|vendor_completions|licenses|doc/|share/modern-shell/(install|uninstall)\.sh' | sort
echo "files: $(tar -tf "$pkg" | grep -vc '/$')"
