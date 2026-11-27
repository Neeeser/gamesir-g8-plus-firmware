#!/bin/zsh
# Builds G8 Companion. Usage:
#   app/scripts/build.sh mac       build the Mac app into app/build/
#   app/scripts/build.sh phone     build for the iPhone in DEVICE_UDID and install it (does not launch it)
#   app/scripts/build.sh sim       build for the iPhone simulator
#   app/scripts/build.sh test      run the unit tests on the Mac
# TEAM_ID, BUNDLE_PREFIX and DEVICE_UDID come from the environment or from config.local.sh at the repo root
# (copy config.example.sh).
set -euo pipefail
app_dir=${0:A:h:h}
repo=${app_dir:h}
[[ -f $repo/config.local.sh ]] && source $repo/config.local.sh
: ${TEAM_ID:?set TEAM_ID in config.local.sh}
: ${BUNDLE_PREFIX:?set BUNDLE_PREFIX in config.local.sh}
export TEAM_ID BUNDLE_PREFIX

cd $app_dir
xcodegen generate --quiet
derived=$app_dir/build/derived
log=$app_dir/build/xcodebuild-${1:-mac}.log
mkdir -p $app_dir/build
run() {
  if ! xcodebuild -project G8Companion.xcodeproj -scheme G8Companion -derivedDataPath $derived "$@" >$log 2>&1; then
    grep -E "error:|failed" $log | head -30
    echo "Build failed. Full log: $log"
    exit 1
  fi
}

case ${1:-mac} in
  mac)
    run -destination 'platform=macOS' build
    echo "Built $derived/Build/Products/Debug/G8 Companion.app"
    ;;
  sim)
    run -destination 'generic/platform=iOS Simulator' build
    echo "Built $derived/Build/Products/Debug-iphonesimulator/G8 Companion.app"
    ;;
  phone)
    : ${DEVICE_UDID:?set DEVICE_UDID in config.local.sh}
    run -destination "id=$DEVICE_UDID" -allowProvisioningUpdates build
    app="$derived/Build/Products/Debug-iphoneos/G8 Companion.app"
    xcrun devicectl device install app --device $DEVICE_UDID "$app" | tail -3
    echo "Installed. Open G8 Companion on the phone."
    ;;
  test)
    run -destination 'platform=macOS' test
    grep -E "Executed [0-9]+ tests" $log | tail -1
    ;;
  *) echo "usage: $0 mac|sim|phone|test"; exit 64 ;;
esac
