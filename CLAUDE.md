# Shortcut Divan

Keyboard shortcuts in a macOS desktop widget, plus a small app to browse, search and edit them.
Persian name «دیوان میان‌بر» (chosen on purpose, keep it). English and Persian, with a full
right-to-left layout in Persian (keycaps still read left to right). See README.md for features.

## Talking to the owner (Saeed Ahmadi, `codingwithsaeed`)

- Reply in Persian, always. Only code, commands and paths stay in English.
- Keep Persian RTL-readable: prefer Persian words; never start or end a sentence, line or list
  item with an English word or path; never put two English terms next to each other; wrap
  unavoidable terms in backticks mid-sentence; put commands in their own code block; start
  table cells and bullets with Persian.
- The owner runs password, sudo and sign-in steps and creates tokens themselves. Never enter
  credentials.

## Branches: git flow

- `main`: released code only. `develop`: integration branch.
- New work goes on `feature/<meaningful-name>` from `develop` (`fix/…` for bug fixes,
  `release/x.y.z` and `hotfix/…` as git flow does). Names say what the change is.
- Never put `claude` (or any tool or agent name) in a branch name, even if the session
  suggests one.
- When the owner approves a feature, merge it into `develop` with `--no-ff`. `develop` goes
  into `main` only for a release, when the owner asks.

## Layout

- `project.yml`: XcodeGen spec; the `.xcodeproj` is generated, not committed. macOS 14+,
  ad-hoc signing (no Apple Developer account), no notarization.
- `App/`: the app (not sandboxed). `ShortcutDivanApp.swift` has the window, sidebar card,
  section cards, editors, settings; `Store.swift` loads, saves and follows a shortcuts file.
  URL scheme `shortcutdivan://section/<title>` opens a section (widget clicks).
- `Widget/`: WidgetKit extension (sandboxed, read-only access to
  `~/Library/Application Support/Shortcut Divan/`). `DivanWidget.swift` (configuration,
  timeline), `Paging.swift` (page and section buttons: widgets can't scroll), `Views.swift`.
- `Shared/`: data model and Rosé Pine colors (`Shortcuts.swift`), keycaps (`Keycaps.swift`).
- `Resources/`: `AppIcon.icon` (Icon Composer), `Localizable.xcstrings`, `InfoPlist.xcstrings`
  (en, fa). Every new user-facing string needs its Persian translation there.
- `scripts/install.sh`: build and install to `~/Applications`, re-register the widget.

## Design rules

- Alignment matters a lot to the owner. Edges line up across the window: the top bar's
  first and last buttons with the cards' edges (also when a scroll bar shows, and in
  right-to-left), the sidebar's first row with the search field, header buttons with the
  keycaps below them. Check every change for this before pushing.
- One look everywhere: the Rosé Pine backdrop, glass cards and round glass buttons; text
  buttons use `TintButtonStyle`, key symbols look like keycaps. New windows and sheets use
  `appLook()`.
- Window layout follows Telegram (the owner's reference): one header row across the window,
  level with the window buttons (`TrafficLights` moves them there); a flat sidebar on the same
  backdrop, parted by one straight line; the search field pinned below the header. No panels
  or cards around the sidebar.
- Latin text uses Inter (`Font.app`, bundled in `Resources/Fonts`); Persian falls back to the
  system font; typed commands in keycaps stay monospaced. Icons use SF Symbols at a readable
  size (`GlassIcon`).

## Data

`~/Library/Application Support/Shortcut Divan/shortcuts.json` (the widget reads it), shape
`{"sections":[{"title","accent","rows":[{"keys","desc"}]}]}`. The owner's app follows
`~/dotfiles/wallpaper/shortcuts.json`; edits are saved back there, in the same hand-editable
format (`Shortcuts.format`), which other dotfiles scripts also read.

## Checking changes

A cloud session can't run the app or see the desktop. The Build workflow compiles every push
to `develop` and `feature/**`; the Release workflow (run by hand) makes a `.dmg` artifact. To
try a branch on the Mac:

```sh
cd ~/dev/workspace/swift/shortcut-divan && git fetch origin && git checkout <branch> && git pull && ./scripts/install.sh
```

Release: `gh release create vX.Y.Z --generate-notes` (attaches the `.dmg`).
