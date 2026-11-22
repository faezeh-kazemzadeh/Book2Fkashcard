# App Store Submission Guide

## Checklist before "Submit for Review"

### Build
- [ ] Archive built with Release configuration, correct version/build number.
- [ ] CloudKit schema deployed to **Production**.
- [ ] `B2F_PROXY_BASE_URL` points to production (or empty for BYOK).
- [ ] App icon replaced with final artwork (the repository ships a placeholder).
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) present; no third-party SDKs requiring their own manifests.
- [ ] `ITSAppUsesNonExemptEncryption = NO` — the app only uses Apple's encryption APIs (CryptoKit, TLS), which is exempt. Confirm this still holds for your final build.

### App Store Connect › App Information
- [ ] Name, subtitle, categories, age rating, content rights ("Does your app contain, show, or access third-party content?" → **Yes**: users import their own books).
- [ ] Privacy Policy URL (publish `docs/AppStore/PRIVACY_POLICY.md`), Terms of Use URL (`TERMS_OF_SERVICE.md`); add Terms link to the description (done in Metadata.md) – required for auto-renewable subscriptions.
- [ ] App Privacy questionnaire as in `Metadata.md`.

### Version page
- [ ] Screenshots (6.9" iPhone, 13" iPad) per `Metadata.md` plan; App Preview optional.
- [ ] Description, keywords, promotional text, support URL, marketing URL.
- [ ] In-App Purchases attached to the version (first submission must include them).

### Review notes (paste and adapt)
```
Book2Flashcards turns textbooks the user owns into flashcards.

How to test without an API key:
1. Settings › AI › Provider: "Apple Intelligence (on-device)" on a supported device, OR
   use the demo proxy token: [REVIEW_TOKEN] with provider "Book2Flashcards Cloud".
2. Library › + › Import File and choose the sample PDF at [URL to a public-domain sample],
   or Scan Pages with the camera.
3. Without AI, cards are still created from the book's vocabulary lists (offline mode).

Premium: purchase the yearly plan in the sandbox, or use Restore Purchases.
Anki export: open a book › Export to Anki › Export › Share .apkg.
iCloud Sync: Settings › Sync (Premium).
No login is required. Content imported by users stays private.
```
Provide a review account/token that does not expire for 30 days.

## Guideline hot spots

| Guideline | How the app complies |
|---|---|
| 2.1 App completeness | Offline fallback generation ensures reviewers always get cards even without AI. |
| 3.1.1 IAP | Premium unlocked only via StoreKit; no external purchase links. |
| 3.1.2 Subscriptions | Paywall shows price, period, trial terms, auto-renew notice, Terms & Privacy links, Restore button; value is ongoing (sync, AI). |
| 4.2 Minimum functionality | Native OCR, scheduling, quizzes, audio, Anki tooling. |
| 5.1.1 Data collection | Permission strings explain camera/photos/microphone/speech/local network use; all are requested only when the feature is used. |
| 5.1.2 Data use | Book text sent to AI only for the user's request; disclosed in privacy policy and AI settings. |
| 5.1.1(v) Account deletion | No accounts are created (proxy tokens are anonymous). If you add sign-in, add in-app account deletion. |
| 5.2 Intellectual property | Terms restrict use to material the user is entitled to; no content is shared publicly by the app. |
| 2.5.2 | No downloaded executable code; AI output is data only. |

## After approval
- Phased release (7 days) for 1.0 updates; monitor crashes in Organizer.
- Respond to reviews; prompt for ratings per ASO strategy.
- Plan 1.1: FSRS parameter optimisation from user history, more OCR languages (via cloud OCR backend), shared decks.
