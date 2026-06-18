#!/usr/bin/env bash
# Release build: universal QuickRun.app, signed with Developer ID + hardened
# runtime, notarized by Apple, and stapled into a distributable
# dist/QuickRun.dmg (with an Applications drag-install shortcut), then installs
# it into /Applications and launches it (quitting any running copy first).
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

# Build a compressed DMG containing the app and an /Applications shortcut so
# users can drag-install. Expects $APP_PATH to already be signed.
build_dmg() {
    local out="$1"
    local staging
    staging="$(mktemp -d)"
    cp -R "$APP_PATH" "$staging/"
    ln -s /Applications "$staging/Applications"   # drag-install shortcut
    rm -f "$out"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$out" >/dev/null
    rm -rf "$staging"
    echo "Built $out"
}

# Submit a file (zip/dmg) to the notary service and wait for the verdict.
notarize() {
    local file="$1"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
        xcrun notarytool submit "$file" \
            --apple-id "$NOTARY_APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    else
        echo "ERROR: no notary credentials." >&2
        echo "Set NOTARY_PROFILE (see header) or NOTARY_APPLE_ID + NOTARY_PASSWORD." >&2
        exit 1
    fi
}

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

echo "Signing app with Developer ID (hardened runtime)..."
codesign --force --options runtime --timestamp --sign "$DEV_ID" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

DMG="$DIST/$APP_NAME.dmg"
build_dmg "$DMG"

if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "SKIP_NOTARIZE=1 — signed only. App: $APP_PATH, dmg: $DMG"
    install_and_launch
    exit 0
fi

echo "Signing DMG..."
codesign --force --sign "$DEV_ID" "$DMG"

echo "Submitting DMG to notary service (waits for result)..."
notarize "$DMG"

echo "Stapling ticket to the DMG and the app..."
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP_PATH"   # app's cdhash was notarized inside the DMG

echo "Verifying Gatekeeper acceptance..."
xcrun stapler validate "$DMG"
spctl --assess --type execute -vvv "$APP_PATH"

echo "Done. Distributable: $DMG"

install_and_launch
