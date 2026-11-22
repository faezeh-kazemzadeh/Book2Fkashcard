import Foundation

/// Free Spaced Repetition Scheduler, version 5 (FSRS-5).
///
/// Memory model: each card has a stability `S` (days until recall probability
/// drops to 90%) and a difficulty `D` (1...10). Retrievability follows the
/// power forgetting curve `R(t, S) = (1 + F·t/S)^C` with `C = -0.5`, `F = 19/81`.
/// The next interval is the time at which `R` reaches the desired retention.
///
/// Reference: open-spaced-repetition/fsrs4anki wiki, "The Algorithm" (FSRS-5).
public struct FSRSScheduler: SpacedRepetitionScheduler {

    /// FSRS-5 default parameters, trained on the open Anki review dataset.
    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
        0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621
    ]

    static let decay = -0.5
    static let factor = 19.0 / 81.0

    public let algorithm: SRSAlgorithm = .fsrs
    public let configuration: SchedulerConfiguration
    private var w: [Double] { configuration.fsrsWeights }

    public init(configuration: SchedulerConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: Model equations

    public static func forgettingCurve(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + factor * t / max(s, 0.01), decay)
    }

    func nextIntervalDays(stability s: Double) -> Double {
        let r = configuration.desiredRetention
        let raw = s / Self.factor * (pow(r, 1 / Self.decay) - 1)
        return min(max(raw.rounded(), 1), configuration.maximumIntervalDays)
    }

    func initialStability(_ rating: Rating) -> Double {
        max(w[rating.rawValue - 1], 0.1)
    }

    func initialDifficulty(_ rating: Rating) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1)
    }

    func nextDifficulty(_ d: Double, rating: Rating) -> Double {
        let delta = -w[6] * Double(rating.rawValue - 3)
        let damped = d + delta * (10 - d) / 9
        let reverted = w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    func recallStability(d: Double, s: Double, r: Double, rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hardPenalty * easyBonus + 1)
    }

    func forgetStability(d: Double, s: Double, r: Double) -> Double {
        let value = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
        return max(0.1, min(value, s))
    }

    func shortTermStability(s: Double, rating: Rating) -> Double {
        max(0.1, s * exp(w[17] * (Double(rating.rawValue) - 3 + w[18])))
    }

    private func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: Scheduling

    public func retrievability(of state: SchedulingState, at date: Date) -> Double? {
        guard state.phase != .new, let last = state.lastReview else { return nil }
        let s = state.stability ?? seededStability(state)
        let elapsed = max(0, date.timeIntervalSince(last)) / 86_400
        return Self.forgettingCurve(elapsedDays: elapsed, stability: s)
    }

    public func review(_ state: SchedulingState, rating: Rating, at now: Date) -> ReviewOutcome {
        var s = state
        let elapsed = state.lastReview.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? 0
        var recallProbability: Double?

        if s.phase != .new && (s.stability == nil || s.difficulty == nil) {
            s.stability = seededStability(s)
            s.difficulty = seededDifficulty(s)
        }

        let scheduled: TimeInterval
        switch s.phase {
        case .new:
            s.stability = initialStability(rating)
            s.difficulty = initialDifficulty(rating)
            s.learningStep = 0
            s.phase = .learning
            scheduled = advanceSteps(&s, rating: rating, steps: configuration.learningSteps)

        case .learning, .relearning:
            let stability = s.stability ?? initialStability(rating)
            let difficulty = s.difficulty ?? initialDifficulty(rating)
            if elapsed < 1 {
                s.stability = shortTermStability(s: stability, rating: rating)
            } else {
                let r = Self.forgettingCurve(elapsedDays: elapsed, stability: stability)
                recallProbability = r
                s.stability = rating == .again
                    ? forgetStability(d: difficulty, s: stability, r: r)
                    : recallStability(d: difficulty, s: stability, r: r, rating: rating)
            }
            s.difficulty = nextDifficulty(difficulty, rating: rating)
            let steps = s.phase == .learning ? configuration.learningSteps : configuration.relearningSteps
            scheduled = advanceSteps(&s, rating: rating, steps: steps)

        case .review:
            let stability = s.stability ?? 1
            let difficulty = s.difficulty ?? 5
            let r = Self.forgettingCurve(elapsedDays: elapsed, stability: stability)
            recallProbability = r
            s.difficulty = nextDifficulty(difficulty, rating: rating)

            if rating == .again {
                s.lapses += 1
                s.stability = forgetStability(d: difficulty, s: stability, r: r)
                if configuration.relearningSteps.isEmpty {
                    scheduled = graduate(&s)
                } else {
                    s.phase = .relearning
                    s.learningStep = 0
                    scheduled = configuration.relearningSteps[0]
                    s.intervalDays = scheduled / 86_400
                }
            } else {
                // Compute all three so that hard ≤ good < easy always holds.
                let hardS = recallStability(d: difficulty, s: stability, r: r, rating: .hard)
                let goodS = recallStability(d: difficulty, s: stability, r: r, rating: .good)
                let easyS = recallStability(d: difficulty, s: stability, r: r, rating: .easy)
                var hardI = nextIntervalDays(stability: hardS)
                var goodI = nextIntervalDays(stability: goodS)
                var easyI = nextIntervalDays(stability: easyS)
                hardI = min(hardI, goodI)
                goodI = max(goodI, hardI + 1)
                easyI = max(easyI, goodI + 1)
                let chosen: (Double, Double)
                switch rating {
                case .hard: chosen = (hardS, hardI)
                case .good: chosen = (goodS, goodI)
                default: chosen = (easyS, easyI)
                }
                s.stability = chosen.0
                s.intervalDays = min(chosen.1, configuration.maximumIntervalDays)
                s.phase = .review
                scheduled = s.intervalDays * 86_400
            }
        }

        s.repetitions += 1
        s.lastReview = now
        s.due = now.addingTimeInterval(scheduled)
        return ReviewOutcome(state: s, retrievabilityAtReview: recallProbability,
                             elapsedDays: elapsed, scheduledInterval: scheduled)
    }

    /// Moves through learning/relearning steps (Anki semantics) and graduates when done.
    private func advanceSteps(_ s: inout SchedulingState, rating: Rating, steps: [TimeInterval]) -> TimeInterval {
        guard !steps.isEmpty else { return graduate(&s) }
        let step = min(s.learningStep, steps.count - 1)
        let interval: TimeInterval
        switch rating {
        case .again:
            s.learningStep = 0
            interval = steps[0]
        case .hard:
            interval = (step == 0 && steps.count > 1) ? (steps[0] + steps[1]) / 2 : steps[step] * 1.5
        case .good:
            let next = step + 1
            if next >= steps.count { return graduate(&s) }
            s.learningStep = next
            interval = steps[next]
        case .easy:
            return graduate(&s)
        }
        s.intervalDays = interval / 86_400
        return interval
    }

    private func graduate(_ s: inout SchedulingState) -> TimeInterval {
        s.phase = .review
        s.learningStep = 0
        s.intervalDays = nextIntervalDays(stability: s.stability ?? 1)
        return s.intervalDays * 86_400
    }

    // MARK: Seeding from SM-2 history

    private func seededStability(_ state: SchedulingState) -> Double {
        // An SM-2 card at its due date is assumed to be at ~90% retrievability,
        // which by definition means stability ≈ interval.
        max(state.intervalDays, 0.5)
    }

    private func seededDifficulty(_ state: SchedulingState) -> Double {
        // Map ease 1.3 (hardest) … 3.0+ (easiest) onto difficulty 10 … ~3.
        clampDifficulty(5 + (2.5 - state.easeFactor) * (10.0 / 3.0))
    }
}
