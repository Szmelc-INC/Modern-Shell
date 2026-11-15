#!/usr/bin/env bash
# test-pkgbuild.sh — build the Arch package from the working tree, the way SAUR does
# (makepkg inside packaging/arch), and list what it installs. Build files and the
# package land in a temp dir; nothing is installed on the system.
# Set GOPROXY=off to build offline from the local module cache.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
ver=$(cat "$repo/shell/VERSION")
pkgver=$(sed -n 's/^pkgver=//p' "$repo/packaging/arch/PKGBUILD")
[[ $pkgver == "$ver" ]] || { echo "PKGBUILD pkgver=$pkgver != shell/VERSION=$ver" >&2; exit 1; }

work=${1:-$(mktemp -d)}
mkdir -p "$work"
cd "$repo/packaging/arch"
BUILDDIR="$work/build" PKGDEST="$work" SRCDEST="$work/src" \
  makepkg -f --noconfirm --nodeps >"$work/makepkg.log" 2>&1 || { tail -30 "$work/makepkg.log"; exit 1; }
[[ $(ls -A | wc -l) == 2 ]] ||{ echo "makepkg left files in packaging/arch: $(ls -A)" >&2; exit 1; }
pkg=$(ls "$work"/modern-shell-"$ver"-*.pkg.tar.*)
echo "built: $pkg"
tar -tf "$pkg" | grep -v '/$' | grep -v '^\.' | grep -E 'bin/|site-functions|completions|vendor_completions|licenses|doc/|share/modern-shell/(install|uninstall)\.sh' | sort
echo "files: $(tar -tf "$pkg" | grep -vc '/$')"
