#!/bin/bash
# Checks a G8 Plus Bluetooth image (structure and every CRC) and then flashes it over Bluetooth LE.
# The controller must be in Android mode (yellow light), or in recovery mode with --recovery.
# Exits 1 if the check or the flash fails.
# Usage: tools/flash.sh [--recovery] <ota.bin>     or     tools/flash.sh [--recovery] --dry-run
set -euo pipefail
cd "$(dirname "$0")/.."
bin=work/G8Flash.app/Contents/MacOS/G8Flash
# Rebuild when the source changed, so a fix to the flasher is never skipped.
if [ ! -x "$bin" ] || [ tools/g8-flash.swift -nt "$bin" ]; then tools/build-bt-app.sh G8Flash tools/g8-flash.swift; fi
rec=""; [ "${1:-}" = "--recovery" ] && { rec="--recovery"; shift; }
[ $# -ge 1 ] || { echo "usage: tools/flash.sh [--recovery] <ota.bin> | --dry-run"; exit 64; }
if [ "$1" = "--dry-run" ]; then exec tools/run-app.sh G8Flash $rec --dry-run; fi
img=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
python3 -I third_party/controller-mod-tool/g8fw.py verify "$img"
[ "$(stat -f %z "$img")" = 393908 ] || { echo "unexpected image size; refusing"; exit 1; }
tools/run-app.sh G8Flash $rec "$img"
