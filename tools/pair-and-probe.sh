#!/bin/bash
# Waits for a controller in Bluetooth pairing mode whose name contains the
# given text, pairs and connects it to this Mac (replacing an older pairing
# with the same address), then saves a controller-probe run.
# Usage: tools/pair-and-probe.sh <name-substring> <capture-tag> [timeout-seconds]
set -u
cd "$(dirname "$0")/.."
want=$1; tag=$2; timeout=${3:-240}; start=$(date +%s)
while (( $(date +%s) - start < timeout )); do
  line=$(tools/bt.sh --inquiry 6 2>/dev/null | grep -F "$want" | head -1)
  [ -n "$line" ] && break
done
[ -z "${line:-}" ] && { echo "no device named like \"$want\" found in pairing mode"; exit 1; }
addr=$(sed -E 's/^address: ([0-9a-f-]+).*/\1/' <<<"$line")
echo "found: $line"
if tools/bt.sh --paired 2>/dev/null | grep -q "address: $addr"; then
  echo "removing older pairing for $addr"; tools/bt.sh --unpair "$addr"
fi
tools/bt.sh --pair "$addr"; tools/bt.sh --connect "$addr"; sleep 4
tools/bt.sh --info "$addr" | grep -v kevent
swift tools/controller-probe.swift 8 > "captures/$tag-probe.txt" 2>&1
grep -A3 'Raw HID' "captures/$tag-probe.txt"
