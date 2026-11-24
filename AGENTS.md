# Tuck

Tiny macOS menu bar icon hider (public, MIT, github.com/JoshD94/tuck). Personal project:
use `~/.local/bin/personal gh` / git.

## Layout
- `Sources/main.swift` — the whole app (AppKit, no Xcode project).
- `Info.plist`, `Assets/AppIcon.icns` (regenerate: `swift scripts/make-icon.swift Assets` + iconutil).
- `scripts/build [--install]` — universal ad-hoc-signed build into `build/`.
- `scripts/release X.Y.Z` — bump version, build, zip, tag, GitHub release (`Tuck.zip`). Here run it as `GIT="$HOME/.local/bin/personal git" GH="$HOME/.local/bin/personal gh" scripts/release X.Y.Z`.
- `install.sh` — the README one-liner; fetches `releases/latest/download/Tuck.zip`.
- `docs/demo.{mp4,gif}` — README demo, recorded with `screencapture -v` + `open -g tuck://toggle`.

## Landmines
- macOS 27 drops a status item wider than the free space instead of pushing icons off-screen
  (the classic 10,000-pt divider trick does nothing). Tuck sizes the divider to the gap
  between the frontmost app's menus (Accessibility) and the dot; keep that logic.
- The divider must sit directly left of the dot; `makeDivider()` re-creates it there.
- Not notarized: no Developer ID cert (only the Account Holder can create one). Every rebuild
  changes the ad-hoc signature, so Accessibility must be re-granted.
- Verify: `scripts/build --install`, then `open -g tuck://show|hide` and screenshot the menu bar.
