# Apple Developer Account Setup — Manual Steps

> These steps must be done in a web browser. They cannot be automated via CLI.
> Complete these once your account verification is approved.

## 1. Accept Developer Agreement
- Go to [developer.apple.com](https://developer.apple.com)
- Sign in with abreujcp@gmail.com
- Accept the license agreement if prompted

## 2. Register Bundle IDs
- Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
- Click **+** → App IDs → Register two:

| Platform | Bundle ID | Capabilities |
|----------|-----------|-------------|
| macOS | `io.lidia.app` | iCloud (CloudKit), Push Notifications |
| iOS | `io.lidia.ios` | iCloud (CloudKit), Push Notifications |

## 3. Create iCloud Container
- Same page → **iCloud Containers** tab → click **+**
- Container ID: `iCloud.io.lidia.app`
- Go back to both App IDs and associate this container

## 4. Create App in App Store Connect
- Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+** → New App
- Platform: **iOS**
- Name: **LidIA**
- Primary Language: **English (U.S.)**
- Bundle ID: `io.lidia.ios` (appears in dropdown after step 2)
- SKU: `lidia-ios`

## 5. Generate API Key
- Go to [App Store Connect → Integrations → API](https://appstoreconnect.apple.com/access/integrations/api)
- Click **+** → Generate API Key
- Name: `LidIA CI`
- Role: `App Manager`
- **Download the `.p8` file** (only available ONCE at creation)
- Note the **Key ID** and **Issuer ID**

## 6. Store the key
```bash
mkdir -p ~/.appstoreconnect/private_keys/
mv ~/Downloads/AuthKey_XXXX.p8 ~/.appstoreconnect/private_keys/
```

## 7. Tell Claude these values
- **Team ID** (probably `B67VDMT9YQ` — confirm on developer portal)
- **API Key ID**
- **API Issuer ID**
- Path to `.p8` file

Claude will plug them into `ExportOptions.plist`, `project.yml`, and `scripts/upload-testflight.sh`.
