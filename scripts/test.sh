#!/bin/zsh

set -euo pipefail

NO_OPEN=1 ./build.sh

APP="build/NetworkInterfaceMenu.app"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/NetworkInterfaceMenu"

[[ -d "$APP" ]] || { echo "App bundle missing"; exit 1; }
[[ -f "$PLIST" ]] || { echo "Info.plist missing"; exit 1; }
[[ -x "$BIN" ]] || { echo "App binary missing or not executable"; exit 1; }

/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST" | grep -qx "NetworkInterfaceMenu"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$PLIST" | grep -qx "true"
