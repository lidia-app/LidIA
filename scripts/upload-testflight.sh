#!/bin/bash
set -euo pipefail

#
# upload-testflight.sh — Archive, export, and upload LidIA iOS to TestFlight
#
# Prerequisites:
#   1. Apple Developer account with App Store Connect access
#   2. App Store Connect API key (.p8 file)
#   3. App record created in App Store Connect with bundle ID: io.lidia.ios
#   4. Set environment variables or edit the config below
#
# Usage:
#   ./scripts/upload-testflight.sh
#   API_KEY_ID=XXXXX API_ISSUER_ID=YYYYY ./scripts/upload-testflight.sh
#

# ── Config ──────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/LidIAiOS"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/LidIAiOS.xcarchive"
EXPORT_PATH="${DIST_DIR}/ios-export"
EXPORT_OPTIONS="${IOS_DIR}/ExportOptions.plist"
PROJECT="${IOS_DIR}/LidIAiOS.xcodeproj"
SCHEME="LidIAiOS"

# App Store Connect API Key — set via env vars or edit here
API_KEY_ID="${API_KEY_ID:-}"
API_ISSUER_ID="${API_ISSUER_ID:-}"
API_KEY_PATH="${API_KEY_PATH:-${HOME}/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8}"

# ── Validation ──────────────────────────────────────────────────────────────
if [[ -z "${API_KEY_ID}" || -z "${API_ISSUER_ID}" ]]; then
    echo "ERROR: API_KEY_ID and API_ISSUER_ID must be set."
    echo ""
    echo "Usage:"
    echo "  API_KEY_ID=XXXXX API_ISSUER_ID=YYYYY ./scripts/upload-testflight.sh"
    echo ""
    echo "Or export them in your shell profile:"
    echo "  export API_KEY_ID=XXXXX"
    echo "  export API_ISSUER_ID=YYYYY"
    echo "  export API_KEY_PATH=/path/to/AuthKey_XXXXX.p8  # optional, defaults to ~/.appstoreconnect/private_keys/"
    exit 1
fi

if [[ ! -f "${API_KEY_PATH}" ]]; then
    echo "ERROR: API key file not found at: ${API_KEY_PATH}"
    echo "Download your .p8 key from App Store Connect and place it there."
    exit 1
fi

if [[ ! -f "${EXPORT_OPTIONS}" ]]; then
    echo "ERROR: ExportOptions.plist not found at: ${EXPORT_OPTIONS}"
    exit 1
fi

# ── Clean previous artifacts ────────────────────────────────────────────────
echo "==> Cleaning previous build artifacts..."
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"
mkdir -p "${DIST_DIR}"

# ── Step 1: Archive ─────────────────────────────────────────────────────────
echo "==> Archiving ${SCHEME}..."
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination 'generic/platform=iOS' \
    -archivePath "${ARCHIVE_PATH}" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "${API_KEY_PATH}" \
    -authenticationKeyID "${API_KEY_ID}" \
    -authenticationKeyIssuerID "${API_ISSUER_ID}" \
    CODE_SIGN_STYLE=Automatic \
    | tail -20

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
    echo "ERROR: Archive failed — ${ARCHIVE_PATH} not found."
    exit 1
fi
echo "==> Archive created: ${ARCHIVE_PATH}"

# ── Step 2: Export IPA ──────────────────────────────────────────────────────
echo "==> Exporting IPA for App Store Connect..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "${API_KEY_PATH}" \
    -authenticationKeyID "${API_KEY_ID}" \
    -authenticationKeyIssuerID "${API_ISSUER_ID}" \
    | tail -10

IPA_FILE=$(find "${EXPORT_PATH}" -name "*.ipa" -print -quit)
if [[ -z "${IPA_FILE}" ]]; then
    echo "ERROR: Export failed — no .ipa found in ${EXPORT_PATH}"
    exit 1
fi
echo "==> IPA exported: ${IPA_FILE}"

# ── Step 3: Upload to TestFlight ────────────────────────────────────────────
echo "==> Uploading to TestFlight..."
xcrun altool --upload-app \
    -f "${IPA_FILE}" \
    -t ios \
    --apiKey "${API_KEY_ID}" \
    --apiIssuer "${API_ISSUER_ID}"

echo ""
echo "==> Upload complete!"
echo ""
echo "Next steps:"
echo "  1. Go to App Store Connect -> TestFlight"
echo "  2. Wait for Apple's processing (usually 5-30 minutes)"
echo "  3. Once processed, add testers or enable public link"
echo "  4. Testers install via TestFlight app on their device"
