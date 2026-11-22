# Release Package – Book2Flashcards AI Pro

| | |
|---|---|
| **Repository** | https://github.com/faezeh-kazemzadeh/Book2Fkashcard |
| **Branch** | `claude/book2flashcards-ai-pro-e8mlhi` |
| **Tracked files** | 108 (including this document and BUILD_REPORT.md) |
| **Swift files** | 83 files, ~12,260 lines |
| **Minimum OS** | iOS 17.0 (iPhone and iPad) · Apple Intelligence provider needs iOS 26 |
| **Toolchain** | Xcode 16.4 or later · Swift 5 language mode · XcodeGen |
| **Status** | ✅ CI green on Linux, macOS and iOS since `5923f78` (run #9). See [BUILD_REPORT.md](BUILD_REPORT.md). |

### Files by area

| Area | Files | Swift files / lines |
|---|---:|---:|
| `Packages/B2FCore` sources (core logic) | 33 | 31 / ~5,570 |
| `Packages/B2FCore` tests | 4 | 4 / ~830 |
| `App/Sources` (iOS app) | 43 | 43 / ~5,370 |
| `App/Resources` (plist, assets, strings, StoreKit) | 10 | – |
| `App/Tests` + `App/UITests` | 4 | 4 / ~450 |
| Docs, CI, project spec, backend, root files | 13 | – |

---

## Build status

All three CI jobs pass as of commit `5923f78` (run #9): core package on Linux and macOS (62/62 tests each), iOS app build with 23 unit/integration tests passing (1 Keychain test skipped in unsigned CI builds) and 6/6 UI tests.
Getting there took 9 runs; every failure, fix and remaining caveat is documented in **[BUILD_REPORT.md](BUILD_REPORT.md)**.

---|---|---|
| #1 | `3e5ff36` | **Failed in all 3 jobs** (Linux core, macOS core, iOS app) |
| #2 | the commit that adds this file | Pending: check the Actions tab |

**Cause of run #1:** two expressions in the core package made the Swift type checker give up ("unable to type-check this expression in reasonable time"):
- `Util/ZipArchive.swift` – DOS date/time bit packing
- `Util/Checksums.swift` – SHA-1 digest byte output

Both are rewritten with explicitly typed steps in the same commit as this document.

**What this means:** because the core package failed, **the app target, the app tests and the UI tests were never compiled in run #1.** More errors are expected once run #2 reaches them. CI runs on every push to `claude/**` branches: https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions

---

## Folder structure

```
Book2Fkashcard/
├── README.md
├── RELEASE_PACKAGE.md
├── project.yml                         XcodeGen spec (generates Book2Flashcards.xcodeproj)
├── .gitignore
├── .github/workflows/ci.yml            Core tests (Linux + macOS), iOS build + tests
├── Backend/ai-proxy/worker.ts          Reference AI proxy (Cloudflare Worker), keeps API keys off devices
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── APP_STORE_SUBMISSION.md
│   └── AppStore/
│       ├── Metadata.md                 Description, subtitle, keywords, screenshots, preview video, ASO
│       ├── PRIVACY_POLICY.md           Template – fill placeholders, legal review
│       └── TERMS_OF_SERVICE.md         Template – fill placeholders, legal review
├── Packages/B2FCore/                   Platform-independent core (iOS, macOS, Linux)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── CSQLite/                    module.modulemap, shim.h (SQLite on Linux)
│   │   └── B2FCore/
│   │       ├── AI/                     AIProvider.swift, ChatCompletionsProvider.swift,
│   │       │                           FlashcardGenerator.swift, PromptLibrary.swift
│   │       ├── Analytics/              StudyAnalytics.swift
│   │       ├── Anki/                   AnkiConnectClient.swift, AnkiExportModels.swift,
│   │       │                           AnkiNoteMapper.swift, AnkiPackageReader.swift,
│   │       │                           AnkiPackageWriter.swift, AnkiTextImporter.swift
│   │       ├── Entitlements/           FeatureGate.swift
│   │       ├── Import/                 DocumentTextExtractors.swift (EPUB, DOCX, TXT)
│   │       ├── Layout/                 LayoutAnalyzer.swift, LessonStructureDetector.swift
│   │       ├── Models/                 DocumentModels.swift, Flashcard.swift, Language.swift
│   │       ├── OCR/                    OCRLanguagePlan.swift
│   │       ├── Quality/                VocabularyQualityFilter.swift, WordLists.swift
│   │       ├── Quiz/                   QuizEngine.swift
│   │       ├── SRS/                    FSRSScheduler.swift, SM2Scheduler.swift, SchedulingModels.swift
│   │       ├── Search/                 SearchIndex.swift
│   │       └── Util/                   Checksums.swift, HTTPTransport.swift, SQLiteDatabase.swift,
│   │                                   TextNormalizer.swift, ZipArchive.swift
│   └── Tests/B2FCoreTests/             AIAndStudyToolsTests.swift, AnkiTests.swift,
│                                       ContentPipelineTests.swift, SchedulerTests.swift
└── App/
    ├── Resources/
    │   ├── Info.plist
    │   ├── Book2Flashcards.entitlements
    │   ├── PrivacyInfo.xcprivacy
    │   ├── Localizable.xcstrings       English + Persian (101 strings)
    │   ├── Products.storekit           Local StoreKit test configuration
    │   └── Assets.xcassets/            AppIcon (placeholder), AccentColor, LaunchBackground
    ├── Sources/
    │   ├── App/                        Book2FlashcardsApp.swift, AppModel.swift
    │   ├── AI/                         AIProviderFactory.swift (+ Apple on-device provider)
    │   ├── Anki/                       AnkiServices.swift
    │   ├── Audio/                      SpeechService.swift, SpeechRecognizer.swift
    │   ├── Import/                     DocumentImporter.swift
    │   ├── OCR/                        ImagePreprocessor.swift, VisionOCREngine.swift
    │   ├── Persistence/                Entities.swift, LibraryRepository.swift, LibraryWriter.swift,
    │   │                               PersistenceController.swift, PreviewData.swift
    │   ├── Processing/                 BookProcessingPipeline.swift
    │   ├── Scanner/                    DocumentScannerView.swift
    │   ├── Search/                     SearchService.swift
    │   ├── Security/                   EncryptedFileStore.swift, KeychainStore.swift, SecureSecrets.swift
    │   ├── Settings/                   AppSettings.swift
    │   ├── Store/                      StoreManager.swift
    │   ├── Sync/                       SyncStatusMonitor.swift
    │   └── Features/
    │       ├── Book/                   BookDetailView, CardEditorView, LessonDetailView, PageReviewView
    │       ├── Components/             Components.swift
    │       ├── Dashboard/              DashboardView, DashboardViewModel
    │       ├── Export/                 AnkiExportView
    │       ├── Library/                LibraryView, LibraryViewModel
    │       ├── Paywall/                PaywallView
    │       ├── Quiz/                   QuizViewModel, QuizViews
    │       ├── Root/                   RootView, OnboardingView
    │       ├── Search/                 SearchView
    │       ├── Settings/               SettingsView
    │       └── Study/                  CardFaceView, StudySessionView, StudySessionViewModel
    ├── Tests/                          OCRAndImportTests.swift, PersistenceIntegrationTests.swift,
    │                                   ServiceTests.swift
    └── UITests/                        Book2FlashcardsUITests.swift
```

---

## Build instructions

### 1. Core package (fastest feedback, no Xcode project needed)
```bash
git clone https://github.com/faezeh-kazemzadeh/Book2Fkashcard.git
cd Book2Fkashcard
git checkout claude/book2flashcards-ai-pro-e8mlhi
swift test --package-path Packages/B2FCore
```
On Linux, first install the SQLite headers with `apt-get install libsqlite3-dev`.

### 2. iOS app
```bash
brew install xcodegen
export B2F_TEAM_ID=ABCDE12345        # your Apple Developer Team ID
xcodegen generate                   # creates Book2Flashcards.xcodeproj (git-ignored)
open Book2Flashcards.xcodeproj
```
- Scheme **Book2Flashcards** → run on an iPhone or iPad simulator. Purchases use `Products.storekit` locally.
- Tests: ⌘U, or:
```bash
xcodebuild test -project Book2Flashcards.xcodeproj -scheme Book2Flashcards \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
- Re-run `xcodegen generate` after adding or removing files; the project file is generated, not committed.

### 3. Recommended fix-up order
1. Get `swift test --package-path Packages/B2FCore` green (Linux CI job first: it is the strictest about Foundation APIs).
2. Build the app target only (`xcodebuild build`), fixing compile errors.
3. Run app unit/integration tests, then UI tests.

---

## Known compilation risks

The code now compiles with Xcode 16.4 (Swift 5 language mode) and Swift 6.0 on Linux. The risks below remain relevant for **other toolchains** (Xcode 26, Swift 6 language mode) and for future edits.

| # | Risk | Where | Likely fix |
|---|---|---|---|
| 1 | **More type-checker timeouts** on long integer/bitwise expressions (same failure class as CI run #1) | `Checksums.swift` (SHA-1 message schedule), `ZipArchive.swift` (`readLE32`), `AnkiPackageWriter.guid(for:)` | Split into typed `let`s |
| 2 | **`@Observable` + `didSet`** on every property, and properties assigned in `init` before the observer is set | `App/Sources/Settings/AppSettings.swift` | If rejected, replace `didSet` with explicit setter methods or `@ObservationIgnored` backing storage |
| 3 | **SwiftData `#Predicate`** with captured locals and `!=` on strings | `LibraryRepository.swift` | Move the comparison to an in-memory `filter` after the fetch |
| 4 | **Heterogeneous literals** in `[String: Any]` JSON blobs | `AnkiPackageWriter.swift`, `AnkiConnectClient.swift` | Add `as [String: Any]` / `as [Any]` annotations |
| 5 | **Multi-statement closure inference** (`map`, `compactMap`, `reduce` without explicit return types) | Core package and view models | Add explicit closure return types |
| 6 | **Foundation Models API names** (`SystemLanguageModel.default.availability`, `LanguageModelSession(instructions:)`, `respond(to:)`) | `AIProviderFactory.swift` (compiled only with Xcode 26, `#if canImport(FoundationModels)`) | Adjust to the shipped SDK |
| 7 | **Linux Foundation gaps** (`String.Encoding(rawValue:)` for Windows-1256, `XMLParser` via FoundationXML, `JSONSerialization` with `Int64`) | `DocumentTextExtractors.swift`, `AnkiPackageWriter.swift` | Guard with `#if canImport(Darwin)` or cast to `Int` |
| 8 | **Sendable / actor-isolation diagnostics** (warnings in Swift 5 mode, errors under Swift 6 mode) | `PageContent` (CGImage), `OCREngine` (CIContext), `StoreManager`/`SyncStatusMonitor` `deinit`, `AnkiExportScope: Identifiable` retroactive conformance | Keep Swift 5 language mode for 1.0; address before enabling Swift 6 |
| 9 | **XcodeGen spec options** – `link: false` on a package dependency, `buildPhase: none` for the `.storekit` file, empty `${B2F_TEAM_ID}` | `project.yml` | Adjust spec; worst case, link B2FCore into the test target normally |
| 10 | **Exhaustive `switch`es** over framework enums that gain cases (e.g. `Product.SubscriptionPeriod.Unit`, `PurchaseResult`) | `PaywallView.swift`, `StoreManager.swift` | Add `@unknown default` where the compiler asks |

---

## Expected first-build issues

These are not compile errors; they are what to expect once the build succeeds.

**Tests**
- **Keychain tests may fail in CI.** CI builds with `CODE_SIGNING_ALLOWED=NO`, and the Keychain can return `errSecMissingEntitlement` (-34018) for unsigned simulator builds. Affects `SecurityTests` and anything that saves API keys. Fix: run those tests with signing, or skip them when the entitlement is missing.
- **Vision OCR tests depend on the OS version.** `OCRTests` assert on recognised text and on the classification of rendered pages. The rotated-page test is the most fragile.
- **StoreKit test needs the `.storekit` file in the test bundle.** `project.yml` copies it there; if `SKTestSession(configurationFileNamed: "Products")` can't find it, check the test target's Copy Bundle Resources phase.
- **UI accessibility audit may report real issues** (contrast, clipped text at large Dynamic Type, unlabeled chart elements). Treat these as bugs to fix, not test noise.
- **Launch-performance test** is slow on CI and can be noisy.

**Runtime**
- **CloudKit is off by default.** iCloud Sync only activates after the Premium toggle, and requires the iCloud container to exist in your developer account and a signed build. The first sync on a real device creates the development schema.
- **No AI provider is configured on first launch** unless `B2F_PROXY_BASE_URL` is set or a key is entered in Settings › AI. Card generation then falls back to offline mode (book vocabulary lists and grammar boxes only), which produces far fewer cards.
- **Persian OCR is weaker than Latin-script OCR**, because Vision has no Persian model. Expect page-review warnings on Persian pages.
- **Speech, microphone and camera** features need a real device for meaningful testing; the document scanner is unavailable on the simulator.

**Tooling**
- `xcbeautify` is used in CI. Locally, either install it or drop the pipe.
- Xcode may update the generated project settings on first open; that's harmless because the project is regenerated from `project.yml`.

---

## Checklist before TestFlight

### Code health
- [ ] CI green on all three jobs (Linux core, macOS core, iOS build + tests)
- [ ] App builds in **Release** configuration with no errors; warnings reviewed
- [ ] Manual smoke test on a real iPhone **and** a real iPad:
  - [ ] Import a text PDF, a scanned PDF, an EPUB, a DOCX, a TXT and photos
  - [ ] Scan 5+ pages with the camera
  - [ ] Lessons detected; cards generated with AI **and** in offline mode
  - [ ] Study session: ratings, interval previews, audio (UK/US, all speeds)
  - [ ] All 9 quiz types, including the speaking quiz with microphone
  - [ ] Anki export (lesson, selected lessons, whole book) opens in AnkiMobile/Anki desktop with the correct deck tree, tags and audio
  - [ ] Anki import of `.apkg`, `.csv`, `.txt`
  - [ ] Search across all scopes
  - [ ] Airplane mode: study, view scanned pages and export decks all work offline
- [ ] Free-plan limits: 4th book and 501st card both show the paywall
- [ ] No crashes or hangs during a 300+ page import; memory stays bounded

### Accessibility & localisation
- [ ] VoiceOver walkthrough of the import, study and export flows
- [ ] Largest Dynamic Type size: no clipped or overlapping text
- [ ] Persian UI language: layout mirrors correctly; Persian card text renders right-to-left
- [ ] iPad hardware keyboard: ⌘1–5, Space to show the answer, 1–4 to rate

### Apple Developer / App Store Connect
- [ ] App ID `com.book2flashcards.pro` with iCloud (CloudKit), Push Notifications, In-App Purchase, Data Protection
- [ ] iCloud container `iCloud.com.book2flashcards.pro` created; sync tested between two devices on the same Apple Account
- [ ] CloudKit schema **deployed to Production**
- [ ] `aps-environment` resolves to `production` in the distribution build
- [ ] IAP products created with matching IDs: `…premium.monthly`, `…premium.yearly` (1-week trial), `…premium.lifetime`
- [ ] Sandbox tester: purchase, restore, cancel and expiry all behave correctly
- [ ] App record created; version, build number and bundle ID match

### Security & privacy
- [ ] No API keys anywhere in the repo, `Info.plist` or build settings (`git grep -nE "sk-[A-Za-z0-9]"` returns nothing)
- [ ] AI proxy deployed (or bring-your-own-key / Apple Intelligence chosen) and `B2F_PROXY_BASE_URL` set for Release
- [ ] `PrivacyInfo.xcprivacy` reflects actual data use; App Privacy questionnaire answered to match
- [ ] Encryption export compliance answered (`ITSAppUsesNonExemptEncryption = NO` — confirm still accurate)
- [ ] Privacy Policy and Terms published at the URLs in `AppConstants`, placeholders filled, legally reviewed

### Assets & metadata
- [ ] Final app icon replaces the placeholder
- [ ] Paywall copy and prices verified
- [ ] TestFlight "What to Test" notes written (point testers at import, OCR quality, Anki export)
- [ ] Internal testers group first; external testing only after Beta App Review

### Upload
- [ ] Archive → Validate App passes in Xcode Organizer
- [ ] Upload; build processed; export compliance answered
- [ ] Crash reporting checked in Organizer after the first tester sessions
