#!/bin/bash
# Installs the latest Tuck release into /Applications and starts it.
# curl -fsSL https://raw.githubusercontent.com/JoshD94/tuck/main/install.sh | bash
set -euo pipefail
url="https://github.com/JoshD94/tuck/releases/latest/download/Tuck.zip"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Tuck…"
curl -fsSL "$url" -o "$tmp/Tuck.zip"
ditto -x -k "$tmp/Tuck.zip" "$tmp"
pkill -x Tuck 2>/dev/null || true
rm -rf /Applications/Tuck.app
mv "$tmp/Tuck.app" /Applications/
xattr -dr com.apple.quarantine /Applications/Tuck.app 2>/dev/null || true
open /Applications/Tuck.app
echo "Tuck is in your menu bar (the dot). Allow it under System Settings → Privacy & Security → Accessibility."
