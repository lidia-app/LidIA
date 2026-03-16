# TestFlight Distribution & macOS Notarization Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [App Store Connect Setup](#app-store-connect-setup)
3. [Create API Key](#create-api-key)
4. [iOS: Archive, Export & Upload to TestFlight](#ios-testflight)
5. [macOS: Notarization & Stapling](#macos-notarization)
6. [Automation Scripts](#automation-scripts)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Apple Developer Account (abreujcp@gmail.com)
- Xcode 26+ installed
- Bundle IDs registered:
  - iOS: `io.lidia.ios`
  - macOS: `io.lidia.app`
- CLI tools: `xcrun`, `xcodebuild`, `altool` (bundled with Xcode)

Verify tools are available:

```bash
which xcrun
xcrun altool --help 2>&1 | head -3
xcodebuild -version
```

---

## App Store Connect Setup

### 1. Register Bundle IDs

Go to [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list):

1. Click **Identifiers** -> **+**
2. Select **App IDs** -> **App**
3. Register two identifiers:
   - **iOS app**: Bundle ID `io.lidia.ios`, Description "LidIA iOS"
   - **macOS app**: Bundle ID `io.lidia.app`, Description "LidIA macOS"
4. Enable capabilities as needed (iCloud, CloudKit)

### 2. Create App Record in App Store Connect

Go to [App Store Connect](https://appstoreconnect.apple.com):

1. Click **My Apps** -> **+** -> **New App**
2. Fill in:
   - **Platform**: iOS
   - **Name**: LidIA
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: io.lidia.ios
   - **SKU**: `lidia-ios` (any unique string)
3. Click **Create**
4. Note the **Apple ID** (numeric) shown in App Information — you may need it later

Repeat for macOS if distributing via the Mac App Store.

---

## Create API Key

App Store Connect API keys allow CLI tools (`altool`, `notarytool`, `xcodebuild`) to authenticate without interactive login.

1. Go to [App Store Connect -> Users and Access](https://appstoreconnect.apple.com/access/integrations/api)
2. Click **Integrations** tab -> **App Store Connect API**
3. Click **+** to generate a new key:
   - **Name**: `LidIA CI`
   - **Access**: App Manager
4. Click **Generate**
5. **Download the `.p8` file** (you can only download it ONCE)
6. Note:
   - **Key ID**: shown in the table (e.g., `ABC123DEFG`)
   - **Issuer ID**: shown at the top of the page (UUID format)

### Store the key

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXX.p8
```

### Set environment variables

Add to your `~/.zshrc`:

```bash
export API_KEY_ID="YOUR_KEY_ID"
export API_ISSUER_ID="YOUR_ISSUER_ID"
export API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
```

---

## iOS: Archive, Export & Upload to TestFlight {#ios-testflight}

### Step 1: Set your Team ID

Before building, update two files with your Apple Developer Team ID (found at https://developer.apple.com/account -> Membership Details):

1. `LidIAiOS/ExportOptions.plist` — replace `REPLACE_WITH_TEAM_ID`
2. `LidIAiOS/project.yml` — set `DEVELOPMENT_TEAM`

### Step 2: Archive

```bash
cd /Users/jcprz/notetaking/LidIA

xcodebuild archive \
    -project LidIAiOS/LidIAiOS.xcodeproj \
    -scheme LidIAiOS \
    -destination 'generic/platform=iOS' \
    -archivePath dist/LidIAiOS.xcarchive \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic
```

### Step 3: Export IPA

```bash
xcodebuild -exportArchive \
    -archivePath dist/LidIAiOS.xcarchive \
    -exportPath dist/ios-export \
    -exportOptionsPlist LidIAiOS/ExportOptions.plist \
    -allowProvisioningUpdates
```

### Step 4: Upload to TestFlight

Using `altool`:

```bash
xcrun altool --upload-app \
    -f dist/ios-export/LidIAiOS.ipa \
    -t ios \
    --apiKey "$API_KEY_ID" \
    --apiIssuer "$API_ISSUER_ID"
```

### Step 5: Configure TestFlight

After upload and Apple's processing (5-30 minutes):

1. Go to App Store Connect -> My Apps -> LidIA -> TestFlight
2. Fill in the **Test Information** (what to test, contact email)
3. **Compliance**: If the app doesn't use non-standard encryption, select "None of the algorithms mentioned above"
4. Add **Internal Testers** (up to 100, must be App Store Connect users)
5. Or create an **External Testing Group**:
   - Add tester emails or enable a **Public Link**
   - External groups require Apple's beta review (usually <24 hours for first build)

### One-command upload

```bash
API_KEY_ID=XXXXX API_ISSUER_ID=YYYYY ./scripts/upload-testflight.sh
```

---

## macOS: Notarization & Stapling {#macos-notarization}

macOS apps distributed outside the Mac App Store must be notarized for Gatekeeper.

### Step 1: Build the release DMG

```bash
./scripts/build-release.sh 0.1.0
```

This produces `dist/LidIA-0.1.0.dmg`.

### Step 2: Submit for notarization

```bash
xcrun notarytool submit dist/LidIA-0.1.0.dmg \
    --key ~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8 \
    --key-id "${API_KEY_ID}" \
    --issuer "${API_ISSUER_ID}" \
    --wait
```

The `--wait` flag blocks until notarization completes (usually 2-15 minutes).

### Step 3: Staple the notarization ticket

```bash
xcrun stapler staple dist/LidIA-0.1.0.dmg
```

### Step 4: Verify

```bash
spctl --assess --type open --context context:primary-signature -v dist/LidIA-0.1.0.dmg
xcrun stapler validate dist/LidIA-0.1.0.dmg
```

### Step 5: Distribute

```bash
gh release create v0.1.0 dist/LidIA-0.1.0.dmg --title "LidIA v0.1.0"
```

### Notarization for ZIP (alternative to DMG)

If distributing as a ZIP instead of DMG:

```bash
# Create ZIP from .app
ditto -c -k --keepParent .build/LidIA.app dist/LidIA-0.1.0.zip

# Submit
xcrun notarytool submit dist/LidIA-0.1.0.zip \
    --key ~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8 \
    --key-id "${API_KEY_ID}" \
    --issuer "${API_ISSUER_ID}" \
    --wait

# Staple the .app (not the ZIP), then re-zip
xcrun stapler staple .build/LidIA.app
ditto -c -k --keepParent .build/LidIA.app dist/LidIA-0.1.0.zip
```

---

## Automation Scripts

| Script | Purpose |
|--------|---------|
| `scripts/upload-testflight.sh` | Archive + export + upload iOS to TestFlight |
| `scripts/build-release.sh` | Build macOS .app + create DMG |

### Environment variables

| Variable | Description | Required |
|----------|-------------|----------|
| `API_KEY_ID` | App Store Connect API Key ID | Yes |
| `API_ISSUER_ID` | App Store Connect Issuer ID | Yes |
| `API_KEY_PATH` | Path to `.p8` key file | Optional (defaults to `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`) |

---

## Troubleshooting

### "No signing certificate found"

Xcode needs a distribution certificate. Go to Xcode -> Settings -> Accounts -> your team -> Manage Certificates -> **+** -> Apple Distribution.

### "No profiles found matching"

With `CODE_SIGN_STYLE=Automatic` and `-allowProvisioningUpdates`, Xcode creates profiles automatically. Make sure your Team ID is set correctly.

### "altool" deprecation warning

Apple is deprecating `altool` in favor of `notarytool` for macOS and the Transporter app / `iTMSTransporter` for iOS. If `altool` stops working, use:

```bash
# Alternative: use Transporter CLI directly
xcrun iTMSTransporter -m upload \
    -assetFile dist/ios-export/LidIAiOS.ipa \
    -apiKey "${API_KEY_PATH}" \
    -apiIssuer "${API_ISSUER_ID}"
```

### Notarization fails with "invalid signature"

Ensure the app is signed with a Developer ID Application certificate (not just development). The `.app` must be code-signed before creating the DMG:

```bash
codesign --deep --force --options runtime \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    .build/LidIA.app
```

### Build number conflicts

App Store Connect rejects uploads with duplicate build numbers. Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each upload, or let `manageAppVersionAndBuildNumber` in ExportOptions.plist handle it automatically.
