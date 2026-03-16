#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: build-release.sh <version>}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Building LidIA v${VERSION} (release)..."
cd "$ROOT_DIR"
swift build -c release

echo "==> Packaging .app bundle..."
./run.sh build

echo "==> Updating Info.plist version..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" .build/LidIA.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" .build/LidIA.app/Contents/Info.plist

echo "==> Creating DMG..."
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "LidIA ${VERSION}" \
        --volicon "Sources/LidIA/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "LidIA.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "LidIA.app" \
        "dist/LidIA-${VERSION}.dmg" \
        ".build/LidIA.app"
else
    echo "create-dmg not found, creating simple DMG..."
    hdiutil create -volname "LidIA ${VERSION}" -srcfolder ".build/LidIA.app" -ov -format UDZO "dist/LidIA-${VERSION}.dmg"
fi

echo "==> DMG ready: dist/LidIA-${VERSION}.dmg"
echo ""
echo "Next steps:"
echo "  1. Notarize: xcrun notarytool submit dist/LidIA-${VERSION}.dmg --apple-id <email> --team-id <team> --password <app-password>"
echo "  2. Staple:   xcrun stapler staple dist/LidIA-${VERSION}.dmg"
echo "  3. Release:  gh release create v${VERSION} dist/LidIA-${VERSION}.dmg --title 'LidIA v${VERSION}'"
echo "  4. Update Homebrew cask SHA256 and version"
