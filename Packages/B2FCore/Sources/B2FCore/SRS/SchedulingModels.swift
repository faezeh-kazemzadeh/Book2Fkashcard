import Foundation

public enum SRSAlgorithm: String, Codable, CaseIterable, Identifiable, Sendable {
    case sm2
    case fsrs

    public var id: String { rawValue }
    public var displayName: String { self == .sm2 ? "SM-2 (classic)" : "FSRS (recommended)" }
}

public enum Rating: Int, Codable, CaseIterable, Identifiable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

public enum CardPhase: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case review
    case relearning
}

/// Scheduling state that both algorithms understand. Keeping SM-2 and FSRS
/// fields side by side lets the user switch algorithms without losing history:
/// FSRS seeds memory state from SM-2 fields on first use.
public struct SchedulingState: Codable, Hashable, Sendable {
    public var phase: CardPhase
    public var due: Date
    public var lastReview: Date?
    /// Current interval in days (fractional for learning steps).
    public var intervalDays: Double
    /// SM-2 ease factor (2.5 = 250%).
    public var easeFactor: Double
    public var repetitions: Int
    public var lapses: Int
    /// FSRS memory stability in days.
    public var stability: Double?
    /// FSRS difficulty in 1...10.
    public var difficulty: Double?
    /// Index into the learning or relearning steps.
    public var learningStep: Int

    public init(phase: CardPhase = .new, due: Date = Date(), lastReview: Date? = nil, intervalDays: Double = 0,
                easeFactor: Double = 2.5, repetitions: Int = 0, lapses: Int = 0,
                stability: Double? = nil, difficulty: Double? = nil, learningStep: Int = 0) {
        self.phase = phase
        self.due = due
        self.lastReview = lastReview
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.lapses = lapses
        self.stability = stability
        self.difficulty = difficulty
        self.learningStep = learningStep
    }

    public static func newCard(now: Date = Date()) -> SchedulingState {
        SchedulingState(phase: .new, due: now)
    }

    public func isDue(at date: Date) -> Bool { due <= date }
}

public struct ReviewOutcome: Hashable, Sendable {
    public var state: SchedulingState
    /// Predicted probability of recall at the moment of this review (nil for new cards).
    public var retrievabilityAtReview: Double?
    /// Days elapsed since the previous review.
    public var elapsedDays: Double
    /// Interval until the next review, in seconds.
    public var scheduledInterval: TimeInterval
}

/// Shared configuration.
public struct SchedulerConfiguration: Codable, Hashable, Sendable {
    /// Learning steps for new cards.
    public var learningSteps: [TimeInterval]
    /// Relearning steps after a lapse.
    public var relearningSteps: [TimeInterval]
    /// FSRS target probability of recall (0.7...0.97).
    public var desiredRetention: Double
    public var maximumIntervalDays: Double
    /// FSRS-5 model weights (19 parameters). Can be replaced with optimised weights.
    public var fsrsWeights: [Double]

    public init(learningSteps: [TimeInterval] = [60, 600],
                relearningSteps: [TimeInterval] = [600],
                desiredRetention: Double = 0.9,
                maximumIntervalDays: Double = 36_500,
                fsrsWeights: [Double] = FSRSScheduler.defaultWeights) {
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.97)
        self.maximumIntervalDays = maximumIntervalDays
        self.fsrsWeights = fsrsWeights.count == 19 ? fsrsWeights : FSRSScheduler.defaultWeights
    }

    public static let `default` = SchedulerConfiguration()
}

public protocol SpacedRepetitionScheduler: Sendable {
    var algorithm: SRSAlgorithm { get }
    var configuration: SchedulerConfiguration { get }
    func review(_ state: SchedulingState, rating: Rating, at now: Date) -> ReviewOutcome
    /// Probability of recall at `date` ("prediction score").
    func retrievability(of state: SchedulingState, at date: Date) -> Double?
}

public extension SpacedRepetitionScheduler {
    /// Interval each rating would produce. Shown on the answer buttons.
    func preview(_ state: SchedulingState, at now: Date) -> [Rating: TimeInterval] {
        var result: [Rating: TimeInterval] = [:]
        for rating in Rating.allCases {
            result[rating] = review(state, rating: rating, at: now).scheduledInterval
        }
        return result
    }
}

public enum SchedulerFactory {
    public static func make(_ algorithm: SRSAlgorithm, configuration: SchedulerConfiguration = .default) -> any SpacedRepetitionScheduler {
        switch algorithm {
        case .sm2: return SM2Scheduler(configuration: configuration)
        case .fsrs: return FSRSScheduler(configuration: configuration)
        }
    }
}

/// Human friendly interval text for answer buttons ("10m", "3d", "2.1mo").
public enum IntervalFormatter {
    public static func short(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(1, Int(minutes.rounded())))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded()))h" }
        let days = hours / 24
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return String(format: "%.1fmo", days / 30) }
        return String(format: "%.1fy", days / 365)
    }
}
