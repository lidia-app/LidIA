#!/bin/bash
set -euo pipefail

# Generate Sparkle EdDSA keys (run once, store securely)
# sparkle-project/Sparkle includes `generate_keys` tool after build
# Run: .build/artifacts/sparkle/Sparkle/bin/generate_keys
# This outputs a public key (for Info.plist) and stores private key in Keychain

VERSION="${1:?Usage: generate-appcast.sh <version>}"
DMG_PATH="dist/LidIA-${VERSION}.dmg"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: $DMG_PATH not found. Run build-release.sh first."
    exit 1
fi

DMG_SIZE=$(stat -f%z "$DMG_PATH")
DMG_SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
PUB_DATE=$(date -R)

# Sign the DMG with Sparkle's sign_update tool
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$DMG_PATH" 2>/dev/null || echo "SIGN_MANUALLY")

LIDIA_WEB_DIR="${LIDIA_WEB_DIR:-/Users/jcprz/notetaking/lidia-web}"

cat > "$LIDIA_WEB_DIR/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>LidIA Updates</title>
    <link>https://lidia-app.github.io/appcast.xml</link>
    <language>en</language>
    <item>
      <title>LidIA ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/lidia-app/LidIA/releases/download/v${VERSION}/LidIA-${VERSION}.dmg"
        length="${DMG_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}"
      />
    </item>
  </channel>
</rss>
EOF

echo "==> Appcast written to ${LIDIA_WEB_DIR}/appcast.xml"
echo "==> SHA256: ${DMG_SHA}"
echo "==> Push lidia-web to deploy: cd ${LIDIA_WEB_DIR} && git add appcast.xml && git commit -m 'update appcast for v${VERSION}' && git push"
