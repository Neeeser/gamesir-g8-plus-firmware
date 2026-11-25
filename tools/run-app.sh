#!/bin/bash
# Runs a tool app from work/ in the foreground and prints its output.
# Usage: tools/run-app.sh <AppName> [arguments]
cd "$(dirname "$0")/.."
name=$1; shift
out=$(mktemp "${TMPDIR:-/tmp}/$name.XXXXXX")
open -W -n --stdout "$out" --stderr "$out" "work/$name.app" --args "$@" 2>/dev/null
cat "$out"; rm -f "$out"
