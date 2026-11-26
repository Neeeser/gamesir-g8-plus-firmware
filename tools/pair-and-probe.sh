#!/bin/bash
# Waits for a controller in Bluetooth pairing mode (fast blink) whose name contains the given text, pairs it
# with tools/pair-hold.swift, which leaves the link up after pairing, then saves a controller-probe run.
# It keeps this Mac's existing pairing for the address unless --fresh is given.
# Usage: tools/pair-and-probe.sh <name-substring> <capture-tag> [timeout-seconds] [--fresh]
set -u
cd "$(dirname "$0")/.."
fresh=""; pos=()
for a in "$@"; do [ "$a" = "--fresh" ] && fresh="--fresh" || pos+=("$a"); done
[ ${#pos[@]} -ge 2 ] || { echo "usage: tools/pair-and-probe.sh <name-substring> <capture-tag> [timeout-seconds] [--fresh]"; exit 64; }
want=${pos[0]}; tag=${pos[1]}; timeout=${pos[2]:-120}; start=$(date +%s)
bin=work/PairHold.app/Contents/MacOS/PairHold
if [ ! -x "$bin" ] || [ tools/pair-hold.swift -nt "$bin" ]; then tools/build-bt-app.sh PairHold tools/pair-hold.swift; fi
line=""
while (( $(date +%s) - start < timeout )); do
  line=$(tools/bt.sh --inquiry 6 2>/dev/null | grep -F "$want" | head -1)
  [ -n "$line" ] && break
done
[ -z "$line" ] && { echo "FAILED: no device named like \"$want\" found in pairing mode"; exit 1; }
addr=$(sed -E 's/^address: ([0-9a-f-]+).*/\1/' <<<"$line")
echo "found: $line"
tools/run-app.sh PairHold "$addr" 15 $fresh || exit 1
swift tools/controller-probe.swift 8 > "captures/$tag-probe.txt" 2>&1
grep -A3 'Raw HID' "captures/$tag-probe.txt"
