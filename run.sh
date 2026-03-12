#!/bin/bash
# Build LidIA and package it as a proper .app bundle so macOS TCC
# permissions (Calendar, Reminders, Microphone, etc.) work correctly.
#
# Usage:
#   ./run.sh          # build + run
#   ./run.sh build    # build only (creates .build/LidIA.app)
#   ./run.sh clean    # remove .app bundle

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH="$(swift build --show-bin-path 2>/dev/null)"
APP_DIR="${ROOT_DIR}/.build/LidIA.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

PLIST_SRC="${ROOT_DIR}/Sources/LidIA/Resources/Info.plist"
ENTITLEMENTS="${ROOT_DIR}/Sources/LidIA/Resources/LidIA.entitlements"
ASSETS_BUNDLE="${BIN_PATH}/LidIA_LidIA.bundle"

case "${1:-run}" in
    clean)
        rm -rf "${APP_DIR}"
        echo "Cleaned ${APP_DIR}"
        exit 0
        ;;
    build|run)
        ;;
    *)
        echo "Usage: $0 [build|run|clean]"
        exit 1
        ;;
esac

# 1. Build
echo "==> Building LidIA..."
swift build

# 2. Create .app bundle structure
echo "==> Packaging .app bundle..."
mkdir -p "${MACOS}" "${RESOURCES}"

# 3. Copy executable
cp "${BIN_PATH}/LidIA" "${MACOS}/LidIA"

# 4. Copy Info.plist
cp "${PLIST_SRC}" "${CONTENTS}/Info.plist"

# 5. Compile asset catalog (SPM doesn't process xcassets)
# This produces Assets.car + AppIcon.icns in Resources/, which macOS needs
# for app icon in Dock, notifications, and other system surfaces.
XCASSETS_SRC="${ROOT_DIR}/Sources/LidIA/Resources/Assets.xcassets"
if [ -d "${XCASSETS_SRC}" ]; then
    echo "==> Compiling asset catalog..."
    xcrun actool "${XCASSETS_SRC}" \
        --compile "${RESOURCES}" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /dev/null \
        2>/dev/null || echo "Warning: actool failed, falling back to .icns copy"
fi

# 5b. Always copy the hand-crafted .icns (higher quality than actool output)
ICNS_SRC="${ROOT_DIR}/Sources/LidIA/Resources/AppIcon.icns"
if [ -f "${ICNS_SRC}" ]; then
    cp "${ICNS_SRC}" "${RESOURCES}/AppIcon.icns"
fi

# 5c. Copy SPM resource bundle (for any non-icon resources)
if [ -d "${ASSETS_BUNDLE}" ]; then
    cp -R "${ASSETS_BUNDLE}" "${RESOURCES}/"
fi

# 5d. Compile MLX Metal shaders into metallib and bundle them
# MLX requires a pre-compiled default.metallib in mlx-swift_Cmlx.bundle/
MLX_METAL_DIR="${ROOT_DIR}/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
MLX_BUNDLE="${RESOURCES}/mlx-swift_Cmlx.bundle"
if [ -d "${MLX_METAL_DIR}" ]; then
    MLX_METALLIB="${MLX_BUNDLE}/default.metallib"
    if [ ! -f "${MLX_METALLIB}" ]; then
        echo "==> Compiling MLX Metal shaders..."
        mkdir -p "${MLX_BUNDLE}"
        AIR_DIR=$(mktemp -d)
        find "${MLX_METAL_DIR}" -name "*.metal" -print0 | while IFS= read -r -d '' f; do
            name=$(basename "$f" .metal)
            xcrun -sdk macosx metal -c -I "${MLX_METAL_DIR}" "$f" -o "${AIR_DIR}/${name}.air" 2>/dev/null
        done
        xcrun -sdk macosx metallib "${AIR_DIR}"/*.air -o "${MLX_METALLIB}" 2>/dev/null
        rm -rf "${AIR_DIR}"
        echo "==> MLX metallib compiled: $(du -h "${MLX_METALLIB}" | cut -f1)"
    fi
fi

# 6. Copy LidiaMCP binary alongside the main executable
if [ -f "${BIN_PATH}/LidiaMCP" ]; then
    cp "${BIN_PATH}/LidiaMCP" "${MACOS}/LidiaMCP"
fi

# 7. Code sign with entitlements
# Use Apple Development identity for stable signing (preserves TCC permissions across rebuilds).
# Falls back to ad-hoc if no identity found.
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "")
if [ -n "${SIGN_IDENTITY}" ] && [ "${SIGN_IDENTITY}" != "" ]; then
    echo "==> Code signing with: ${SIGN_IDENTITY}"
    codesign --force --sign "${SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" --generate-entitlement-der "${APP_DIR}"
else
    echo "==> Code signing (ad-hoc — permissions may reset on rebuild)..."
    codesign --force --sign - --entitlements "${ENTITLEMENTS}" "${APP_DIR}"
fi

echo "==> Built: ${APP_DIR}"

# Force macOS to re-read the app icon from the bundle (clears icon cache)
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "${APP_DIR}" 2>/dev/null || true

if [ "${1:-run}" = "run" ]; then
    echo "==> Launching LidIA..."
    open "${APP_DIR}"
fi
