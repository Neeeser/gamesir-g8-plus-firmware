#!/bin/bash
# macOS grants Bluetooth only to an app bundle that declares a usage string,
# so Bluetooth tools are built as tiny apps in work/ (ignored by Git).
# Usage: tools/build-bt-app.sh <AppName> <source.swift>
set -euo pipefail
cd "$(dirname "$0")/.."
name=$1; src=$2; app=work/$name.app
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.controller-research.$(echo "$name" | tr 'A-Z' 'a-z')</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Talks to a game controller over Bluetooth.</string>
</dict></plist>
PLIST
swiftc -O "$src" -o "$app/Contents/MacOS/$name"
codesign --force -s - "$app" 2>/dev/null
echo "built $app"
