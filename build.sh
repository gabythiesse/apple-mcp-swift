#!/bin/zsh
# Release build of one server, installed at the stable path <server>/bin/<Binary> and signed with the fixed "Apple MCP" identity.
# macOS ties permissions to "identifier + certificate", so they survive rebuilds.
# (An ad hoc signature ties the permission to the exact binary contents: every build asked again.)
# The identity lives in the dedicated keychain ~/Library/Keychains/apple-mcp.keychain-db (created by installer.command),
# which codesign can use without any prompt.
# Usage: ./build.sh safari-mcp   |   ./build.sh --sign <binary> [identifier]   |   ./build.sh --all
set -e
ROOT=${0:a:h}
IDENTITY=$(<"$ROOT/.signature/identite.sha1")
KEYCHAIN="$HOME/Library/Keychains/apple-mcp.keychain-db"

sign() {
  security unlock-keychain -p "$(<"$ROOT/.signature/trousseau.motdepasse")" "$KEYCHAIN" 2>/dev/null || true
  if [[ -n $2 ]]; then codesign --force --timestamp=none -s "$IDENTITY" -i "$2" "$1"
  else codesign --force --timestamp=none -s "$IDENTITY" "$1"; fi
}

if [[ $1 == --sign ]]; then sign "$2" "$3"; exit; fi
if [[ $1 == --all ]]; then for d in "$ROOT"/*-mcp "$ROOT"/launcher; do "$0" "${d:t}"; done; exit; fi

dir="$ROOT/${1:?usage: build.sh <name>-mcp}"
cd "$dir"
[[ -x build.sh ]] && exec ./build.sh   # Contacts and the launcher have their own script
binary=$(grep -m1 -oE 'name: "[A-Za-z]+MCP"' Package.swift | cut -d'"' -f2)   # package name = executable name
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build failed"; exit 1 }
mkdir -p bin
install -m 755 .build/release/$binary bin/$binary
sign bin/$binary dev.applemcp.${1}
rm -f bin/*.cstemp(N)
echo "installed and signed: $PWD/bin/$binary"
