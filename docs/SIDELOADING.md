# Installing the unsigned IPA on your own iPhone (free Apple ID)

The **Unsigned IPA** workflow (`.github/workflows/unsigned-ipa.yml`) builds a Release `.ipa` on every push to `main` or `claude/**` and on demand. It is **not signed**, so iOS will not install it directly. A sideloading tool signs it on your computer with your **free Apple ID**, then installs it.

## 1. Download the IPA
1. Open https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/workflows/unsigned-ipa.yml (signed in to GitHub).
2. Open the latest green run → **Artifacts** → download `Book2Flashcards-…-unsigned.ipa`.
3. GitHub delivers it as a `.zip`; unzip it to get the `.ipa`.
   (No run yet? Click **Run workflow** on that page.)

## 2. Prepare the iPhone
- iOS 17 or later (the app's minimum).
- **Settings › Privacy & Security › Developer Mode → On**, then restart (iOS 16+). The option appears after a sideloaded app is first installed or the phone is connected to a Mac with Xcode; if it is missing, do step 3 first and come back.
- Connect the iPhone to your computer with a cable and tap **Trust This Computer**.

## 3. Sign and install – pick one tool

### Option A – Sideloadly (Windows or macOS, simplest)
1. Install Sideloadly (sideloadly.io) and, on Windows, iTunes and iCloud from Apple's website (not the Microsoft Store versions).
2. Drag the `.ipa` into Sideloadly, select your iPhone, enter your Apple ID.
3. Click **Start**. Sideloadly creates a free development certificate for your Apple ID, removes entitlements that free accounts cannot use, signs, and installs.

### Option B – AltStore (Windows or macOS, auto-refresh)
1. Install AltServer on the computer, then use it to install AltStore on the iPhone with your Apple ID.
2. Copy the `.ipa` to the iPhone (Files app / AirDrop) and open it with **AltStore › My Apps › +**.
3. AltStore can re-sign the app automatically every few days while AltServer is running on the same Wi-Fi.

### Option C – Xcode on a Mac (no IPA needed)
Build straight from source with a free "Personal Team": `xcodegen generate`, open the project, set **Signing & Capabilities › Team** to your Personal Team, **remove the iCloud, Push Notifications and In-App Purchase capabilities**, change the bundle ID to something unique (e.g. `com.yourname.book2flashcards`), select your iPhone and Run.

## 4. First launch
**Settings › General › VPN & Device Management** → your Apple ID → **Trust**. Then open Book2Flashcards.

## Limits of a free Apple ID

| Limit | Effect |
|---|---|
| Signature expires after **7 days** | The app stops opening; re-sign with the same tool (AltStore can do it automatically). Your data on the phone is kept. |
| Max **3 sideloaded apps** at a time, 10 App IDs per week | Counts AltStore itself when using Option B. |
| **No iCloud / CloudKit** | iCloud Sync is unavailable (it is off by default, so nothing breaks). Settings sync across devices also won't work. |
| **No In-App Purchase** | The paywall cannot load products, so Premium cannot be bought. Free-plan limits apply: 3 books, 500 cards, no Anki export, no AI explanations, basic OCR. |
| **No push notifications** | Not used by the app except for CloudKit sync. |
| Keychain items tied to the free signing identity | API keys and the page-encryption key may not survive a re-sign with a different certificate; re-enter API keys if asked. |

Everything else works offline: import, OCR, lesson detection, offline card generation, AI card generation with your own OpenAI/Azure key (entered in Settings › AI), studying, quizzes, audio, search and Anki *import*.

## Why not just install the IPA directly?
iOS only runs code signed by a certificate Apple issued to the installing account, embedded with a provisioning profile that lists the device (development/ad hoc) or that came through TestFlight/App Store. The CI runner has no Apple account, so the artifact is deliberately unsigned. For a build with iCloud, purchases and no 7-day expiry, use a paid Apple Developer account and TestFlight (see `FINAL_RELEASE_REPORT.md`, steps 2–6).
