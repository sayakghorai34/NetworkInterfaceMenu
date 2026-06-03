#!/bin/zsh

set -e

APP_NAME="NetworkInterfaceMenu"
BUNDLE_ID="${BUNDLE_ID:-com.opensource.NetworkInterfaceMenu}"
BUILD_DIR="$PWD/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BIN_PATH="$BIN_DIR/$APP_NAME"
ICON_PATH="$PWD/NetworkInterfaceMenu.icns"
PLIST_PATH="$APP_DIR/Contents/Info.plist"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"

swiftc main.swift \
  -framework Cocoa \
  -framework Security \
  -framework SystemConfiguration \
  -o "$BIN_PATH"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RES_DIR/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string NetworkInterfaceMenu.icns" "$PLIST_PATH"
fi

killall "$APP_NAME" 2>/dev/null || true
open "$APP_DIR"
