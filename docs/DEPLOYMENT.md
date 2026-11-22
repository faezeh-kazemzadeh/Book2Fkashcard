# Deployment Guide

## 1. Prerequisites
- macOS 15+, **Xcode 16.4+** (Xcode 26 to use the Apple Intelligence provider; the code compiles on both thanks to `#if canImport(FoundationModels)`).
- Apple Developer Program membership.
- `brew install xcodegen` (and optionally `brew install xcbeautify`).

## 2. Identifiers (developer.apple.com › Certificates, IDs & Profiles)
1. **App ID** `com.book2flashcards.pro` (change everywhere – `project.yml`, `AppConstants`, entitlements, StoreKit IDs – if you use another prefix) with capabilities:
   - iCloud → CloudKit, container **`iCloud.com.book2flashcards.pro`**
   - Push Notifications (CloudKit silent pushes)
   - In-App Purchase
   - Data Protection (Complete Until First User Authentication)
2. **Keychain sharing** is implied by `keychain-access-groups`.

## 3. Generate & open
```bash
export B2F_TEAM_ID=ABCDE12345     # your Team ID
xcodegen generate
open Book2Flashcards.xcodeproj
```
Run the `Book2Flashcards` scheme. The scheme uses `App/Resources/Products.storekit`, so purchases work locally without App Store Connect.

## 4. CloudKit
1. Run the app once on a device/simulator signed into iCloud with Sync turned on (Settings › Sync). SwiftData creates the development schema.
2. In the **CloudKit Console** verify record types `CD_BookEntity`, `CD_FlashcardEntity`, … exist.
3. Before release: **Deploy Schema Changes to Production**. Every later model change must be additive (new optional attributes/entities) – never rename or delete deployed fields.
4. Change `aps-environment` to `production` for Release (Xcode does this automatically for distribution signing).

## 5. AI configuration
Choose one for production:
- **Recommended – proxy:** deploy `Backend/ai-proxy/worker.ts` (Cloudflare Workers: `wrangler deploy`; secrets `OPENAI_API_KEY`, `TOKEN_SIGNING_KEY`; KV namespace `QUOTA`). Set the `B2F_PROXY_BASE_URL` build setting. Your sign-in/token service issues `Book2Flashcards Cloud` tokens (e.g. after verifying an App Store transaction JWS server-side using `appAccountToken`).
- **Bring-your-own-key:** leave `B2F_PROXY_BASE_URL` empty; users enter OpenAI or Azure keys (stored with Secure Enclave wrapping).
- **On-device:** Apple Intelligence works without any configuration on supported devices (iOS 26+).

Never put API keys in `Info.plist`, build settings or source.

## 6. In-App Purchases (App Store Connect)
Create exactly these products (IDs must match `StoreManager.ProductID` and `Products.storekit`):

| Type | Product ID | Suggested price |
|---|---|---|
| Auto-renewable (group "Premium", level 2) | `com.book2flashcards.pro.premium.monthly` | $5.99 / month |
| Auto-renewable (group "Premium", level 1) | `com.book2flashcards.pro.premium.yearly` | $39.99 / year, 1-week free trial |
| Non-consumable | `com.book2flashcards.pro.premium.lifetime` | $79.99 |

Add a review screenshot of the paywall for each and fill localized display names. Enable **App Store Server Notifications V2** pointing at your backend if you validate subscriptions server-side.

## 7. Versioning & build
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` (or `agvtool`).
- Archive: Product › Archive (Release, whole-module optimisation), or CI:
```bash
xcodebuild -project Book2Flashcards.xcodeproj -scheme Book2Flashcards -configuration Release \
  -archivePath build/Book2Flashcards.xcarchive -destination 'generic/platform=iOS' archive
xcodebuild -exportArchive -archivePath build/Book2Flashcards.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```
- Upload with Xcode Organizer or `xcrun altool --upload-app` / Transporter. For CI, use an App Store Connect API key (`.p8`) stored as an encrypted CI secret – never commit it (`.gitignore` covers `*.p8`).

## 8. TestFlight
Internal testers first (no review). Test matrix: iPhone SE (small screen), iPhone 16 Pro Max, iPad (split view, keyboard), VoiceOver on, Dynamic Type XXXL, Persian/Arabic UI language, airplane mode (offline study/export), two devices on one Apple Account (sync), sandbox purchase/restore/cancel.

## 9. Monitoring
- Xcode Organizer: crashes, hangs, energy, disk writes.
- MetricKit can be added for on-device diagnostics without third-party SDKs.
- Proxy: Cloudflare analytics + quota KV.
