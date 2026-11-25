#!/bin/bash
# Waits for the controller to reappear on USB under a new identity (each
# wired mode uses a different vendor/product ID), then saves its USB
# registry entry, HID report descriptor and a GameController probe.
# Usage: tools/capture-usb-mode.sh <how-many-new-modes> [timeout-seconds]
set -u
cd "$(dirname "$0")/.."
want=${1:-2}; timeout=${2:-900}
seen="$(ls captures/*-ids.txt 2>/dev/null | xargs cat 2>/dev/null)"
got=0; start=$(date +%s)
current_ids() {
  ioreg -p IOUSB -w0 -l | awk -F' = ' '/\+-o /{if (v!="" && p!="") printf "%04x:%04x\n", v, p; v=""; p=""}
    /"idVendor"/{v=$2} /"idProduct"/{p=$2} END{if (v!="" && p!="") printf "%04x:%04x\n", v, p}' | sort -u
}
while (( got < want )) && (( $(date +%s) - start < timeout )); do
  for id in $(current_ids); do
    case "$id" in 05ac:*) continue;; esac
    grep -q "$id" <<<"$seen" && continue
    sleep 3  # let the host finish enumerating interfaces
    name=$(ioreg -p IOUSB -w0 -l | awk -v want="$id" -F' = ' '
      /\+-o /{if (v!="" && p!="" && sprintf("%04x:%04x",v,p)==want) {print n; exit}
              n=$0; sub(/.*\+-o /,"",n); sub(/@.*/,"",n); v=""; p=""}
      /"idVendor"/{v=$2} /"idProduct"/{p=$2}
      END{if (sprintf("%04x:%04x",v,p)==want) print n}')
    tag="mode-${id/:/-}"
    echo "$id $name" > "captures/$tag-ids.txt"
    ioreg -l -w0 -r -n "$name" > "captures/$tag-ioreg.txt"
    grep -o '"ReportDescriptor" = <[0-9a-f]*>' "captures/$tag-ioreg.txt" | sed 's/.*<//;s/>//' > "captures/$tag-report-descriptors.hex"
    swift tools/controller-probe.swift 6 > "captures/$tag-probe.txt" 2>&1
    echo "captured $id ($name)"
    seen="$seen $id"; got=$((got+1))
  done
  sleep 1
done
echo "done: $got new mode(s) captured"
