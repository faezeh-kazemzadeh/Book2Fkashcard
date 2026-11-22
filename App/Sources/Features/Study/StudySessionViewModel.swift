import Foundation
import Observation
import B2FCore

@MainActor
@Observable
final class StudySessionViewModel {
    let scope: LibraryRepository.StudyScope
    private(set) var queue: [FlashcardEntity] = []
    private(set) var position = 0
    private(set) var isAnswerShown = false
    private(set) var reviewedCount = 0
    private(set) var againCount = 0
    private(set) var intervalPreview: [Rating: TimeInterval] = [:]
    private(set) var prediction: Double?
    @ObservationIgnored private var shownAt = Date()
    @ObservationIgnored private var scheduler: any SpacedRepetitionScheduler = FSRSScheduler()

    init(scope: LibraryRepository.StudyScope) {
        self.scope = scope
    }

    var current: FlashcardEntity? { position < queue.count ? queue[position] : nil }
    var isFinished: Bool { current == nil }
    var remaining: Int { max(0, queue.count - position) }
    var progress: Double { queue.isEmpty ? 1 : Double(position) / Double(queue.count) }

    func load(repository: LibraryRepository, settings: AppSettings) {
        scheduler = settings.scheduler
        queue = repository.studyQueue(scope: scope, newCardsPerDay: settings.newCardsPerDay)
        position = 0
        reviewedCount = 0
        againCount = 0
        prepareCurrent()
    }

    func reveal() {
        guard !isAnswerShown, current != nil else { return }
        isAnswerShown = true
    }

    func answer(_ rating: Rating, repository: LibraryRepository) throws {
        guard let card = current, isAnswerShown else { return }
        let duration = min(Date().timeIntervalSince(shownAt), 120)
        let outcome = try repository.recordReview(of: card, rating: rating, duration: duration, scheduler: scheduler)
        reviewedCount += 1
        if rating == .again { againCount += 1 }
        // Cards due again within this session (learning steps) go back into the queue.
        if outcome.scheduledInterval < 20 * 60 {
            let insertAt = min(queue.count, position + 1 + max(3, queue.count / 10))
            queue.insert(card, at: insertAt)
        }
        position += 1
        prepareCurrent()
    }

    private func prepareCurrent() {
        isAnswerShown = false
        shownAt = Date()
        if let card = current {
            intervalPreview = scheduler.preview(card.scheduling, at: Date())
            prediction = scheduler.retrievability(of: card.scheduling, at: Date())
        } else {
            intervalPreview = [:]
            prediction = nil
        }
    }
}
