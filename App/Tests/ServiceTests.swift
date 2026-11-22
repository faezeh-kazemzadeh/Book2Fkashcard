import XCTest
import SwiftData
import StoreKitTest
import B2FCore
@testable import Book2Flashcards

/// End-to-end pipeline: text document → pages → lessons → AI cards (mocked) → store.
@MainActor
final class PipelineIntegrationTests: XCTestCase {
    func testTextBookProducesLessonsAndCards() async throws {
        let container = try PersistenceController.makeContainer(cloudSync: false, inMemory: true)
        let writer = LibraryWriter(modelContainer: container)
        let provider = MockAIProvider { request in
            if request.schema?.name == "lesson_outline" { return #"{"lessons":[]}"# }
            return #"{"vocabulary":[{"term":"itinerary","translation":"برنامه سفر","definition":"a planned route","ipa":"aɪˈtɪnərəri","pronunciation":"eye-TIN-uh-rer-ee","partOfSpeech":"noun","example":"Our itinerary includes Rome.","exampleTranslation":"برنامه سفر ما شامل رم است.","synonyms":["schedule"],"antonyms":[],"priority":"essential","confidence":0.9}],"grammar":[],"reading":[],"speaking":[]}"#
        }
        let pipeline = BookProcessingPipeline(dependencies: .init(
            writer: writer, ocr: OCREngine(), provider: provider, tier: .premium,
            options: GenerationOptions(), encryption: EncryptedFileStore(rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))))
        let pages = [
            ExtractedDocument.Page(text: "Unit 1\nLesson 1A Holidays\nVocabulary\nitinerary - برنامه سفر\nsouvenir - سوغاتی\nluggage - چمدان"),
            ExtractedDocument.Page(text: "Lesson 1B Airports\nReading\nPassengers wait for their delayed flights at the gate.")
        ]
        let document = ImportedDocument(title: "Travel English", author: "", kind: .txt,
                                        source: TextPageSource(pages: pages), originalData: nil, fileExtension: "txt")
        var finishedCards: Int?
        for await event in await pipeline.process(document) {
            if case .finished(_, let cards) = event { finishedCards = cards }
            if case .failed(let message) = event { XCTFail(message) }
        }
        XCTAssertEqual(finishedCards, 1, "duplicate 'itinerary' from lesson 1B must be filtered")
        let repository = LibraryRepository(context: container.mainContext)
        let book = try XCTUnwrap(repository.books().first)
        XCTAssertEqual(book.status, .ready)
        XCTAssertEqual(book.allLessons.map(\.title), ["Lesson 1A – Holidays", "Lesson 1B – Airports"])
        XCTAssertEqual(book.pageCount, 2)
    }

    func testFreePlanStopsAtCardLimit() async throws {
        let container = try PersistenceController.makeContainer(cloudSync: false, inMemory: true)
        let writer = LibraryWriter(modelContainer: container)
        // Pre-fill to the free limit.
        let filler = try await writer.importDeckCards(bookTitle: "Filler", target: .english, native: .persian,
            cards: (0..<FeatureGate.freeCardLimit).map { (deckPath: ["Filler"], draft: FlashcardDraft(content: .basic(BasicContent(front: "q\($0)", back: "a")))) })
        XCTAssertEqual(filler.imported, FeatureGate.freeCardLimit)

        let pipeline = BookProcessingPipeline(dependencies: .init(writer: writer, ocr: OCREngine(), provider: nil, tier: .free,
                                                                  options: GenerationOptions(), refineLessonsWithAI: false))
        let document = ImportedDocument(title: "B", author: "", kind: .txt,
                                        source: TextPageSource(pages: [.init(text: "Lesson 1\nVocabulary\nabandon - رها کردن\ncommute - رفت و آمد\nresilient - مقاوم")]),
                                        originalData: nil, fileExtension: "txt")
        var hitLimit = false
        for await event in await pipeline.process(document) {
            if case .limitReached = event { hitLimit = true }
        }
        XCTAssertTrue(hitLimit)
        XCTAssertEqual(LibraryRepository(context: container.mainContext).cardCount(), FeatureGate.freeCardLimit)
    }
}

@MainActor
final class AnkiExportServiceTests: XCTestCase {
    func testExportBookWritesPackageWithHierarchy() async throws {
        let container = try PersistenceController.makeContainer(cloudSync: false, inMemory: true)
        PreviewData.populate(container.mainContext)
        let repository = LibraryRepository(context: container.mainContext)
        let book = try XCTUnwrap(repository.books().first)
        let files = EncryptedFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let service = AnkiExportService(repository: repository, settings: AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                                        files: files)
        let result = try await service.export(scope: .book(book.id), options: .init(includeAudio: false, includeScheduling: true)) { _ in }
        XCTAssertEqual(result.noteCount, book.allCards.count)
        XCTAssertEqual(repository.exportCount(), 1)

        let imported = try AnkiPackageReader().read(packageAt: result.fileURL, mediaDestination: files.mediaDirectory)
        XCTAssertTrue(imported.deckNames.contains("English File Intermediate::Unit 1::Lesson 1A – Mood food::Vocabulary"))
        XCTAssertTrue(imported.deckNames.contains("English File Intermediate::Unit 1::Lesson 1A – Mood food::Grammar"))
    }
}

final class SecurityTests: XCTestCase {
    func testEncryptedFileStoreRoundTrip() throws {
        let store = EncryptedFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let secret = Data("page image bytes".utf8)
        let sealed = try store.seal(secret)
        XCTAssertNotEqual(sealed, secret)
        XCTAssertEqual(try store.open(sealed), secret)
    }

    func testSecureSecretStoreRoundTrip() throws {
        let store = SecureSecretStore()
        let account = "test-\(UUID().uuidString)"
        try store.store("sk-test-123", account: account)
        XCTAssertEqual(try store.secret(account: account), "sk-test-123")
        try store.remove(account: account)
        XCTAssertNil(try store.secret(account: account))
    }
}

@MainActor
final class StoreKitTests: XCTestCase {
    func testPurchaseUnlocksPremium() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        let store = StoreManager()
        await store.start()
        XCTAssertEqual(store.tier, .free)
        XCTAssertEqual(store.products.count, 3)

        let yearly = try XCTUnwrap(store.product(.yearly))
        XCTAssertNotNil(yearly.subscription?.introductoryOffer)
        let result = try await store.purchase(yearly)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(store.tier, .premium)
        XCTAssertEqual(store.gate.check(.ankiExport), .allowed)
    }
}

final class AIProviderFactoryTests: XCTestCase {
    @MainActor
    func testFactoryRequiresCredentials() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.aiProvider = .azureOpenAI
        settings.azureEndpoint = "http://insecure.example.com"
        settings.azureDeployment = "cards"
        let factory = AIProviderFactory(settings: settings, credentials: APICredentialStore())
        XCTAssertNil(factory.makeProvider(), "non-HTTPS endpoints and missing keys must be rejected")
    }
}
