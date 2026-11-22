# Build Report – Book2Flashcards AI Pro

| | |
|---|---|
| **Repository** | https://github.com/faezeh-kazemzadeh/Book2Fkashcard |
| **Branch** | `claude/book2flashcards-ai-pro-e8mlhi` |
| **First green commit** | `5923f78` – CI run #9 |
| **CI run** | https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/runs/45033572431 |
| **Result** | ✅ All three jobs passed |

## Final CI result (run #9)

| Job | Environment | Result | Tests |
|---|---|---|---|
| B2FCore (Linux) | `swift:6.0-noble` container, Swift 6.0 | ✅ success | 62 / 62 passed |
| B2FCore (macOS, with DEFLATE) | macOS 15 runner, Xcode 16.4 | ✅ success | 62 / 62 passed |
| iOS app | macOS 15, Xcode 16.4, iPhone 16 Pro simulator (iOS 18.5) | ✅ success | Unit/integration: 23 passed, 1 skipped, 0 failed · UI: 6 / 6 passed |

### iOS test detail

| Suite | Tests | Result |
|---|---|---|
| AIProviderFactoryTests | 1 | ✅ |
| AnkiExportServiceTests | 1 | ✅ export → `.apkg` → re-import with full deck hierarchy |
| ImportTests | 5 | ✅ text PDF, scanned PDF, DOCX, TXT, unsupported type, scan → PDF |
| OCRTests | 4 | ✅ real Vision OCR on rendered pages, structure detection, preprocessing, rotation |
| PersistenceIntegrationTests | 8 | ✅ SwiftData round-trips, study queue, review logging, cascade delete, background writer |
| PipelineIntegrationTests | 2 | ✅ end-to-end book → lessons → cards; free-plan card limit |
| SecurityTests | 2 | ✅ 1 passed (AES-GCM incl. tamper detection) · ⏭ 1 skipped (see below) |
| StoreKitTests | 1 | ✅ local StoreKit purchase unlocks Premium |
| UI tests | 6 | ✅ library, study flow, lesson + export sheet, search, accessibility audit, launch performance (2.6 s ± 8.8 % on CI simulator) |

---

## Path to green: 9 CI runs

| Run | Commit | Linux | macOS | iOS | What failed → what was fixed |
|---|---|---|---|---|---|
| 1 | `3e5ff36` | ❌ | ❌ | ❌ | Swift type checker gave up on two bit-packing expressions (`ZipArchive` DOS timestamps, `SHA1` output). Split into explicitly typed steps. |
| 2 | `ed4d4a7` | ❌ | ❌ | ❌ | Exclusivity violation: `currentLesson?.pageRange = currentLesson!…` in `LessonStructureDetector`. Read into a local first. |
| 3 | `a21ee14` | – | – | – | Cancelled by the next push (also included four app fixes from code review: `PrefixSequence.count`, long string interpolation, `Substring` in `String(localized:)`, tuple sort). |
| 4 | `d885f22` | ✅ | ✅ | ❌ | iOS: `NormalizedRect` ambiguous with the iOS 18 Swift Vision API type. Qualified as `B2FCore.NormalizedRect`. |
| 5 | `1aaa0b3` | ✅ | ✅ | ❌ | **App compiled.** 4 test failures: Keychain `-34018` (×2), OCR structure test, dashboard contrast audit. |
| 6 | `d5504f1` | ✅ | ✅ | ❌ | Keychain tests fixed (injectable key; signed-only test skipped when entitlement missing). Diagnostics added, but CI log formatter showed only first line. |
| 7 | `ac491d3` | ✅ | ✅ | ❌ | Single-line diagnostics revealed both root causes (below). |
| 8 | `78b681a` | ✅ | ✅ | ❌ | OCR test passing. Audit then pinpointed five invisible buttons. |
| 9 | `5923f78` | ✅ | ✅ | ✅ | Invisible shortcut buttons replaced with iPad menu commands. **All green.** |

---

## Product bugs found and fixed by CI

These were genuine defects, not test problems:

1. **Vocabulary lists missed on real-looking pages** (`LayoutAnalyzer`). With textbook line spacing (~1× line height), each "word – meaning" line became its own paragraph, so no vocabulary list was detected. Now: runs of 2+ "term – meaning" lines form a list regardless of spacing, lines starting with a section keyword ("Grammar:", "Exercise") start a new block, and the paragraph-gap threshold is 1.2× line height. This directly affects card quality on real books.
2. **Low-contrast dashboard text** (`StatTile`). Values were drawn in orange/green/red and titles in secondary grey on a grey card – failing or nearly failing WCAG contrast. Text now uses primary label colours; colour is kept on the icons.
3. **Invisible keyboard-shortcut buttons** (`RootView`). Five zero-opacity buttons sat behind the main UI to provide ⌘1–⌘5. Replaced by a proper "Go" `CommandMenu`, which also lists the shortcuts in the iPad ⌘-hold overlay. Tab selection moved to `AppModel`.
4. **`NSLock` used directly in an async function** (`PDFPageSource`) – would be an error in Swift 6. Lock now only taken in a synchronous helper.

---

## Things that pass but need attention

| Item | Detail | Recommendation |
|---|---|---|
| **Keychain / Secure Enclave test skipped in CI** | CI builds with `CODE_SIGNING_ALLOWED=NO`; the simulator returns `errSecMissingEntitlement` (-34018). `SecureSecretStore` round-trip therefore has **not been executed anywhere yet**. The test skips only for that exact error. | Run the test suite locally with signing (⌘U in Xcode with your team set), or add a signed CI job. |
| **Accessibility audit scope** | The audit ignores: (a) contrast for elements under the translucent tab bar or off-screen – measured against scrolled content, not our colours; (b) Swift Charts axis text, which has no accessibility element (charts expose per-bar labels/values instead); (c) elements of type `other`. Everything else must pass. | Re-check the tab bar and charts manually with Accessibility Inspector on a device. |
| **StoreKit test takes ~5.5 minutes** | `testPurchaseUnlocksPremium` passes but spent 327 s (285 s in an earlier run), most likely waiting inside StoreKit's local test session. It accounts for most of the iOS job's duration. | Investigate before adding more StoreKit tests (e.g. instrument `loadProducts` / `purchase` timing, or use `SKTestSession` per test with `resetToDefaultState`). |
| **Study-flow UI test is conditional** | `testStudyFlowRatesCard` rates a card if one is due, otherwise asserts the "All done!" state – it passed, but the log does not show which branch ran. | Seed one card due today in `PreviewData` so the rating path is always exercised. |
| **Compiler warnings** | `ImagePreprocessor` is `Sendable` but holds a `CIContext` (error under Swift 6). | Make it a `final class` with `@unchecked Sendable` (CIContext is thread-safe) or `@preconcurrency import CoreImage`, before moving to Swift 6 mode. |

## Not covered by CI

CI proves the code compiles and the tested paths behave on a simulator. It does **not** verify:

- **Apple Intelligence provider** – compiled out on Xcode 16.4 (`#if canImport(FoundationModels)`); needs an Xcode 26 build and an Apple Intelligence device.
- **Live AI calls** – OpenAI / Azure / proxy requests are tested for request shape and decoding with mocks only.
- **iCloud sync** – CloudKit is off in tests (unsigned builds, in-memory stores).
- **Camera scanner, microphone/speech recognition, audio playback** – require a real device.
- **Exported decks in real Anki clients** – `.apkg` files are validated by our own reader and SQLite checks, not yet opened in Anki desktop, AnkiMobile or AnkiDroid.
- **iPad layout and the new ⌘1–⌘5 "Go" menu** – UI tests run on iPhone only.
- **Persian/Arabic OCR quality** – OCR tests use English pages.

These remain on the TestFlight checklist in `RELEASE_PACKAGE.md`.

---

## Reproduce locally

```bash
git clone https://github.com/faezeh-kazemzadeh/Book2Fkashcard.git
cd Book2Fkashcard && git checkout claude/book2flashcards-ai-pro-e8mlhi

# Core package (macOS or Linux; Linux needs libsqlite3-dev)
swift test --package-path Packages/B2FCore

# iOS app
brew install xcodegen
B2F_TEAM_ID=YOURTEAMID xcodegen generate
xcodebuild test -project Book2Flashcards.xcodeproj -scheme Book2Flashcards \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```
Run without `CODE_SIGNING_ALLOWED=NO` (signed) to also execute the Keychain test.
