import Foundation
import SwiftData
import B2FCore

/// Background writer used by the processing pipeline and importers.
/// Each call saves, so the UI (observing the main context) updates incrementally.
@ModelActor
actor LibraryWriter {

    func createBook(title: String, author: String, target: StudyLanguage, native: StudyLanguage,
                    source: BookSourceKind, cover: Data?) throws -> UUID {
        let book = BookEntity(title: title, author: author, targetLanguage: target, nativeLanguage: native, source: source)
        book.coverThumbnail = cover
        book.status = .extracting
        modelContext.insert(book)
        try modelContext.save()
        return book.id
    }

    func updateStatus(bookID: UUID, status: ProcessingStatus, message: String = "", progress: Double? = nil) throws {
        guard let book = fetchBook(bookID) else { return }
        book.status = status
        book.statusMessage = message
        if let progress { book.progress = progress }
        book.updatedAt = Date()
        try modelContext.save()
    }

    func addPage(bookID: UUID, index: Int, text: String, analyzed: AnalyzedPage?, encryptedImage: Data?) throws {
        guard let book = fetchBook(bookID) else { return }
        let page = PageEntity(index: index, ocrText: text, analyzed: analyzed, encryptedImage: encryptedImage)
        page.book = book
        modelContext.insert(page)
        book.pageCount = max(book.pageCount, index + 1)
        try modelContext.save()
    }

    func analyzedPages(bookID: UUID) -> [AnalyzedPage] {
        guard let book = fetchBook(bookID) else { return [] }
        return book.sortedPages.compactMap { page in
            if page.isUserCorrected {
                // Re-analyse corrected text so structure reflects the user's edits.
                return LayoutAnalyzer().analyze(pageIndex: page.index, plainText: page.ocrText)
            }
            return page.analyzed
        }
    }

    /// Replaces the book's outline. Existing cards of lessons that keep their ID are preserved.
    func saveOutline(bookID: UUID, outline: BookOutline) throws {
        guard let book = fetchBook(bookID) else { return }
        for unit in book.units ?? [] { modelContext.delete(unit) }
        for (unitOrder, unitNode) in outline.units.enumerated() {
            let unit = UnitEntity(title: unitNode.title, order: unitOrder)
            unit.book = book
            modelContext.insert(unit)
            for (lessonOrder, lessonNode) in unitNode.lessons.enumerated() {
                let lesson = LessonEntity(node: lessonNode, order: lessonOrder)
                lesson.unit = unit
                modelContext.insert(lesson)
            }
        }
        try modelContext.save()
    }

    struct LessonWorkItem: Sendable {
        let id: UUID
        let node: LessonNode
        let unitTitle: String
        let bookTitle: String
    }

    func lessonsNeedingCards(bookID: UUID) -> [LessonWorkItem] {
        guard let book = fetchBook(bookID) else { return [] }
        return book.allLessons
            .filter { $0.generationStatus != .ready }
            .map { LessonWorkItem(id: $0.id, node: $0.node, unitTitle: $0.unit?.title ?? "", bookTitle: book.title) }
    }

    func deduplicationKeys(bookID: UUID) -> Set<String> {
        guard let book = fetchBook(bookID) else { return [] }
        return Set(book.allCards.map { $0.content.deduplicationKey })
    }

    func totalCardCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<FlashcardEntity>())) ?? 0
    }

    func saveCards(lessonID: UUID, drafts: [FlashcardDraft]) throws {
        guard let lesson = fetchLesson(lessonID) else { return }
        for draft in drafts {
            let card = FlashcardEntity(draft: draft)
            card.lesson = lesson
            modelContext.insert(card)
        }
        lesson.generationStatus = .ready
        lesson.unit?.book?.updatedAt = Date()
        try modelContext.save()
    }

    func markLesson(_ lessonID: UUID, status: ProcessingStatus) throws {
        fetchLesson(lessonID)?.generationStatus = status
        try modelContext.save()
    }

    /// Creates (or reuses) Book → Unit → Lesson entities from an Anki deck path and stores the cards.
    func importDeckCards(bookTitle: String, target: StudyLanguage, native: StudyLanguage,
                         cards: [(deckPath: [String], draft: FlashcardDraft)]) throws -> (bookID: UUID, imported: Int) {
        let book = BookEntity(title: bookTitle, targetLanguage: target, nativeLanguage: native, source: .ankiDeck)
        book.status = .ready
        book.progress = 1
        modelContext.insert(book)

        var units: [String: UnitEntity] = [:]
        var lessons: [String: LessonEntity] = [:]
        // Deck path "Book::Unit::Lesson::Section" → unit = component 1, lesson = component 2 (when present).
        for (deckPath, draft) in cards {
            let unitTitle = deckPath.count > 1 ? deckPath[1] : (deckPath.first ?? "Imported")
            let lessonTitle = deckPath.count > 2 ? deckPath[2] : unitTitle
            let unit = units[unitTitle] ?? {
                let unit = UnitEntity(title: unitTitle, order: units.count)
                unit.book = book
                modelContext.insert(unit)
                units[unitTitle] = unit
                return unit
            }()
            let lessonKey = unitTitle + "\u{1f}" + lessonTitle
            let lesson = lessons[lessonKey] ?? {
                let lesson = LessonEntity(node: LessonNode(title: lessonTitle, pageRange: 0...0), order: unit.lessons?.count ?? 0)
                lesson.generationStatus = .ready
                lesson.unit = unit
                modelContext.insert(lesson)
                lessons[lessonKey] = lesson
                return lesson
            }()
            let card = FlashcardEntity(draft: draft)
            card.lesson = lesson
            modelContext.insert(card)
        }
        try modelContext.save()
        return (book.id, cards.count)
    }

    private func fetchBook(_ id: UUID) -> BookEntity? {
        var descriptor = FetchDescriptor<BookEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchLesson(_ id: UUID) -> LessonEntity? {
        var descriptor = FetchDescriptor<LessonEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
