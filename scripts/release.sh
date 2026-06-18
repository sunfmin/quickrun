#!/usr/bin/env bash
# Release build: universal QuickRun.app, signed with Developer ID + hardened
# runtime, notarized by Apple, and stapled. Produces a distributable
# dist/QuickRun.zip, then installs it into /Applications and launches it
# (quitting any running copy first).
#
# One-time notary credential setup (stores a keychain profile):
#   xcrun notarytool store-credentials QuickRunNotary \
#     --apple-id "you@example.com" --team-id HL27PWAKDF \
#     --password "<app-specific-password>"   # appleid.apple.com -> App-Specific Passwords
#
# Then:
#   NOTARY_PROFILE=QuickRunNotary ./scripts/release.sh
#
# Overridable via env:
#   DEV_ID          signing identity (default: the Developer ID below)
#   TEAM_ID         Apple team id (default: HL27PWAKDF)
#   NOTARY_PROFILE  notarytool keychain profile, OR
#   NOTARY_APPLE_ID + NOTARY_PASSWORD  Apple ID + app-specific password
#   SKIP_NOTARIZE=1 sign only, skip notarization/stapling (smoke test)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

DEV_ID="${DEV_ID:-Developer ID Application: FENGMIN SUN (HL27PWAKDF)}"
TEAM_ID="${TEAM_ID:-HL27PWAKDF}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

# Quit any running copy, replace the one in /Applications, and launch it.
install_and_launch() {
    local dest="/Applications/$APP_NAME.app"
    echo "Quitting running $APP_NAME (if any)..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1   # let it exit so we can overwrite the bundle
    echo "Installing to $dest..."
    rm -rf "$dest"
    ditto "$APP_PATH" "$dest"
    echo "Launching $dest..."
    open "$dest"
}

assemble_app release arm64 x86_64

echo "Signing with Developer ID (hardened runtime)..."
codesign --force --options runtime --timestamp --sign "$DEV_ID" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

ZIP="$DIST/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "SKIP_NOTARIZE=1 — signed only. Bundle: $APP_PATH, zip: $ZIP"
    install_and_launch
    exit 0
fi

echo "Submitting to notary service (waits for result)..."
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ZIP" \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD" --wait
else
    echo "ERROR: no notary credentials." >&2
    echo "Set NOTARY_PROFILE (see header) or NOTARY_APPLE_ID + NOTARY_PASSWORD." >&2
    exit 1
fi

echo "Stapling ticket..."
xcrun stapler staple "$APP_PATH"

# Re-zip the stapled bundle for distribution.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

echo "Verifying Gatekeeper acceptance..."
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute -vvv "$APP_PATH"

echo "Done. Distributable: $ZIP"

install_and_launch
