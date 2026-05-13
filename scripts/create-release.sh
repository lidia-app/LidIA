#!/bin/bash
# Create a distributable release of LidIA (.zip + .dmg)
# Signs with Developer ID and notarizes with Apple.
#
# Usage:
#   ./scripts/create-release.sh              # Build + create artifacts (ad-hoc sign)
#   ./scripts/create-release.sh v0.1.0       # Same, with version tag
#   ./scripts/create-release.sh v0.1.0 sign  # Build + sign with Developer ID + notarize
#
# Prerequisites for signed releases:
#   1. "Developer ID Application" certificate in Keychain
#   2. App-specific password stored: xcrun notarytool store-credentials "LidIA-notary"
#      (prompts for Apple ID, Team ID, and app-specific password)
#
# Output: dist/LidIA-<version>.zip and dist/LidIA-<version>.dmg

set -euo pipefail

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "dev")}"
SIGN_MODE="${2:-adhoc}"  # "sign" for Developer ID + notarization, anything else for ad-hoc
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="LidIA"
ENTITLEMENTS="${ROOT_DIR}/Sources/LidIA/Resources/LidIA.entitlements"

echo "==> Building ${APP_NAME} release ${VERSION}..."
echo ""

# 1. Build in release mode
echo "==> Step 1/7: Building release binary..."
cd "${ROOT_DIR}"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

# 2. Create .app bundle
echo "==> Step 2/7: Packaging .app bundle..."
RELEASE_APP="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${RELEASE_APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

rm -rf "${RELEASE_APP}"
mkdir -p "${MACOS}" "${RESOURCES}" "${FRAMEWORKS}" "${DIST_DIR}"

# Copy release executable
cp "${BIN_PATH}/LidIA" "${MACOS}/LidIA"

# Copy Info.plist and set version
cp "${ROOT_DIR}/Sources/LidIA/Resources/Info.plist" "${CONTENTS}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS}/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${CONTENTS}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${CONTENTS}/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION}" "${CONTENTS}/Info.plist"

# Compile asset catalog
XCASSETS_SRC="${ROOT_DIR}/Sources/LidIA/Resources/Assets.xcassets"
if [ -d "${XCASSETS_SRC}" ]; then
    echo "    Compiling asset catalog..."
    xcrun actool "${XCASSETS_SRC}" \
        --compile "${RESOURCES}" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /dev/null \
        2>/dev/null || true
fi

# Copy hand-crafted .icns
ICNS_SRC="${ROOT_DIR}/Sources/LidIA/Resources/AppIcon.icns"
if [ -f "${ICNS_SRC}" ]; then
    cp "${ICNS_SRC}" "${RESOURCES}/AppIcon.icns"
fi

# Copy SPM resource bundle
ASSETS_BUNDLE="${BIN_PATH}/LidIA_LidIA.bundle"
if [ -d "${ASSETS_BUNDLE}" ]; then
    cp -R "${ASSETS_BUNDLE}" "${RESOURCES}/"
fi

# Compile MLX Metal shaders
MLX_METAL_DIR="${ROOT_DIR}/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
MLX_BUNDLE="${RESOURCES}/mlx-swift_Cmlx.bundle"
if [ -d "${MLX_METAL_DIR}" ]; then
    MLX_METALLIB="${MLX_BUNDLE}/default.metallib"
    echo "    Compiling MLX Metal shaders..."
    mkdir -p "${MLX_BUNDLE}"
    AIR_DIR=$(mktemp -d)
    find "${MLX_METAL_DIR}" -name "*.metal" -print0 | while IFS= read -r -d '' f; do
        name=$(basename "$f" .metal)
        xcrun -sdk macosx metal -c -I "${MLX_METAL_DIR}" "$f" -o "${AIR_DIR}/${name}.air" 2>/dev/null
    done
    xcrun -sdk macosx metallib "${AIR_DIR}"/*.air -o "${MLX_METALLIB}" 2>/dev/null
    rm -rf "${AIR_DIR}"
    echo "    MLX metallib: $(du -h "${MLX_METALLIB}" | cut -f1)"
fi

# Embed Sparkle.framework
SPARKLE_FW="${BIN_PATH}/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
    echo "    Embedding Sparkle.framework..."
    cp -R "${SPARKLE_FW}" "${FRAMEWORKS}/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS}/LidIA" 2>/dev/null || true
fi

# Copy LidiaMCP if exists
if [ -f "${BIN_PATH}/LidiaMCP" ]; then
    cp "${BIN_PATH}/LidiaMCP" "${MACOS}/LidiaMCP"
fi

# 3. Code sign
if [ "${SIGN_MODE}" = "sign" ]; then
    echo "==> Step 3/7: Code signing with Developer ID..."

    # Find Developer ID Application identity
    DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "")
    if [ -z "${DEV_ID}" ]; then
        echo "ERROR: No 'Developer ID Application' certificate found in Keychain."
        echo ""
        echo "To create one:"
        echo "  1. Go to https://developer.apple.com/account/resources/certificates"
        echo "  2. Create a 'Developer ID Application' certificate"
        echo "  3. Download and double-click to install in Keychain"
        exit 1
    fi

    echo "    Identity: ${DEV_ID}"

    # Sign embedded frameworks first
    if [ -d "${FRAMEWORKS}" ]; then
        find "${FRAMEWORKS}" -name "*.framework" -exec \
            codesign --force --sign "${DEV_ID}" --options runtime {} \; 2>/dev/null || true
    fi

    # Sign the app with hardened runtime (required for notarization)
    codesign --force --sign "${DEV_ID}" \
        --entitlements "${ENTITLEMENTS}" \
        --options runtime \
        --generate-entitlement-der \
        "${RELEASE_APP}"

    echo "    Signed successfully"
else
    echo "==> Step 3/7: Code signing (ad-hoc — not notarizable)..."
    if [ -d "${FRAMEWORKS}" ]; then
        find "${FRAMEWORKS}" -name "*.framework" -exec codesign --force --sign - {} \; 2>/dev/null || true
    fi
    codesign --force --sign - --entitlements "${ENTITLEMENTS}" "${RELEASE_APP}"
fi

# 4. Create .zip (Sparkle uses zip for updates)
echo "==> Step 4/7: Creating ZIP archive..."
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
cd "${DIST_DIR}"
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP_NAME}.app" "${ZIP_NAME}"
echo "    Created: dist/${ZIP_NAME} ($(du -h "${ZIP_NAME}" | cut -f1))"

# 5. Create .dmg
echo "==> Step 5/7: Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_NAME}"

DMG_STAGE=$(mktemp -d)
cp -R "${APP_NAME}.app" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov -format UDZO \
    "${DMG_NAME}" \
    -quiet

rm -rf "${DMG_STAGE}"
echo "    Created: dist/${DMG_NAME} ($(du -h "${DMG_NAME}" | cut -f1))"

# 6. Notarize (only if signed with Developer ID)
if [ "${SIGN_MODE}" = "sign" ]; then
    echo "==> Step 6/7: Notarizing with Apple..."
    echo "    Submitting DMG for notarization..."

    if xcrun notarytool submit "${DMG_NAME}" \
        --keychain-profile "LidIA-notary" \
        --wait 2>&1; then
        echo "    Notarization succeeded!"

        echo "    Stapling notarization ticket..."
        xcrun stapler staple "${DMG_NAME}"
        echo "    DMG stapled successfully"

        # Also notarize the ZIP
        echo "    Submitting ZIP for notarization..."
        xcrun notarytool submit "${ZIP_NAME}" \
            --keychain-profile "LidIA-notary" \
            --wait 2>&1 || echo "    ZIP notarization failed (non-critical, DMG is primary)"
    else
        echo ""
        echo "    Notarization failed. Common fixes:"
        echo "    1. Store credentials: xcrun notarytool store-credentials 'LidIA-notary'"
        echo "       (prompts for Apple ID, Team ID, app-specific password)"
        echo "    2. Create app-specific password at https://appleid.apple.com"
        echo "    3. Check logs: xcrun notarytool log <submission-id> --keychain-profile 'LidIA-notary'"
    fi
else
    echo "==> Step 6/7: Skipping notarization (ad-hoc build)"
fi

# 7. Cleanup
echo "==> Step 7/7: Cleanup..."
rm -rf "${RELEASE_APP}"

cd "${ROOT_DIR}"
echo ""
echo "==> Release artifacts ready in dist/:"
ls -lh "dist/${ZIP_NAME}" "dist/${DMG_NAME}"
echo ""

if [ "${SIGN_MODE}" = "sign" ]; then
    echo "Next steps:"
    echo "  1. Test: open dist/${DMG_NAME}"
    echo "  2. Tag:  git tag v${VERSION} && git push --tags"
    echo "  3. Release: gh release create v${VERSION} dist/${ZIP_NAME} dist/${DMG_NAME} --title 'LidIA ${VERSION}'"
    echo "  4. Appcast: ./scripts/generate-appcast.sh ${VERSION}"
else
    echo "Next steps (unsigned build — for local testing only):"
    echo "  1. Test: open dist/${DMG_NAME}"
    echo "  2. For distribution, re-run with: $0 ${VERSION} sign"
fi
