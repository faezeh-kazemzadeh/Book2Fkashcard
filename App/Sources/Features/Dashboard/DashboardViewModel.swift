import Foundation
import Observation
import B2FCore

@MainActor
@Observable
final class DashboardViewModel {
    struct Snapshot {
        var books = 0
        var lessons = 0
        var cards = 0
        var dueNow = 0
        var exports = 0
        var summary: StudySummary?
    }

    private(set) var snapshot = Snapshot()

    func refresh(repository: LibraryRepository, now: Date = Date()) {
        // Only the last year of reviews is needed for every dashboard widget.
        let since = Calendar.current.date(byAdding: .day, value: -366, to: now)
        let records = repository.reviewRecords(since: since)
        snapshot = Snapshot(
            books: repository.bookCount(),
            lessons: repository.lessonCount(),
            cards: repository.cardCount(),
            dueNow: repository.dueCount(now: now),
            exports: repository.exportCount(),
            summary: StudyAnalytics().summarize(records, now: now)
        )
    }

    var retentionText: String {
        guard let rate = snapshot.summary?.retentionRate else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    var streakText: String {
        let days = snapshot.summary?.currentStreak ?? 0
        return String(localized: "\(days) days")
    }
}
