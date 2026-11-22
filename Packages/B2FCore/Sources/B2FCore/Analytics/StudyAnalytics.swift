import Foundation

/// Immutable record of one review, used for analytics and FSRS optimisation.
public struct ReviewRecord: Codable, Hashable, Sendable {
    public var cardID: UUID
    public var reviewedAt: Date
    public var rating: Rating
    public var phaseBefore: CardPhase
    public var elapsedDays: Double
    public var scheduledDays: Double
    public var retrievability: Double?
    public var durationSeconds: Double

    public init(cardID: UUID, reviewedAt: Date, rating: Rating, phaseBefore: CardPhase,
                elapsedDays: Double, scheduledDays: Double, retrievability: Double?, durationSeconds: Double) {
        self.cardID = cardID
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.phaseBefore = phaseBefore
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.retrievability = retrievability
        self.durationSeconds = durationSeconds
    }
}

public struct DailyActivity: Hashable, Sendable, Identifiable {
    public var day: Date
    public var reviews: Int
    public var correct: Int
    public var id: Date { day }
}

public struct StudySummary: Hashable, Sendable {
    public var reviewsToday: Int
    /// "True retention": share of mature-phase reviews not answered Again.
    public var retentionRate: Double?
    public var currentStreak: Int
    public var longestStreak: Int
    public var weekly: [DailyActivity]
    public var monthly: [DailyActivity]
    /// Last 365 days, for the heatmap.
    public var heatmap: [Date: Int]
    /// Mean predicted retrievability at review time vs. observed recall (calibration).
    public var averagePredictedRecall: Double?
}

/// Pure analytics over review history. The app feeds records from the store.
public struct StudyAnalytics {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func summarize(_ records: [ReviewRecord], now: Date = Date()) -> StudySummary {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: (reviews: Int, correct: Int)] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.reviewedAt)
            var entry = byDay[day] ?? (0, 0)
            entry.reviews += 1
            if record.rating != .again { entry.correct += 1 }
            byDay[day] = entry
        }

        let reviewPhase = records.filter { $0.phaseBefore == .review }
        let retention: Double? = reviewPhase.isEmpty ? nil
            : Double(reviewPhase.filter { $0.rating != .again }.count) / Double(reviewPhase.count)

        let predictions = records.compactMap(\.retrievability)
        let averagePrediction = predictions.isEmpty ? nil : predictions.reduce(0, +) / Double(predictions.count)

        let (current, longest) = streaks(days: Set(byDay.keys), today: today)

        func series(_ count: Int) -> [DailyActivity] {
            (0..<count).reversed().compactMap { offset -> DailyActivity? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let entry = byDay[day] ?? (0, 0)
                return DailyActivity(day: day, reviews: entry.reviews, correct: entry.correct)
            }
        }

        var heatmap: [Date: Int] = [:]
        if let start = calendar.date(byAdding: .day, value: -364, to: today) {
            for (day, entry) in byDay where day >= start { heatmap[day] = entry.reviews }
        }

        return StudySummary(
            reviewsToday: byDay[today]?.reviews ?? 0,
            retentionRate: retention,
            currentStreak: current,
            longestStreak: longest,
            weekly: series(7),
            monthly: series(30),
            heatmap: heatmap,
            averagePredictedRecall: averagePrediction
        )
    }

    /// A streak continues through today even if today has no reviews yet.
    func streaks(days: Set<Date>, today: Date) -> (current: Int, longest: Int) {
        var current = 0
        var cursor = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while days.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return (current, max(longest, current))
    }

    /// Heatmap intensity bucket 0...4 for a review count.
    public static func heatLevel(_ count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1..<10: return 1
        case 10..<30: return 2
        case 30..<80: return 3
        default: return 4
        }
    }
}
