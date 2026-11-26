#!/bin/bash
# Runs a tool app from work/ in the foreground and prints its output.
# `open -W` does not pass on the app's exit status, so this exits 1 when the app printed a line starting with
# "FAILED".
# Usage: tools/run-app.sh <AppName> [arguments]
cd "$(dirname "$0")/.."
name=$1; shift
out=$(mktemp "${TMPDIR:-/tmp}/$name.XXXXXX")
open -W -n --stdout "$out" --stderr "$out" "work/$name.app" --args "$@" 2>/dev/null
cat "$out"
status=0; grep -q '^FAILED' "$out" && status=1
rm -f "$out"
exit $status
