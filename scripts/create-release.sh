#!/bin/bash
# Create a distributable release of LidIA (.zip + .dmg)
#
# Usage:
#   ./scripts/create-release.sh          # Build release + create artifacts
#   ./scripts/create-release.sh v0.1.0   # Same, with version tag
#
# Output: dist/LidIA-<version>.zip and dist/LidIA-<version>.dmg

set -euo pipefail

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "dev")}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="LidIA"

echo "==> Building ${APP_NAME} release ${VERSION}..."
echo ""

# 1. Build in release mode
echo "==> Step 1/6: Building release binary..."
cd "${ROOT_DIR}"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

# 2. Create .app bundle (same structure as run.sh but with release binary)
echo "==> Step 2/6: Packaging .app bundle..."
RELEASE_APP="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${RELEASE_APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

rm -rf "${RELEASE_APP}"
mkdir -p "${MACOS}" "${RESOURCES}" "${DIST_DIR}"

# Copy release executable
cp "${BIN_PATH}/LidIA" "${MACOS}/LidIA"

# Copy Info.plist
cp "${ROOT_DIR}/Sources/LidIA/Resources/Info.plist" "${CONTENTS}/Info.plist"

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

# Copy LidiaMCP if exists
if [ -f "${BIN_PATH}/LidiaMCP" ]; then
    cp "${BIN_PATH}/LidiaMCP" "${MACOS}/LidiaMCP"
fi

# 3. Ad-hoc code sign (no Developer ID)
echo "==> Step 3/6: Code signing (ad-hoc)..."
ENTITLEMENTS="${ROOT_DIR}/Sources/LidIA/Resources/LidIA.entitlements"
codesign --force --sign - --entitlements "${ENTITLEMENTS}" "${RELEASE_APP}"

# 4. Create .zip
echo "==> Step 4/6: Creating ZIP archive..."
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
cd "${DIST_DIR}"
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP_NAME}.app" "${ZIP_NAME}"
echo "    Created: dist/${ZIP_NAME} ($(du -h "${ZIP_NAME}" | cut -f1))"

# 5. Create .dmg
echo "==> Step 5/6: Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_NAME}"

# Create a temporary DMG folder with app + Applications symlink
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

# 6. Cleanup
echo "==> Step 6/6: Cleanup..."
rm -rf "${RELEASE_APP}"

cd "${ROOT_DIR}"
echo ""
echo "==> Release artifacts ready in dist/:"
ls -lh "dist/${ZIP_NAME}" "dist/${DMG_NAME}"
echo ""
echo "Next steps:"
echo "  1. Test the .app from the DMG (drag to Applications, open)"
echo "  2. Tag the release: git tag v${VERSION} && git push --tags"
echo "  3. Create GitHub release: gh release create v${VERSION} dist/${ZIP_NAME} dist/${DMG_NAME} --title 'LidIA ${VERSION}' --notes 'Release notes here'"
