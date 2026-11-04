#!/bin/bash
# Builds MyBrowser.app next to this script. Usage: ./build_app.sh [--install]
set -e
cd "$(dirname "$0")"

VERSION=$(tr -d '[:space:]' < VERSION)
UPDATE_REPO=$(tr -d '[:space:]' < UPDATE_REPO)

echo "Building MyBrowser $VERSION (release)..."
swift build -c release

APP="MyBrowser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MyBrowser "$APP/Contents/MacOS/MyBrowser"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MyBrowser</string>
    <key>CFBundleDisplayName</key><string>MyBrowser</string>
    <key>CFBundleExecutable</key><string>MyBrowser</string>
    <key>CFBundleIdentifier</key><string>com.local.MyBrowser</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>MBUpdateRepo</key><string>$UPDATE_REPO</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it without complaint.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($VERSION)"

if [ "$1" = "--install" ]; then
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$APP"
fi
