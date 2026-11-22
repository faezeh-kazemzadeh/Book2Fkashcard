# Install Book2Flashcards on your iPhone or iPad (Windows PC, no Mac, free Apple ID)

This guide takes you from the unsigned IPA built by GitHub Actions to the app running on your iPhone or iPad, using **Sideloadly** on a **Windows PC** and your **free Apple ID**. It is for **personal use** only.

**Time needed:** ~30 minutes the first time, ~2 minutes for each weekly refresh.

---

## What you need

| Item | Requirement |
|---|---|
| iPhone / iPad | **iOS / iPadOS 17.0 or later** (Settings › General › About › iOS Version). The app runs on both iPhone and iPad. |
| Windows PC | Windows 10 or 11, 64-bit, with a free USB port and internet |
| Cable | A USB cable that carries **data** (the one from Apple is best; some cheap cables only charge) |
| Apple ID | Any Apple ID with **two-factor authentication** on. No paid Developer account is needed. |
| GitHub | You must be signed in to GitHub to download the build artifact |

> **Privacy tip (optional):** you can create a separate free Apple ID just for sideloading at appleid.apple.com. It works the same way and keeps your main account out of third-party tools. Both are fine.

---

## Part 1 – Download the IPA (on the Windows PC)

1. Open the **Unsigned IPA** workflow page and sign in to GitHub:
   https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/workflows/unsigned-ipa.yml
2. Click the newest run with a **green ✓**.
   Current verified build: https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/runs/45044071980
3. Scroll down to **Artifacts** and click **`Book2Flashcards-1.0.0-1-62d1e99-unsigned.ipa`** (≈ 1 MB).
   *Ignore the `…-dSYM` artifact – it is only for reading crash reports.*
4. GitHub downloads a **`.zip`**. Right-click it › **Extract All…** › Extract.
5. Inside the extracted folder you now have **`Book2Flashcards-1.0.0-1-62d1e99-unsigned.ipa`**. This `.ipa` is the file you will use – **not** the `.zip`.

> Artifacts are kept for 30 days. If the list is empty or expired, click **Run workflow** on the workflow page, wait ~3 minutes, and use the new run.

---

## Part 2 – Install iTunes, iCloud and Sideloadly (on the Windows PC)

Sideloadly uses Apple's device drivers, which come with iTunes and iCloud. **The Microsoft Store versions do not work reliably** – use the direct downloads from Apple.

1. **Remove Store versions first** (if installed): Settings › Apps › Installed apps → uninstall *iTunes* and *iCloud* if their publisher is "Microsoft Store"/"Apple Inc." from the Store.
2. **Install iTunes (web version)**: https://www.apple.com/itunes/ → scroll to *"Looking for other versions?"* → **Windows** → download the 64-bit installer → install.
3. **Restart the PC.**
4. **iCloud for Windows – only if Sideloadly asks for it.** Some Sideloadly versions also need Apple's iCloud components. If Sideloadly reports missing iCloud/Apple components after Part 4, install iCloud for Windows the same way (non-Store version where Apple still offers one), restart, and retry. You do **not** need to sign in to iCloud.
5. **Install Sideloadly**: https://sideloadly.io → **Download for Windows** → run the installer.
   Only download Sideloadly from sideloadly.io.

---

## Part 3 – Connect the iPhone (or iPad)

1. **Unlock** the iPhone and keep it on the Home Screen.
2. Plug it into the PC with the USB cable.
3. On the iPhone, tap **Trust** on *"Trust This Computer?"* and enter your passcode.
4. Open **iTunes** once on the PC: a small phone icon should appear near the top left. If it does, Windows can see the device. Close iTunes again.

---

## Part 4 – Sign and install with Sideloadly

1. Open **Sideloadly**.
2. **iDevice:** pick your iPhone from the drop-down (it shows the device name and iOS version).
3. **Apple account:** type your Apple ID email.
4. **IPA:** drag `Book2Flashcards-1.0.0-1-62d1e99-unsigned.ipa` onto the IPA icon on the left (or click it and browse to the file).
5. Leave **Advanced options** at their defaults for the first attempt.
6. Click **Start**.
7. Enter your **Apple ID password** when asked.
8. Enter the **6-digit two-factor code** that appears on your iPhone/iPad/Mac or by SMS.
9. Wait. The log shows signing, uploading and installing. When it says **"Done."**, the Book2Flashcards icon is on your iPhone's Home Screen.

> Sideloadly signs the app with a free "Apple Development" certificate for your Apple ID. Your password goes to Apple's servers for this login.

---

## Part 5 – Turn on Developer Mode (iPhone, once)

iOS 16 and later require Developer Mode to run apps signed with a development certificate.

1. Tap the Book2Flashcards icon. iOS shows **"Developer Mode Required"** – tap **OK**.
2. Open **Settings › Privacy & Security**, scroll to the bottom, tap **Developer Mode**.
   *(The option only appears after a sideloaded app is installed – that is why this step comes after Part 4.)*
3. Switch **Developer Mode** on → tap **Restart**.
4. After the iPhone restarts and you unlock it, a prompt asks **"Turn On Developer Mode?"** → tap **Turn On** and enter your passcode.

---

## Part 6 – Trust the developer (iPhone, once per Apple ID)

1. Tap the app icon. If iOS says **"Untrusted Developer"**, tap **Cancel**.
2. Open **Settings › General › VPN & Device Management**.
3. Under **Developer App**, tap your **Apple ID email**.
4. Tap **Trust "Apple Development: your@email…"** → **Trust**.
   *(The iPhone must be online for this; it checks the certificate with Apple.)*

---

## Part 7 – Launch

1. Tap **Book2Flashcards** on the Home Screen.
2. The welcome screen asks which language you're learning, your native language and your level → **Get Started**.
3. Optional – AI cards: **Settings › AI › Provider: OpenAI** → paste your own API key → **Save & Test Connection**. Without a key, cards are built offline from the vocabulary lists and grammar boxes in your book.
4. **Library › + › Import File / Scan Pages / Photos** to add your first book.

### iPad
Repeat **Parts 3–7** with the iPad connected (same IPA, same Apple ID). Developer Mode (Part 5) and trusting (Part 6) must be done on each device separately.

---

## Keeping it running: the 7-day limit

Apps signed with a free Apple ID **stop opening after 7 days** ("…is no longer available").

**To refresh (before or after it expires):** repeat **Part 4** with the same IPA and the same Apple ID. Sideloadly reinstalls over the existing app – **your books, cards and study history are kept**. Do **not** delete the app first; deleting it erases its data.

**Automatic refresh (optional):**
1. In iTunes, with the iPhone connected, open the device page and tick **"Sync with this iPhone over Wi-Fi"** → Apply.
2. If your Sideloadly version offers **automatic refresh** (its background "daemon"), enable it for Book2Flashcards after a successful install. Menu names vary between versions; if you can't find it, use the manual refresh above.
3. Keep the PC on and Sideloadly running in the background on the **same Wi-Fi** as the iPhone. It refreshes the app before it expires.

**Other free-account limits**
- Maximum **3 sideloaded apps** active at a time, and **10 new app IDs per 7 days**.
- The app is for your own devices only.

---

## What works and what doesn't (free Apple ID)

| Works | Doesn't work |
|---|---|
| Importing PDF, scanned PDF, EPUB, Word, TXT, photos, camera scans | **iCloud Sync** between iPhone and iPad (free accounts can't use iCloud) – each device keeps its own library |
| OCR, lesson detection, offline card generation | **Buying Premium** (no In-App Purchase) – free-plan limits apply: **3 books, 500 cards**, basic OCR |
| AI cards with your own OpenAI / Azure key | **Anki export** and **AI explanations** (Premium features) |
| Studying (FSRS / SM-2), quizzes, pronunciation audio, search | Settings syncing between devices |
| Anki **import** (.apkg, .csv, .txt) | |

To move books between devices, import the same file on each device.

---

## Troubleshooting

### Sideloadly doesn't show the iPhone
- Unlock the iPhone and keep the screen on; reconnect the cable.
- Try another USB port (directly on the PC, not a hub) and another cable.
- Make sure you tapped **Trust** on the iPhone. If you tapped "Don't Trust": Settings › General › Transfer or Reset iPhone › Reset › **Reset Location & Privacy**, then reconnect and trust.
- Check iTunes is the **web version** (Part 2). Uninstall the Microsoft Store versions, reinstall from Apple, restart.
- Open iTunes: if iTunes can't see the phone either, the problem is the driver/cable, not Sideloadly.

### Login fails / no 2FA code
- Make sure two-factor authentication is on for the Apple ID (appleid.apple.com › Sign-In and Security).
- Use your **normal Apple ID password**, not an app-specific password.
- If no code appears, on the iPhone go to **Settings › [your name] › Sign-In & Security › Two-Factor Authentication › Get Verification Code** and type that code into Sideloadly.
- Check the PC's date and time are set automatically.

### "Invalid IPA" / "Could not extract"
- You dragged the **`.zip`** instead of the **`.ipa`**. Extract the zip first (Part 1, step 4).
- Re-download the artifact if extraction fails (incomplete download).

### "Maximum number of apps" / "App ID limit reached"
- Free accounts allow 3 active sideloaded apps: delete one you don't need from the iPhone, then retry.
- The 10-App-IDs-per-week limit resets 7 days after the IDs were created. Wait, or use another free Apple ID.

### "An App ID with identifier … is not available"
- Open Sideloadly's **Advanced options** and change the **Bundle ID** to something unique, e.g. `com.yourname.book2flashcards`, then Start again.
- Note: changing the bundle ID installs a *separate* app; keep the same bundle ID for every refresh so your data is kept.

### "Developer Mode Required" keeps appearing / option missing
- The Developer Mode switch only appears after a sideloaded app is installed. Finish Part 4 first.
- After switching it on you must **restart** and confirm **Turn On** after unlocking (Part 5, step 4).

### "Untrusted Developer" / "Unable to Verify App"
- Do Part 6 (trust your Apple ID in VPN & Device Management).
- The iPhone needs internet for the first verification. Turn off VPNs/content blockers that block Apple servers and try again.

### App installed but "…is no longer available"
- The 7-day signature expired, or you signed it with an Apple ID whose certificate was revoked (e.g. by signing in Sideloadly on another PC). Re-run Part 4 with the same Apple ID.

### iOS version too old
- Error mentions "MinimumOSVersion" or the app won't install: update to **iOS 17 or later** (Settings › General › Software Update).

### App opens but crashes immediately
1. Reproduce the crash once.
2. On the iPhone: **Settings › Privacy & Security › Analytics & Improvements › Analytics Data**.
3. Find the newest entry starting with **`Book2Flashcards`** (`.ips`), open it, tap **Share**, and send it (e.g. by email to yourself, then attach to a GitHub issue).
4. Note which build you installed (`62d1e99`). The matching `…-dSYM` artifact from the same run is needed to make the crash report readable.

### Sideloadly shows another error
- Update Sideloadly to the latest version and retry.
- Copy the full log text from Sideloadly's log window and include it when asking for help, together with your iOS version and the IPA name.

---

## Removing the app

Press and hold the icon › **Remove App** › **Delete App**. This deletes all books and cards stored on that device. Optionally turn Developer Mode off again in Settings › Privacy & Security.
