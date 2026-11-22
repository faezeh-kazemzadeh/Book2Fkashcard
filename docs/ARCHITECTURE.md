# Architecture

## Layers

```
┌──────────────────────────── App target (iOS 17+, SwiftUI) ────────────────────────────┐
│ Features/*  Views + @Observable view models (Dashboard, Library, Book, Study, Quiz,    │
│             Search, Settings, Paywall, Export)                                          │
│ App/AppModel  composition root: settings, store, sync monitor, factories                │
│ Processing  BookProcessingPipeline (actor) – import → OCR → layout → lessons → cards    │
│ OCR         ImagePreprocessor (CoreImage+Vision) · VisionOCREngine · OCRBackend protocol │
│ Import      DocumentImporter (PDFKit, EPUB, DOCX, TXT, images) · DocumentScannerView    │
│ Persistence SwiftData @Model entities · LibraryRepository (main) · LibraryWriter (actor) │
│ Security    KeychainStore · SecureSecretStore (Secure Enclave) · EncryptedFileStore     │
│ AI          AIProviderFactory · AppleOnDeviceProvider (Foundation Models)               │
│ Audio       SpeechService (AVSpeech) · AudioRenderer (.m4a for Anki) · SpeechRecognizer │
│ Store       StoreManager (StoreKit 2) · Sync: SyncStatusMonitor, NSUbiquitousKVStore    │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │ depends on
┌─────────────────────── Packages/B2FCore (iOS, macOS, Linux) ───────────────────────────┐
│ Models     CardContent, FlashcardDraft, LessonNode/BookOutline, LayoutBlock             │
│ SRS        FSRSScheduler (FSRS-5) · SM2Scheduler · SpacedRepetitionScheduler protocol  │
│ Layout     LayoutAnalyzer (blocks) · LessonStructureDetector (Unit › Lesson › Section)  │
│ Quality    VocabularyQualityFilter + WordLists                                         │
│ AI         AIProvider protocol · ChatCompletionsProvider (OpenAI/Azure/proxy) ·          │
│            PromptLibrary (strict JSON schemas) · FlashcardGenerator · AILessonRefiner   │
│ Anki       AnkiPackageWriter/Reader (.apkg) · AnkiTextImporter (.csv/.txt) ·            │
│            AnkiNoteMapper · AnkiConnectClient (AnkiSyncTarget)                           │
│ Quiz       QuizEngine (9 types, grading) · ReadingQuizGenerator                         │
│ Search     SearchIndex (TF-IDF, prefix, Persian/Arabic normalisation)                  │
│ Analytics  StudyAnalytics (retention, streaks, heatmap) · Entitlements: FeatureGate    │
│ Util       ZipArchive · SQLiteDatabase · SHA1/CRC32 · TextNormalizer                    │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

Everything that can be pure Swift lives in `B2FCore`, so ~70% of the logic is unit-tested on Linux and macOS in seconds without a simulator.

## Processing pipeline

1. **Import** – `DocumentImporter` returns a lazy `PageSource`. PDFs use their text layer when it is real text; scanned PDFs, photos and camera scans become images. Originals are sealed with AES-GCM and kept locally for reprocessing.
2. **OCR** – `ImagePreprocessor` (advanced mode: document segmentation + perspective correction, deskew from text baselines, shadow removal by background division, noise reduction, contrast, orientation search) → `VNRecognizeTextRequest` (accurate, language plan from `OCRLanguagePlan`) → `LayoutAnalyzer`. Low-confidence pages in advanced mode can be re-transcribed by a vision-capable model.
3. **Structure** – `LessonStructureDetector` builds Book › Unit › Lesson › Section using multilingual title patterns (Unit/Lesson/Lektion/Leçon/Lección/درس/الدرس, "1A" codes) and section keywords. Fallback: page windows. Optional `AILessonRefiner` cleans titles.
4. **Cards** – `FlashcardGenerator` ranks candidates with `VocabularyQualityFilter`, sends each lesson (chunked) to the AI provider with a strict JSON schema, decodes, filters again (stop words, very common words, lemma duplicates, empty answers) and tags with the hierarchy. Without AI, `HeuristicCardGenerator` uses the book's own vocabulary lists and grammar boxes.
5. **Persist** – every stage writes through `LibraryWriter`, so the UI updates live and interrupted imports resume (`resume(bookID:)`).

## AI provider abstraction

`AIProvider.complete(AIRequest) -> AIResponse` is the only contract. Implementations: `ChatCompletionsProvider` (OpenAI, Azure OpenAI, backend proxy), `AppleOnDeviceProvider` (iOS 26 Foundation Models), `LocalModelProvider` (placeholder for MLX/llama.cpp), `MockAIProvider` (tests/UI tests). `AIProviderFactory` maps settings → provider; views never know which one runs.

**Apple Intelligence readiness:** the on-device provider is wired today; Writing Tools work automatically in all `TextField`/`TextEditor` editors (card editor, page correction). A future `@Generable` structured-output path can replace the schema-in-prompt approach without touching callers.

## Spaced repetition

`SchedulingState` stores SM-2 fields (ease, interval) and FSRS fields (stability, difficulty) side by side. Switching algorithms is lossless: FSRS seeds stability/difficulty from SM-2 history on first use. Review logs (`ReviewLogEntity`) record rating, elapsed/scheduled days and predicted retrievability for analytics and future FSRS parameter optimisation.

## Anki

* **Export** – schema-11 `collection.anki2` (importable by every Anki client) built with SQLite, zipped with `media` map. Two note types (*Book2Flashcards Vocabulary*, *Book2Flashcards Basic*) with stable model IDs; note GUIDs derive from card UUIDs, so re-exporting updates notes instead of duplicating. Deck names use `::` hierarchy; tags are `B2F::Book::Unit::Lesson`.
* **Import** – `.apkg/.colpkg` (schema 11 and uncompressed schema 18; zstd `anki21b` is detected with a clear message), Anki text exports with `#` headers, generic CSV/TSV.
* **Sync preparation** – `AnkiSyncTarget` protocol with an `AnkiConnectClient` implementation (idempotent pushes keyed on the `B2FID` field). AnkiWeb has no public API; a self-hosted sync server target can implement the same protocol.

## Offline-first & sync

SwiftData is the source of truth. With iCloud Sync on, SwiftData mirrors to the user's **private** CloudKit database (`NSPersistentCloudKitContainer` underneath), which queues offline changes and exports them when the network returns. Preferences sync through `NSUbiquitousKeyValueStore`; subscriptions through StoreKit (Apple Account). Model rules for CloudKit: every attribute optional/defaulted, no unique constraints, optional inverse relationships.

## Security

| Asset | Protection |
|---|---|
| Page images | AES-256-GCM (`EncryptedFileStore`); key in iCloud Keychain (synchronizable) so synced pages decrypt on the user's devices |
| Imported originals | AES-256-GCM, local only |
| User API keys | Wrapped with a Secure Enclave P-256 key (ECDH + HKDF + AES-GCM), Keychain `ThisDeviceOnly` |
| Store files | Data Protection `CompleteUntilFirstUserAuthentication` (allows background sync) |
| Provider keys in production | Never in the binary – `Backend/ai-proxy` holds them server-side; app uses short-lived tokens |

## Scaling to millions of users

* All per-user data lives on device/in the user's CloudKit – the backend is only the stateless AI proxy (Workers scale horizontally; per-user KV quotas).
* Prompt + schema versions (`PromptLibrary.version`) allow server-side caching of generations for popular books keyed by content hash.
* Large books stream page-by-page (lazy `PageSource`, bounded image sizes), so memory stays flat.
