# Shared bundle assembly for QuickRun build scripts. Sourced, not run.
# Single home for the .app layout + Info.plist so dev and release can't drift.

APP_NAME=QuickRun
BUNDLE_ID=jp.theplant.quickrun
DIST=dist
SHORT_VERSION="${SHORT_VERSION:-0.5.3}"
BUILD_VERSION="${BUILD_VERSION:-8}"

# assemble_app <config> [arch...]
# Builds the binary and assembles an UNSIGNED dist/QuickRun.app.
# Sets APP_PATH to the bundle path. Signing is left to the caller.
assemble_app() {
    local config="$1"; shift
    local archflags=""
    local a
    for a in "$@"; do archflags="$archflags --arch $a"; done

    local app="$DIST/$APP_NAME.app"

    echo "Building ($config${archflags:+ ${archflags}})..."
    swift build -c "$config" --product "$APP_NAME" $archflags
    local bin_dir
    bin_dir="$(swift build -c "$config" --product "$APP_NAME" $archflags --show-bin-path)"

    echo "Assembling $app..."
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin_dir/$APP_NAME" "$app/Contents/MacOS/$APP_NAME"

    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

    printf 'APPL????' > "$app/Contents/PkgInfo"

    if [ -f Resources/AppIcon.icns ]; then
        cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    fi

    APP_PATH="$app"
}
