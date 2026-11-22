# Book2Flashcards AI Pro

An iPhone and iPad app that turns language-learning books (PDF, scanned pages, EPUB, DOCX, TXT, photos, camera scans) into structured lessons, high-quality flashcards and quizzes, with FSRS/SM-2 spaced repetition and full Anki import/export.

## Repository layout

```
project.yml                  XcodeGen spec (generates Book2Flashcards.xcodeproj)
Packages/B2FCore/            Platform-independent core (builds & tests on iOS, macOS, Linux)
  Sources/B2FCore/
    Models/  SRS/  Layout/  Quality/  AI/  Anki/  Quiz/  Search/  Analytics/
    Entitlements/  OCR/  Import/  Util/
  Tests/B2FCoreTests/        Unit tests: FSRS, SM-2, Anki round-trip, ZIP, OCR layout,
                             lesson detection, quality filter, AI decoding, quizzes, search
App/
  Sources/
    App/          Entry point, AppModel (composition root)
    Persistence/  SwiftData entities, repository, background writer, preview data
    Security/     Keychain, Secure Enclave secret wrapping, AES-GCM file store
    OCR/          CoreImage/Vision preprocessing and text recognition
    Import/       File importers (PDF/EPUB/DOCX/TXT/images)
    Scanner/      VisionKit document camera, scan → PDF
    Processing/   Book processing pipeline
    AI/           Provider factory, Apple Intelligence provider
    Audio/        TTS playback, .m4a rendering for Anki, speech recognition
    Store/        StoreKit 2
    Sync/         CloudKit/network status
    Settings/     Preferences (iCloud key-value synced)
    Anki/         Export/import services
    Search/       Search index builder
    Features/     SwiftUI views and view models
  Resources/      Info.plist, entitlements, privacy manifest, assets, Localizable (en, fa), StoreKit config
  Tests/          Integration tests: persistence, OCR, importers, pipeline, Anki, StoreKit, security
  UITests/        UI tests incl. accessibility audit and launch performance
Backend/ai-proxy/ Reference AI proxy (keeps provider keys off devices)
docs/             Architecture, deployment, App Store submission, metadata, privacy policy, terms
.github/workflows CI: core tests on Linux & macOS, iOS build + tests on simulator
```

## Quick start

```bash
brew install xcodegen
export B2F_TEAM_ID=YOURTEAMID
xcodegen generate
open Book2Flashcards.xcodeproj        # run the "Book2Flashcards" scheme

swift test --package-path Packages/B2FCore   # fast core tests (macOS or Linux)
```

Configure AI in the app under **Settings › AI** (OpenAI key, Azure OpenAI endpoint/deployment/key, the proxy, or Apple Intelligence on iOS 26 devices). Without AI, the app still builds cards from the book's own vocabulary lists and grammar boxes.

## Feature map

| Requirement | Where |
|---|---|
| Import PDF/scanned PDF/EPUB/DOCX/TXT/images/camera; Files, iCloud Drive, OneDrive, Dropbox, Google Drive (File Provider) | `App/Sources/Import`, `Scanner`, `B2FCore/Import` |
| OCR with border/perspective, shadow, noise, skew, contrast, rotation; multi-language; confidence flags | `App/Sources/OCR`, `B2FCore/OCR/OCRLanguagePlan.swift` |
| Headings, lesson titles, tables, vocabulary lists, grammar boxes, exercises | `B2FCore/Layout/LayoutAnalyzer.swift` |
| Units / lessons / sections | `B2FCore/Layout/LessonStructureDetector.swift`, `AI/FlashcardGenerator.swift` (`AILessonRefiner`) |
| Vocabulary, grammar, reading, speaking cards | `B2FCore/AI/PromptLibrary.swift`, `FlashcardGenerator.swift` |
| Quality filter | `B2FCore/Quality` |
| Anki .apkg export (lesson/lessons/book, deck tree, tags, audio, images) | `B2FCore/Anki/AnkiPackageWriter.swift`, `App/Sources/Anki` |
| Anki import (.apkg/.csv/.txt) | `AnkiPackageReader.swift`, `AnkiTextImporter.swift`, `AnkiNoteMapper.swift` |
| AnkiConnect / desktop sync preparation | `AnkiConnectClient.swift` (`AnkiSyncTarget`) |
| SM-2 and FSRS-5, retention, prediction | `B2FCore/SRS`, `B2FCore/Analytics` |
| 9 quiz types | `B2FCore/Quiz`, `Features/Quiz` |
| Audio (UK/US, 0.5–1.5×), IPA | `App/Sources/Audio`, AI prompts |
| Dashboard with heatmap | `Features/Dashboard` |
| Search (books, OCR, lessons, vocab, definitions, examples, grammar) | `B2FCore/Search`, `App/Sources/Search` |
| OpenAI, Azure OpenAI, local (future), Apple Intelligence | `B2FCore/AI/AIProvider.swift`, `ChatCompletionsProvider.swift`, `App/Sources/AI` |
| Offline-first + iCloud sync | `Persistence/PersistenceController.swift`, `Sync`, `Settings/AppSettings.swift` |
| StoreKit 2 free/premium | `Store/StoreManager.swift`, `B2FCore/Entitlements/FeatureGate.swift` |
| Security | `App/Sources/Security`, `Backend/ai-proxy` |
| Accessibility (VoiceOver, Dynamic Type, RTL, keyboard) | `Features/*` (`AdaptiveText`, shortcuts, accessibility labels), UI accessibility audit |

## Docs
- [Architecture](docs/ARCHITECTURE.md)
- [Deployment guide](docs/DEPLOYMENT.md)
- [App Store submission guide](docs/APP_STORE_SUBMISSION.md)
- [App Store metadata, screenshots, preview video, ASO](docs/AppStore/Metadata.md)
- [Privacy policy](docs/AppStore/PRIVACY_POLICY.md) · [Terms of use](docs/AppStore/TERMS_OF_SERVICE.md)

## Known limitations
- Vision has no Persian model: Persian pages use the Arabic-script model plus orthography normalisation, and in advanced mode are re-transcribed by a vision-capable AI model. Accuracy on dense Persian pages is lower than for Latin scripts.
- Anki's newest zstd-compressed `.apkg` format (`collection.anki21b`) is detected but not decoded; users re-export with "Support older Anki versions".
- AnkiConnect push is a preview (same-network desktop only).
- The app icon is a placeholder.
