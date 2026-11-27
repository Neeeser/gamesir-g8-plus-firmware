# Machine and account settings for app/scripts/build.sh.
# Copy to config.local.sh (ignored by Git) and fill it in.

# Apple developer team ID (10 characters): security find-identity -v -p codesigning
TEAM_ID=""

# Reverse-DNS prefix for the app's bundle ID, for example com.yourname
BUNDLE_PREFIX=""

# The iPhone to install on: xcrun devicectl list devices
DEVICE_UDID=""
