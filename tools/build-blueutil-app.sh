#!/bin/bash
# Wraps Homebrew's blueutil in an app bundle with a Bluetooth usage string,
# because macOS denies Bluetooth to command-line tools started from an
# agent session. Run the result with tools/bt.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
app=work/BlueUtil.app
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.controller-research.blueutil</string>
  <key>CFBundleName</key><string>BlueUtil</string>
  <key>CFBundleExecutable</key><string>blueutil</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Pairs and connects game controllers for testing.</string>
</dict></plist>
PLIST
cp "$(realpath "$(command -v blueutil)")" "$app/Contents/MacOS/blueutil"
codesign --force -s - "$app"
echo "built $app"
