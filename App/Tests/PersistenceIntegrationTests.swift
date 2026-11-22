import XCTest
import SwiftData
import B2FCore
@testable import Book2Flashcards

/// Integration tests for SwiftData persistence, the study queue and review logging.
@MainActor
final class PersistenceIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var repository: LibraryRepository!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(cloudSync: false, inMemory: true)
        repository = LibraryRepository(context: container.mainContext)
    }

    func makeLesson(cards: [FlashcardDraft]) throws -> LessonEntity {
        let context = container.mainContext
        let book = BookEntity(title: "Test Book", targetLanguage: .english, nativeLanguage: .persian, source: .pdf)
        context.insert(book)
        let unit = UnitEntity(title: "Unit 1", order: 0)
        unit.book = book
        context.insert(unit)
        let lesson = LessonEntity(node: LessonNode(title: "Lesson 1A", pageRange: 0...1), order: 0)
        lesson.unit = unit
        context.insert(lesson)
        for draft in cards {
            let card = FlashcardEntity(draft: draft)
            card.lesson = lesson
            context.insert(card)
        }
        try context.save()
        return lesson
    }

    func vocab(_ term: String, priority: LearningPriority = .normal) -> FlashcardDraft {
        FlashcardDraft(content: .vocabulary(VocabularyContent(term: term, translation: "ترجمه")), priority: priority)
    }

    func testCardContentRoundTripsThroughStore() throws {
        let lesson = try makeLesson(cards: [vocab("resilient")])
        let card = try XCTUnwrap(lesson.cards?.first)
        XCTAssertEqual(card.kind, .vocabulary)
        XCTAssertEqual(card.frontText, "resilient")
        guard case .vocabulary(let v) = card.content else { return XCTFail() }
        XCTAssertEqual(v.translation, "ترجمه")
        XCTAssertEqual(lesson.deckPath, ["Test Book", "Unit 1", "Lesson 1A"])
    }

    func testStudyQueueLimitsNewCardsAndOrdersByPriority() throws {
        _ = try makeLesson(cards: [vocab("alpha"), vocab("beta", priority: .essential), vocab("gamma"), vocab("delta")])
        let queue = repository.studyQueue(newCardsPerDay: 2)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.first?.frontText, "beta")
    }

    func testRecordingReviewUpdatesSchedulingAndLogs() throws {
        let lesson = try makeLesson(cards: [vocab("resilient")])
        let card = try XCTUnwrap(lesson.cards?.first)
        let outcome = try repository.recordReview(of: card, rating: .easy, duration: 4, scheduler: FSRSScheduler())
        XCTAssertEqual(card.scheduling.phase, .review)
        XCTAssertEqual(card.due, outcome.state.due)
        XCTAssertEqual(repository.reviewRecords().count, 1)
        XCTAssertEqual(repository.newCardsIntroduced(on: Date()), 1)
        XCTAssertEqual(repository.dueCount(), 0)
    }

    func testDueCardsAppearInQueue() throws {
        let lesson = try makeLesson(cards: [vocab("resilient")])
        let card = try XCTUnwrap(lesson.cards?.first)
        card.scheduling = SchedulingState(phase: .review, due: Date().addingTimeInterval(-60),
                                          lastReview: Date().addingTimeInterval(-86_400 * 3), intervalDays: 3)
        try container.mainContext.save()
        XCTAssertEqual(repository.dueCount(), 1)
        XCTAssertEqual(repository.studyQueue(newCardsPerDay: 0).count, 1)
    }

    func testStudyScopeFiltersByLesson() throws {
        let lesson = try makeLesson(cards: [vocab("alpha")])
        _ = try makeLesson(cards: [vocab("beta")])
        let queue = repository.studyQueue(scope: .init(lessonIDs: [lesson.id]), newCardsPerDay: 10)
        XCTAssertEqual(queue.map(\.frontText), ["alpha"])
    }

    func testDeletingBookCascades() throws {
        _ = try makeLesson(cards: [vocab("alpha"), vocab("beta")])
        let book = try XCTUnwrap(repository.books().first)
        try repository.delete(book)
        XCTAssertEqual(repository.cardCount(), 0)
        XCTAssertEqual(repository.lessonCount(), 0)
    }

    func testWriterPersistsOutlineAndCards() async throws {
        let writer = LibraryWriter(modelContainer: container)
        let bookID = try await writer.createBook(title: "Book", author: "", target: .english, native: .persian, source: .txt, cover: nil)
        let outline = BookOutline(units: [UnitNode(title: "Unit 1", lessons: [LessonNode(title: "Lesson 1", pageRange: 0...0)])])
        try await writer.saveOutline(bookID: bookID, outline: outline)
        let work = await writer.lessonsNeedingCards(bookID: bookID)
        XCTAssertEqual(work.count, 1)
        try await writer.saveCards(lessonID: work[0].id, drafts: [vocab("resilient")])
        let remaining = await writer.lessonsNeedingCards(bookID: bookID)
        XCTAssertTrue(remaining.isEmpty)
        let total = await writer.totalCardCount()
        XCTAssertEqual(total, 1)
    }

    func testAnkiDeckImportBuildsHierarchy() async throws {
        let writer = LibraryWriter(modelContainer: container)
        let result = try await writer.importDeckCards(bookTitle: "English File", target: .english, native: .persian, cards: [
            (deckPath: ["English File", "Unit 1", "Lesson 1A", "Vocabulary"], draft: vocab("alpha")),
            (deckPath: ["English File", "Unit 1", "Lesson 1B"], draft: vocab("beta")),
            (deckPath: ["English File", "Unit 2", "Lesson 2A"], draft: vocab("gamma"))
        ])
        XCTAssertEqual(result.imported, 3)
        let book = try XCTUnwrap(repository.book(id: result.bookID))
        XCTAssertEqual(book.sortedUnits.map(\.title), ["Unit 1", "Unit 2"])
        XCTAssertEqual(book.sortedUnits[0].sortedLessons.map(\.title), ["Lesson 1A", "Lesson 1B"])
    }
}
