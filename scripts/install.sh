#!/usr/bin/env bash
# Build Shortcut Divan from source and install it into ~/Applications.
# Needs Xcode and XcodeGen (brew install xcodegen). No Apple Developer account:
# the app is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project ShortcutDivan.xcodeproj -scheme ShortcutDivan -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build -quiet build

APP=~/Applications/"Shortcut Divan.app"
pkill -x "Shortcut Divan" 2>/dev/null || true
pkill -x DivanWidget 2>/dev/null || true # a running widget would keep the old code
mkdir -p ~/Applications
rm -rf "$APP"
cp -R "build/Build/Products/Release/Shortcut Divan.app" "$APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
pluginkit -a "$APP/Contents/PlugIns/DivanWidget.appex"
open -g "$APP" --args --reload
echo "installed $APP. Add the widget: right-click the desktop › Edit Widgets › Shortcut Divan"
