import Foundation
import SwiftData
import B2FCore

/// Main-actor façade over SwiftData used by view models.
/// Background work (imports, generation) goes through `LibraryWriter`.
@MainActor
final class LibraryRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Counts (plan limits, dashboard)

    func bookCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<BookEntity>())) ?? 0
    }

    func cardCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<FlashcardEntity>())) ?? 0
    }

    func lessonCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<LessonEntity>())) ?? 0
    }

    func exportCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<ExportRecordEntity>())) ?? 0
    }

    // MARK: Books

    func books() -> [BookEntity] {
        let descriptor = FetchDescriptor<BookEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func book(id: UUID) -> BookEntity? {
        var descriptor = FetchDescriptor<BookEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func lesson(id: UUID) -> LessonEntity? {
        var descriptor = FetchDescriptor<LessonEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func card(id: UUID) -> FlashcardEntity? {
        var descriptor = FetchDescriptor<FlashcardEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func delete(_ book: BookEntity) throws {
        context.delete(book)
        try context.save()
    }

    // MARK: Study queue

    struct StudyScope: Equatable {
        var lessonIDs: Set<UUID>?
        static let all = StudyScope(lessonIDs: nil)
    }

    /// Due reviews (learning first, then by due date) followed by today's
    /// allowance of new cards (highest priority first).
    func studyQueue(scope: StudyScope = .all, newCardsPerDay: Int, maxReviews: Int = 500, now: Date = Date()) -> [FlashcardEntity] {
        let newPhase = CardPhase.new.rawValue
        let dueDescriptor = FetchDescriptor<FlashcardEntity>(
            predicate: #Predicate { $0.due <= now && $0.isSuspended == false && $0.phaseRaw != newPhase },
            sortBy: [SortDescriptor(\.due)])
        var reviews = ((try? context.fetch(dueDescriptor)) ?? []).filter { inScope($0, scope) }
        reviews.sort { lhs, rhs in
            let l = lhs.phaseRaw == CardPhase.review.rawValue ? 1 : 0
            let r = rhs.phaseRaw == CardPhase.review.rawValue ? 1 : 0
            return l != r ? l < r : lhs.due < rhs.due
        }

        let remainingNew = max(0, newCardsPerDay - newCardsIntroduced(on: now))
        var fresh: [FlashcardEntity] = []
        if remainingNew > 0 {
            let newDescriptor = FetchDescriptor<FlashcardEntity>(
                predicate: #Predicate { $0.phaseRaw == newPhase && $0.isSuspended == false },
                sortBy: [SortDescriptor(\.priorityRaw, order: .reverse), SortDescriptor(\.createdAt)])
            fresh = Array(((try? context.fetch(newDescriptor)) ?? []).filter { inScope($0, scope) }.prefix(remainingNew))
        }
        return Array(reviews.prefix(maxReviews)) + fresh
    }

    func dueCount(now: Date = Date()) -> Int {
        let newPhase = CardPhase.new.rawValue
        let descriptor = FetchDescriptor<FlashcardEntity>(
            predicate: #Predicate { $0.due <= now && $0.isSuspended == false && $0.phaseRaw != newPhase })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    private func inScope(_ card: FlashcardEntity, _ scope: StudyScope) -> Bool {
        guard let ids = scope.lessonIDs else { return true }
        return card.lesson.map { ids.contains($0.id) } ?? false
    }

    func newCardsIntroduced(on date: Date) -> Int {
        let start = Calendar.current.startOfDay(for: date)
        let newPhase = CardPhase.new.rawValue
        let descriptor = FetchDescriptor<ReviewLogEntity>(
            predicate: #Predicate { $0.reviewedAt >= start && $0.phaseBeforeRaw == newPhase })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: Reviews

    @discardableResult
    func recordReview(of card: FlashcardEntity, rating: Rating, duration: TimeInterval,
                      scheduler: any SpacedRepetitionScheduler, at now: Date = Date()) throws -> ReviewOutcome {
        let before = card.scheduling
        let outcome = scheduler.review(before, rating: rating, at: now)
        card.scheduling = outcome.state
        let log = ReviewLogEntity(cardID: card.id, outcome: outcome, rating: rating, phaseBefore: before.phase,
                                  duration: duration, algorithm: scheduler.algorithm, at: now)
        log.card = card
        context.insert(log)
        try context.save()
        return outcome
    }

    func reviewRecords(since date: Date? = nil) -> [ReviewRecord] {
        var descriptor = FetchDescriptor<ReviewLogEntity>(sortBy: [SortDescriptor(\.reviewedAt)])
        if let date { descriptor.predicate = #Predicate { $0.reviewedAt >= date } }
        return ((try? context.fetch(descriptor)) ?? []).map(\.record)
    }

    // MARK: Cards

    func existingDeduplicationKeys(in book: BookEntity) -> Set<String> {
        Set(book.allCards.map { $0.content.deduplicationKey })
    }

    func update(_ card: FlashcardEntity, content: CardContent) throws {
        card.content = content
        card.confidence = max(card.confidence, 0.95) // user-verified
        try context.save()
    }

    func setSuspended(_ card: FlashcardEntity, _ suspended: Bool) throws {
        card.isSuspended = suspended
        try context.save()
    }

    func delete(_ card: FlashcardEntity) throws {
        context.delete(card)
        try context.save()
    }

    func resetSchedulingForAll() throws {
        for card in (try? context.fetch(FetchDescriptor<FlashcardEntity>())) ?? [] {
            card.scheduling = .newCard()
        }
        try context.save()
    }

    // MARK: Pages

    func updateOCRText(_ page: PageEntity, text: String) throws {
        page.ocrText = text
        page.isUserCorrected = true
        page.isLowConfidence = false
        try context.save()
    }

    // MARK: Exports

    func recordExport(scope: String, cardCount: Int, books: [BookEntity]) throws {
        context.insert(ExportRecordEntity(scopeDescription: scope, cardCount: cardCount))
        for book in books { book.exportCount += 1 }
        try context.save()
    }
}
