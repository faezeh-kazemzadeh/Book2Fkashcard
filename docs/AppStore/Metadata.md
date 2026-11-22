# App Store Package – Book2Flashcards AI Pro

All character counts were checked against App Store Connect limits.

## Name (≤ 30)
**Book2Flashcards AI Pro** (22)

## Subtitle (≤ 30)
**Textbooks to Anki flashcards** (28)

## Promotional Text (≤ 170, editable without review)
> New: scan any textbook page and get study-ready vocabulary, grammar and reading cards in seconds – with IPA, audio and one-tap Anki export. (139)

## Keywords (≤ 100, comma-separated, no spaces after commas)
```
ocr,vocabulary,ielts,toefl,srs,fsrs,persian,farsi,german,french,spanish,scanner,exam,words,quiz
```
(95) — "anki", "flashcards", "book", "AI" and "pro" are omitted because Apple already indexes words in the name and subtitle.

## Description (≤ 4000)

Turn the language books you already own into serious study material.

Book2Flashcards AI Pro reads your textbook – PDF, scanned pages, EPUB, Word files, photos or screenshots – finds every unit and lesson, and builds high-quality flashcards and quizzes from what each lesson actually teaches. Study them with a modern spaced-repetition scheduler, or export the decks to Anki with one tap.

SCAN OR IMPORT ANYTHING
• Camera scanner with automatic page detection, cropping, de-skewing and shadow removal
• Batch-scan whole chapters and save them as a PDF
• Import from Files, iCloud Drive, OneDrive, Dropbox and Google Drive
• PDF (text or scanned), EPUB, DOCX, TXT, images and screenshots

ACCURATE OCR FOR LANGUAGE BOOKS
• English, German, French, Spanish, Arabic and Persian
• Detects headings, lesson titles, tables, vocabulary lists, grammar boxes and exercises
• Flags low-confidence text so you can check it against the page

LESSONS, NOT JUST TEXT
Book2Flashcards recognises units, lessons and sections (“Unit 3 › Lesson 3B › Vocabulary”) and keeps that structure everywhere: in the app, in quizzes and in your Anki decks.

FLASHCARDS WORTH LEARNING
• Vocabulary: translation, definition, IPA, pronunciation, example sentence, synonyms and antonyms
• Grammar: rule, formula, examples and the mistakes learners really make
• Reading comprehension and speaking prompts with model answers
• Smart quality filter: no articles, no “the/and/go”, no duplicates, and exam vocabulary first

STUDY SMARTER
• FSRS (the modern open-source scheduler) or classic SM-2
• See your predicted recall and the next interval on every button
• 9 quiz types: multiple choice, fill in the blank, listening, speaking, translation, typing, vocabulary and grammar challenges, reading comprehension
• British or American pronunciation at 0.5×–1.5× speed

ANKI, DONE RIGHT
• Export a lesson, several lessons or the whole book as .apkg
• Keeps deck hierarchy, tags, audio and images
• Import your existing Anki decks (.apkg, .csv, .txt)

YOUR DATA, YOUR DEVICE
• Works offline: study, review, view scanned pages and export decks without a connection
• iCloud sync across iPhone and iPad (Premium)
• Page images are encrypted; your own AI keys are protected by the Secure Enclave
• No ads, no tracking

PREMIUM
Free: 3 books, 500 flashcards and standard OCR.
Premium: unlimited books and cards, advanced OCR, AI explanations, Anki export and iCloud sync. Monthly, yearly (with free trial) or lifetime.

Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage them in your App Store account settings.
Terms: https://book2flashcards.app/terms · Privacy: https://book2flashcards.app/privacy

## What's New (1.0)
First release: OCR import, lesson detection, AI flashcards, FSRS study, quizzes, Anki import/export and iCloud sync.

## Categories
Primary: **Education** · Secondary: **Productivity**

## Age Rating
4+ (no objectionable content; user-generated content is private to the user).

## App Privacy ("nutrition label")
| Data type | Collected | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| User Content – Other (book text sent for AI generation) | Yes | No | No | App Functionality |
| Purchases | Yes (by Apple) | No | No | App Functionality |
Everything else: **Not collected**. iCloud data lives in the user's private CloudKit database and is not accessible to the developer.

---

## Screenshots Plan

Sizes required: 6.9" iPhone (1320×2868), 13" iPad (2064×2752). Generate from the simulator with `-UITestSeedData -SkipOnboarding -PremiumOverride` for consistent content, then frame with captions (top, bold, ≤ 6 words).

| # | Screen | Caption | Notes |
|---|---|---|---|
| 1 | Camera scanner over a textbook page, page outline visible | **Scan your textbook** | Hero shot; strongest value proposition |
| 2 | Book detail: Unit › Lesson list with card counts | **Lessons found automatically** | Show English File–style "1A/1B" |
| 3 | Vocabulary card back: translation, IPA, example, synonyms | **Cards worth learning** | Persian translation visible (RTL) |
| 4 | Grammar card: formula + common mistakes | **Grammar, explained** | |
| 5 | Study screen with rating buttons + intervals | **Smart reviews with FSRS** | |
| 6 | Anki export sheet with deck hierarchy | **One-tap Anki export** | |
| 7 | Dashboard with streak, retention and heatmap | **See your progress** | |
| 8 | Quiz (multiple choice / speaking) | **9 quiz types** | |
| 9 (iPad) | Split view: page image + OCR text side by side | **Check every page** | iPad only |

Localise captions for fa, de, fr, es, ar storefronts (RTL screenshots mirrored for fa/ar).

## App Preview Video Plan (15–30 s, portrait, no device frame, no audio dependency)

| Time | Shot | On-screen text |
|---|---|---|
| 0–3 s | Phone camera captures a textbook page; outline snaps to page | "Scan any page" |
| 3–7 s | Processing progress → lesson list appears (Unit 1 › 1A, 1B) | "Lessons detected" |
| 7–13 s | Scroll through generated vocabulary/grammar cards | "AI flashcards" |
| 13–18 s | Study session: flip card, tap Good, interval shown | "Learn with FSRS" |
| 18–23 s | Export sheet → Share .apkg → Anki opens with deck tree | "Export to Anki" |
| 23–27 s | Dashboard heatmap + streak | "Track your progress" |
| 27–30 s | App icon + name | "Book2Flashcards AI Pro" |

Record with `xcrun simctl io booted recordVideo`, 30 fps, captions burned in, poster frame at 0:08 (cards).

## Metadata & ASO Strategy

1. **Keyword focus.** Target intent queries ("anki ocr", "scan vocabulary", "ielts vocabulary", "persian english flashcards"). Name + subtitle carry *Anki, flashcards, textbooks, AI*; the keyword field carries everything else without repeating them.
2. **Localisation as ranking surface.** Ship localized metadata for en-US, en-GB, fa (via the Arabic/Persian-reading storefronts), de-DE, fr-FR, es-ES/es-MX, ar-SA. Each locale's keyword field is indexed separately in many storefronts – use it for synonyms (e.g. de: "vokabeln,karteikarten,lernkarten").
3. **Conversion.** First two screenshots must show the scan → cards transformation. Keep the promo text seasonal (exam seasons: IELTS/TOEFL in spring, back-to-school in September).
4. **Ratings.** Ask with `SKStoreReviewController`/`requestReview` only after a positive moment (finishing a session with ≥ 80% recall, third day of streak), max 3×/year.
5. **In-app events.** "30-day vocabulary challenge", "Exam sprint" – drive re-engagement and search visibility.
6. **Custom product pages** per audience (IELTS learners, Persian speakers, German learners) linked from ads and social posts.
7. **Measure.** Track impressions → product page views → installs in App Analytics; A/B test icon and the first screenshot with Product Page Optimization (90-day cycles).
