#!/bin/bash
# Checks a G8 Plus Bluetooth image (structure and every CRC) and then flashes
# it over Bluetooth LE. The controller must be in Android mode (yellow light).
# Usage: tools/flash.sh <ota.bin>     or     tools/flash.sh --dry-run
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d work/G8Flash.app ] || tools/build-bt-app.sh G8Flash tools/g8-flash.swift
if [ "${1:-}" = "--dry-run" ]; then exec tools/run-app.sh G8Flash --dry-run; fi
img=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
python3 -I third_party/controller-mod-tool/g8fw.py verify "$img"
[ "$(stat -f %z "$img")" = 393908 ] || { echo "unexpected image size; refusing"; exit 1; }
tools/run-app.sh G8Flash "$img"
