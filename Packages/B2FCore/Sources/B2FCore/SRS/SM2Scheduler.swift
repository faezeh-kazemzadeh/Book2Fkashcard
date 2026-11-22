import Foundation

/// SM-2 as popularised by Anki: SuperMemo-2 ease factors with four answer
/// buttons, learning steps, a hard multiplier and an easy bonus.
///
/// Ease changes: Again −0.20, Hard −0.15, Good ±0, Easy +0.15 (floor 1.3).
/// Review intervals: Hard = I·1.2, Good = (I + d/2)·EF, Easy = (I + d)·EF·1.3,
/// where d is the number of days the card was overdue.
public struct SM2Scheduler: SpacedRepetitionScheduler {
    public let algorithm: SRSAlgorithm = .sm2
    public let configuration: SchedulerConfiguration

    public static let minimumEase = 1.3
    public static let startingEase = 2.5
    static let hardMultiplier = 1.2
    static let easyBonus = 1.3
    static let graduatingIntervalDays = 1.0
    static let easyIntervalDays = 4.0
    static let lapseNewIntervalFactor = 0.0

    public init(configuration: SchedulerConfiguration = .default) {
        self.configuration = configuration
    }

    /// SM-2 has no memory model, so the prediction uses an exponential
    /// forgetting curve calibrated so that R = 90% at the scheduled due date.
    public func retrievability(of state: SchedulingState, at date: Date) -> Double? {
        guard state.phase != .new, let last = state.lastReview else { return nil }
        let interval = max(state.intervalDays, 1.0 / 1_440)
        let elapsed = max(0, date.timeIntervalSince(last)) / 86_400
        return exp(log(0.9) * elapsed / interval)
    }

    public func review(_ state: SchedulingState, rating: Rating, at now: Date) -> ReviewOutcome {
        var s = state
        let elapsed = state.lastReview.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? 0
        let predicted = retrievability(of: state, at: now)
        let scheduled: TimeInterval

        switch s.phase {
        case .new, .learning:
            if s.phase == .new {
                s.phase = .learning
                s.learningStep = 0
                s.easeFactor = Self.startingEase
            }
            scheduled = advance(&s, rating: rating, steps: configuration.learningSteps,
                                graduateDays: rating == .easy ? Self.easyIntervalDays : Self.graduatingIntervalDays)

        case .relearning:
            let lapseInterval = max(1, (s.intervalDays * Self.lapseNewIntervalFactor).rounded())
            scheduled = advance(&s, rating: rating, steps: configuration.relearningSteps, graduateDays: lapseInterval)

        case .review:
            let current = max(s.intervalDays, 1)
            let overdue = max(0, elapsed - current)
            switch rating {
            case .again:
                s.lapses += 1
                s.easeFactor = max(Self.minimumEase, s.easeFactor - 0.2)
                s.intervalDays = max(1, (current * Self.lapseNewIntervalFactor).rounded())
                if configuration.relearningSteps.isEmpty {
                    scheduled = s.intervalDays * 86_400
                } else {
                    s.phase = .relearning
                    s.learningStep = 0
                    scheduled = configuration.relearningSteps[0]
                }
            case .hard, .good, .easy:
                let hard = max(current + 1, (current * Self.hardMultiplier).rounded())
                let good = max(hard + 1, ((current + overdue / 2) * s.easeFactor).rounded())
                let easy = max(good + 1, ((current + overdue) * s.easeFactor * Self.easyBonus).rounded())
                let next: Double
                switch rating {
                case .hard:
                    s.easeFactor = max(Self.minimumEase, s.easeFactor - 0.15)
                    next = hard
                case .good:
                    next = good
                default:
                    s.easeFactor += 0.15
                    next = easy
                }
                s.intervalDays = min(next, configuration.maximumIntervalDays)
                scheduled = s.intervalDays * 86_400
            }
        }

        s.repetitions += 1
        s.lastReview = now
        s.due = now.addingTimeInterval(scheduled)
        return ReviewOutcome(state: s, retrievabilityAtReview: predicted,
                             elapsedDays: elapsed, scheduledInterval: scheduled)
    }

    private func advance(_ s: inout SchedulingState, rating: Rating, steps: [TimeInterval], graduateDays: Double) -> TimeInterval {
        func graduate(_ days: Double) -> TimeInterval {
            s.phase = .review
            s.learningStep = 0
            s.intervalDays = days
            return days * 86_400
        }
        guard !steps.isEmpty else { return graduate(graduateDays) }
        let step = min(s.learningStep, steps.count - 1)
        switch rating {
        case .again:
            s.learningStep = 0
            s.intervalDays = steps[0] / 86_400
            return steps[0]
        case .hard:
            let interval = (step == 0 && steps.count > 1) ? (steps[0] + steps[1]) / 2 : steps[step] * 1.5
            s.intervalDays = interval / 86_400
            return interval
        case .good:
            let next = step + 1
            if next >= steps.count { return graduate(graduateDays) }
            s.learningStep = next
            s.intervalDays = steps[next] / 86_400
            return steps[next]
        case .easy:
            return graduate(max(graduateDays, Self.easyIntervalDays))
        }
    }
}
