# Final Release Report – Book2Flashcards AI Pro 1.0

_Status as of 22 Nov 2026 · branch `claude/book2flashcards-ai-pro-e8mlhi` · PR [#1](https://github.com/faezeh-kazemzadeh/Book2Fkashcard/pull/1) → `main`_

## TL;DR

The **code is complete, compiles, and passes all automated tests** on Linux, macOS and the iOS simulator. **Nothing has yet been done on the Apple side** (signing, App ID, iCloud container, App Store Connect, in-app purchases), and **the app has never run on a physical device**. Those are the gating items for TestFlight, not code.

| | Readiness |
|---|---|
| **TestFlight (internal testers)** | **35 %** |
| **App Store submission** | **22 %** |

Both percentages are computed from the weighted checklists in [§5](#5-readiness-scores) – they measure work remaining, not code quality.

---

## 1. Current build status

**✅ All three jobs green on the PR head** – [run #14](https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/runs/45035221843) on commit `fa3bd61` (same source code as the first green run, [#9](https://github.com/faezeh-kazemzadeh/Book2Fkashcard/actions/runs/45033572431) on `5923f78`). Commits after `fa3bd61` change documentation only.

| Job | Toolchain | Last result |
|---|---|---|
| B2FCore (Linux) | Swift 6.0 (`swift:6.0-noble`) | ✅ pass |
| B2FCore (macOS) | Xcode 16.4 | ✅ pass |
| iOS app – build + unit/integration + UI tests | Xcode 16.4, iPhone 16 Pro simulator, iOS 18.5 | ✅ pass |

- **Compiler warnings:** one class – `ImagePreprocessor` stores a non-`Sendable` `CIContext` (error only in Swift 6 language mode; the project uses Swift 5 mode).
- **Not built by CI:** the Apple Intelligence provider (`#if canImport(FoundationModels)` – needs Xcode 26) and a **Release archive** (CI builds Debug for the simulator, unsigned).
- History of the 9 runs it took to reach green, and every fix: [BUILD_REPORT.md](BUILD_REPORT.md).

---

## 2. Passed tests summary

**92 distinct tests · 154 executions: 153 passed, 1 skipped, 0 failed** (62 core tests run on both Linux and macOS, plus 24 app unit/integration and 6 UI tests on iOS).

| Area | Tests | What is proven |
|---|---|---|
| Spaced repetition (FSRS-5, SM-2) | 15 | Learning steps, graduation, interval growth, lapses, hard ≤ good < easy, SM-2 → FSRS seeding, 90 % retention at due date |
| Anki format | 9 | `.apkg` written as a valid Anki schema-11 SQLite collection; deck tree, tags, checksum (`csum`), scheduling, media map; round-trip import incl. stable note IDs; `.csv`/`.txt` with Anki headers; clear error for newest zstd format; cloze/basic notes |
| ZIP, SHA-1, CRC-32 | 4 | Known test vectors; stored + DEFLATE archives; UTF-8/Persian file names |
| OCR layout & lesson detection | 5 | Headings, lesson titles, tables, vocabulary lists, grammar boxes, exercises, low-confidence flags; Unit › Lesson › Section outline; page-window fallback; Persian OCR language plan |
| Text normalisation | 4 | Persian/Arabic orthography, ZWNJ and digit folding, HTML stripping/escaping, edit distance, script detection |
| Quality filter | 4 | Rejects articles, stop words, very common words, numbers, OCR noise, proper nouns, inflected duplicates; ranks curated/academic words first |
| AI layer | 8 | Strict JSON-schema request shape (OpenAI and Azure), vision input, tolerant decoding, filtering of AI output, offline fallback, auth errors surfaced, lesson-title refinement |
| Quizzes & search | 7 | Multiple choice integrity, fill-in-the-blank, typing tolerance, spoken grading, grammar challenge; prefix/diacritic/Persian-normalised search |
| Documents, analytics, plan limits | 6 | DOCX headings/tables/page breaks, EPUB spine & metadata, TXT paging; streaks/retention/heatmap; free vs. premium gates |
| **iOS:** persistence | 8 | SwiftData round-trip, study queue limits & priority, review logging, due cards, scope filter, cascade delete, background writer, Anki deck → book hierarchy |
| **iOS:** OCR (real Vision) | 4 | Rendered textbook page → text + structure; advanced preprocessing; rotated page; device language support |
| **iOS:** importers | 5 | Text PDF uses text layer; image-only PDF treated as scanned; DOCX/TXT; unsupported type; scan → PDF |
| **iOS:** pipeline | 2 | Book → lessons → AI cards (mocked) with duplicate filtering; free plan stops at 500 cards and shows paywall |
| **iOS:** Anki export service, StoreKit, security, AI factory | 5 (incl. the skipped test) | Book export re-imports with hierarchy; local StoreKit purchase unlocks Premium; AES-GCM incl. tamper detection; non-HTTPS/keyless provider rejected |
| **iOS UI** | 6 | Library, study flow, lesson → export sheet, search, accessibility audit (Dynamic Type, contrast, element detection), launch time (2.6 s on CI simulator) |
| **Skipped** | 1 | Secure Enclave/Keychain secret round-trip – needs a signed build (CI is unsigned) |

---

## 3. Remaining risks

Ranked by impact on a successful 1.0.

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| 1 | **Never run on a real device.** Camera scanner, microphone/speech, TTS audio, Secure Enclave, memory on large books are untested on hardware. | High | Certain to surface *something* | Day-1 device smoke test (§4) before any tester sees it |
| 2 | **No production AI backend.** Without the proxy + a token service, testers must paste their own OpenAI/Azure key; without any AI, cards come only from the book's vocabulary lists (far fewer). | High | Certain | Deploy `Backend/ai-proxy` and a token issuer, or ship TestFlight as bring-your-own-key and say so |
| 3 | **iCloud sync untested.** SwiftData + CloudKit model never mirrored; first real sync creates the schema. Schema mistakes become permanent once deployed to Production. | High | Medium | Two-device sync test in Development before deploying the schema |
| 4 | **Keychain / Secure Enclave code path unexecuted.** API-key storage has only been tested indirectly. | Medium | Low–Medium | Run the test suite signed (⌘U) once |
| 5 | **Exported decks not opened in real Anki clients.** Validated only against our own reader and the schema. | Medium | Low–Medium | Import a book export into Anki desktop, AnkiMobile, AnkiDroid |
| 6 | **OCR quality on real books, especially Persian/Arabic.** Tests use rendered English pages; Vision has no Persian model. | Medium | Medium | Test 3–5 real textbooks (incl. one Persian) and tune `LayoutAnalyzer` thresholds |
| 7 | **AI output quality** (translations, IPA, distractors) is unmeasured; prompts tested only for request shape. | Medium | Medium | Review ~100 generated cards per language before external testing |
| 8 | **Apple Intelligence provider never compiled.** | Low | Medium | Build once with Xcode 26; hide the option if it fails |
| 9 | **StoreKit test takes ~5.5 min** in CI (passes). | Low (CI cost) | – | Investigate before adding more StoreKit tests |
| 10 | **Copyright perception in App Review** (users import commercial textbooks). | Medium | Low | Terms restrict use to owned material; nothing is shared publicly; explain in review notes |
| 11 | **Swift 6 migration debt** (Sendable warnings). | Low | – | Stay on Swift 5 mode for 1.0 |

---

## 4. Manual testing checklist

Run on **one small iPhone (SE / mini)**, **one large iPhone**, and **one iPad with a hardware keyboard**. Tick each on every device unless marked.

### A. First launch & settings
- [ ] Onboarding appears once; language/level choices persist after relaunch
- [ ] Settings › AI: save an OpenAI key → "Save & Test Connection" succeeds; wrong key shows a clear error
- [ ] Azure OpenAI and Apple Intelligence options behave as labelled (Apple Intelligence only on supported devices)

### B. Import & OCR
- [ ] Import a **text PDF** (≥ 100 pages) – progress shown, memory stays reasonable, lessons detected
- [ ] Import a **scanned PDF** – OCR runs, low-confidence pages flagged
- [ ] **Camera scan** 5+ pages in good and poor light – auto-crop, shadows removed, text recognised
- [ ] **Photos** (multiple) and a **screenshot**
- [ ] **EPUB**, **DOCX**, **TXT** (including a Persian UTF-8 and a Windows-1256 file)
- [ ] Files from **iCloud Drive, OneDrive, Dropbox, Google Drive** via the Files picker
- [ ] "Open in Book2Flashcards" from another app (PDF, `.apkg`)
- [ ] Background the app mid-import; return – import continues or can be resumed
- [ ] Page review: image shows, orange boxes on weak blocks, edit + save; "Rebuild lessons" regenerates cards

### C. Cards & quality
- [ ] Vocabulary cards contain translation, definition, IPA, example, synonyms/antonyms
- [ ] No cards for articles, "the/and/go"-type words, or duplicates
- [ ] Grammar, reading and speaking cards present and sensible
- [ ] Card editor saves every field; "Explain with AI" works (Premium)

### D. Study & quizzes
- [ ] Study session: show answer (tap / Space), rate 1–4, interval previews correct, learning cards return in-session
- [ ] Switch FSRS ↔ SM-2 – history kept, intervals change sensibly
- [ ] Audio: British vs American, all 5 speeds, autoplay toggle
- [ ] All 9 quiz types, including **speaking** (microphone permission prompt, transcript graded)

### E. Anki
- [ ] Export **one lesson**, **selected lessons**, **whole book** with audio + scheduling
- [ ] Open each `.apkg` in **Anki desktop**, **AnkiMobile**, **AnkiDroid**: deck tree `Book::Unit::Lesson::Vocabulary`, tags, audio play
- [ ] Re-export after editing a card → re-import in Anki **updates** the note (no duplicate)
- [ ] Import an existing `.apkg`, a `.csv`, an Anki `.txt` export

### F. Offline & sync
- [ ] Airplane mode: study, review, view scanned pages, export deck – all work
- [ ] iCloud Sync on two devices (same Apple Account): book, cards, reviews, settings appear on the second device; edits sync back
- [ ] Turn sync off/on – no data loss

### G. Purchases (sandbox account)
- [ ] Free limits: 4th book and 501st card open the paywall
- [ ] Buy monthly, yearly (trial shown), lifetime; Restore Purchases; cancel/expire → features re-lock, data kept

### H. Accessibility & localisation
- [ ] VoiceOver: import → study → export completely operable
- [ ] Largest Dynamic Type: no clipped text on any screen
- [ ] Device language Persian: UI mirrored; Persian card text right-to-left inside English UI
- [ ] iPad: ⌘1–⌘5 ("Go" menu), Space/1–4 in study, split view and Stage Manager resizing

### I. Stability
- [ ] No crashes or hangs across the above; check Xcode Organizer after TestFlight sessions

---

## 5. Readiness scores

Each item is weighted by how much it blocks the milestone; partially done items get partial credit.

### TestFlight (internal testers) – **35 %**

| Item | Weight | Done | Credit | Evidence |
|---|---:|---:|---:|---|
| Code complete, compiles, automated tests green | 25 | 100 % | 25 | CI runs #9+ |
| Privacy manifest, permission strings, export-compliance flag | 5 | 100 % | 5 | `PrivacyInfo.xcprivacy`, `Info.plist` |
| AI usable by testers | 10 | 50 % | 5 | BYOK and offline mode work; no hosted proxy |
| Apple Developer setup (App ID + capabilities, iCloud container, keychain group) | 15 | 0 % | 0 | – |
| Signed Release archive builds and validates | 15 | 0 % | 0 | Never archived |
| App Store Connect app record + sandbox IAP products | 10 | 0 % | 0 | – |
| Real-device smoke test (§4 A–D on one device) | 20 | 0 % | 0 | – |
| **Total** | **100** | | **35** | |

### App Store submission – **22 %**

| Item | Weight | Done | Credit | Evidence |
|---|---:|---:|---:|---|
| TestFlight readiness (above) | 40 | 35 % | 14 | |
| Store metadata: description, subtitle, keywords, promo text | 5 | 100 % | 5 | `docs/AppStore/Metadata.md` |
| Privacy policy & terms published and legally reviewed | 10 | 30 % | 3 | Drafts with placeholders |
| Final app icon | 5 | 0 % | 0 | Placeholder |
| Screenshots (6.9" iPhone, 13" iPad) and optional preview | 10 | 0 % | 0 | Plan only |
| CloudKit schema deployed to Production after sync test | 5 | 0 % | 0 | |
| Production AI backend (proxy + token service, quotas) | 10 | 0 % | 0 | Reference worker only |
| Full manual checklist (§4) passed on 3 devices, beta feedback fixed | 15 | 0 % | 0 | |
| **Total** | **100** | | **22** | |

---

## 6. Exact next steps for release

### Step 1 – Merge (today)
1. Review and merge [PR #1](https://github.com/faezeh-kazemzadeh/Book2Fkashcard/pull/1) into `main`.

### Step 2 – Apple Developer setup (≈ 1 hour)
2. Decide the final bundle ID. If not `com.book2flashcards.pro`, replace it in `project.yml`, `App/Resources/Book2Flashcards.entitlements`, `AppConstants` (`PersistenceController.swift`), `StoreManager.ProductID` and `Products.storekit`.
3. developer.apple.com › Identifiers: create the App ID with **iCloud (CloudKit)**, **Push Notifications**, **In-App Purchase**, **Data Protection**.
4. Create the iCloud container `iCloud.com.book2flashcards.pro` and assign it to the App ID.

### Step 3 – First signed build on a device (≈ ½ day)
5. `export B2F_TEAM_ID=<your team>` → `xcodegen generate` → open in Xcode 16.4+.
6. Run on your iPhone. Do checklist §4 A–D. Fix anything blocking.
7. Run the test suite signed (⌘U) to execute the skipped Keychain test.

### Step 4 – Sync, purchases, Anki (≈ 1 day)
8. Turn on iCloud Sync on two devices; complete §4 F. Then **CloudKit Console › Deploy Schema Changes to Production**.
9. App Store Connect: create the app record and the three products (`…premium.monthly`, `…premium.yearly` with 1-week trial, `…premium.lifetime`); create a sandbox tester; complete §4 G.
10. Export decks and complete §4 E in Anki desktop, AnkiMobile and AnkiDroid.

### Step 5 – AI for testers (≈ ½–2 days)
11. Either: deploy `Backend/ai-proxy` (Cloudflare: `wrangler deploy`, secrets `OPENAI_API_KEY`, `TOKEN_SIGNING_KEY`, KV `QUOTA`) plus a token-issuing endpoint, and set `B2F_PROXY_BASE_URL`;
    or: ship TestFlight as bring-your-own-key and tell testers in "What to Test".
12. Review ~100 generated cards in each language you support; adjust `PromptLibrary` if needed.

### Step 6 – TestFlight internal (→ 100 % TestFlight readiness)
13. Product › Archive (Release) → Validate → Upload.
14. Answer export compliance (no non-exempt encryption), add internal testers, write "What to Test".
15. Collect a week of feedback and crash reports; fix.

### Step 7 – App Store submission
16. Replace the app icon with final artwork (1024×1024, no transparency).
17. Fill placeholders in `PRIVACY_POLICY.md` / `TERMS_OF_SERVICE.md`, get legal review, publish at the URLs in `AppConstants`.
18. Produce screenshots per `docs/AppStore/Metadata.md` (6.9" iPhone, 13" iPad; seed with `-UITestSeedData -SkipOnboarding -PremiumOverride`).
19. Complete §4 on all three devices; external TestFlight (Beta App Review) optional but recommended.
20. Enter metadata, App Privacy answers, age rating; attach the IAPs to the version; paste review notes from `docs/APP_STORE_SUBMISSION.md` with a working demo token or instructions.
21. Submit for review; release with phased rollout.
