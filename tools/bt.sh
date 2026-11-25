#!/bin/bash
# Runs blueutil through the BlueUtil app bundle and prints its output.
# Usage: tools/bt.sh <blueutil arguments>
cd "$(dirname "$0")/.."
out=$(mktemp "${TMPDIR:-/tmp}/bt.XXXXXX")
open -W -n --stdout "$out" --stderr "$out" work/BlueUtil.app --args "$@"
cat "$out"; rm -f "$out"
