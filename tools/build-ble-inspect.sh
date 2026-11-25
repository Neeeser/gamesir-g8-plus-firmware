#!/bin/bash
# macOS only grants Bluetooth to an app bundle that declares a usage string,
# so the inspector is built as a tiny app in work/ (ignored by Git).
set -euo pipefail
cd "$(dirname "$0")/.."
app=work/BLEInspect.app
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.controller-research.ble-inspect</string>
  <key>CFBundleName</key><string>BLEInspect</string>
  <key>CFBundleExecutable</key><string>BLEInspect</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Reads a game controller's Bluetooth device information.</string>
</dict></plist>
PLIST
swiftc -O tools/ble-inspect.swift -o "$app/Contents/MacOS/BLEInspect"
codesign --force -s - "$app"
echo "built $app"
