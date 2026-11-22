import XCTest
@testable import B2FCore

final class FSRSSchedulerTests: XCTestCase {
    let scheduler = FSRSScheduler()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewCardGoodEntersSecondLearningStep() {
        let outcome = scheduler.review(.newCard(now: start), rating: .good, at: start)
        XCTAssertEqual(outcome.state.phase, .learning)
        XCTAssertEqual(outcome.state.learningStep, 1)
        XCTAssertEqual(outcome.scheduledInterval, 600, accuracy: 0.001)
        XCTAssertEqual(outcome.state.stability!, FSRSScheduler.defaultWeights[2], accuracy: 1e-9)
    }

    func testNewCardEasyGraduatesUsingInitialStability() {
        let outcome = scheduler.review(.newCard(now: start), rating: .easy, at: start)
        XCTAssertEqual(outcome.state.phase, .review)
        // S0(easy) = 15.69 days, desired retention 0.9 → interval == stability → 16 days.
        XCTAssertEqual(outcome.state.intervalDays, 16)
    }

    func testInitialDifficultyOrdering() {
        let again = scheduler.initialDifficulty(.again)
        let easy = scheduler.initialDifficulty(.easy)
        XCTAssertGreaterThan(again, easy)
        XCTAssertTrue((1...10).contains(again))
        XCTAssertTrue((1...10).contains(easy))
    }

    func testRetrievabilityAtIntervalMatchesDesiredRetention() {
        let r = FSRSScheduler.forgettingCurve(elapsedDays: 10, stability: 10)
        XCTAssertEqual(r, 0.9, accuracy: 1e-9)
    }

    func testReviewButtonsAreOrdered() {
        var state = scheduler.review(.newCard(now: start), rating: .easy, at: start).state
        let reviewDay = state.due
        state = scheduler.review(state, rating: .good, at: reviewDay).state
        let preview = scheduler.preview(state, at: state.due)
        XCTAssertLessThan(preview[.again]!, preview[.hard]!)
        XCTAssertLessThanOrEqual(preview[.hard]!, preview[.good]!)
        XCTAssertLessThan(preview[.good]!, preview[.easy]!)
    }

    func testSuccessfulReviewsGrowIntervals() {
        var state = scheduler.review(.newCard(now: start), rating: .easy, at: start).state
        var previous = state.intervalDays
        for _ in 0..<5 {
            state = scheduler.review(state, rating: .good, at: state.due).state
            XCTAssertGreaterThan(state.intervalDays, previous)
            previous = state.intervalDays
        }
    }

    func testLapseMovesToRelearningAndReducesStability() {
        var state = scheduler.review(.newCard(now: start), rating: .easy, at: start).state
        state = scheduler.review(state, rating: .good, at: state.due).state
        let stabilityBefore = state.stability!
        let lapse = scheduler.review(state, rating: .again, at: state.due)
        XCTAssertEqual(lapse.state.phase, .relearning)
        XCTAssertEqual(lapse.state.lapses, 1)
        XCTAssertLessThan(lapse.state.stability!, stabilityBefore)
        XCTAssertEqual(lapse.scheduledInterval, 600, accuracy: 0.001)
        XCTAssertNotNil(lapse.retrievabilityAtReview)
    }

    func testSeedsMemoryStateFromSM2Card() {
        let sm2Card = SchedulingState(phase: .review, due: start, lastReview: start.addingTimeInterval(-10 * 86_400),
                                      intervalDays: 10, easeFactor: 2.5, repetitions: 4)
        let outcome = scheduler.review(sm2Card, rating: .good, at: start)
        XCTAssertNotNil(outcome.state.stability)
        XCTAssertGreaterThan(outcome.state.intervalDays, 10)
    }

    func testDesiredRetentionIsClamped() {
        XCTAssertEqual(SchedulerConfiguration(desiredRetention: 0.5).desiredRetention, 0.7)
        XCTAssertEqual(SchedulerConfiguration(desiredRetention: 0.999).desiredRetention, 0.97)
    }
}

final class SM2SchedulerTests: XCTestCase {
    let scheduler = SM2Scheduler()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testLearningStepsThenGraduation() {
        var outcome = scheduler.review(.newCard(now: start), rating: .good, at: start)
        XCTAssertEqual(outcome.state.phase, .learning)
        XCTAssertEqual(outcome.scheduledInterval, 600, accuracy: 0.001)
        outcome = scheduler.review(outcome.state, rating: .good, at: outcome.state.due)
        XCTAssertEqual(outcome.state.phase, .review)
        XCTAssertEqual(outcome.state.intervalDays, 1)
    }

    func testGoodReviewMultipliesByEase() {
        let card = SchedulingState(phase: .review, due: start, lastReview: start.addingTimeInterval(-10 * 86_400),
                                   intervalDays: 10, easeFactor: 2.5, repetitions: 3)
        let outcome = scheduler.review(card, rating: .good, at: start)
        XCTAssertEqual(outcome.state.intervalDays, 25)
        XCTAssertEqual(outcome.state.easeFactor, 2.5)
    }

    func testEasyAndHardAdjustEase() {
        let card = SchedulingState(phase: .review, due: start, lastReview: start.addingTimeInterval(-10 * 86_400),
                                   intervalDays: 10, easeFactor: 2.5, repetitions: 3)
        XCTAssertEqual(scheduler.review(card, rating: .easy, at: start).state.easeFactor, 2.65, accuracy: 1e-9)
        XCTAssertEqual(scheduler.review(card, rating: .hard, at: start).state.easeFactor, 2.35, accuracy: 1e-9)
        XCTAssertEqual(scheduler.review(card, rating: .hard, at: start).state.intervalDays, 12)
    }

    func testLapseNeverDropsEaseBelowMinimum() {
        let card = SchedulingState(phase: .review, due: start, lastReview: start.addingTimeInterval(-86_400),
                                   intervalDays: 1, easeFactor: 1.35, repetitions: 3)
        let outcome = scheduler.review(card, rating: .again, at: start)
        XCTAssertEqual(outcome.state.easeFactor, SM2Scheduler.minimumEase)
        XCTAssertEqual(outcome.state.phase, .relearning)
        XCTAssertEqual(outcome.state.lapses, 1)
    }

    func testPredictionIsNinetyPercentAtDueDate() {
        let card = SchedulingState(phase: .review, due: start.addingTimeInterval(5 * 86_400), lastReview: start,
                                   intervalDays: 5, easeFactor: 2.5)
        XCTAssertEqual(scheduler.retrievability(of: card, at: card.due)!, 0.9, accuracy: 1e-9)
    }

    func testIntervalFormatter() {
        XCTAssertEqual(IntervalFormatter.short(60), "1m")
        XCTAssertEqual(IntervalFormatter.short(600), "10m")
        XCTAssertEqual(IntervalFormatter.short(3 * 86_400), "3d")
    }
}

final class StudyAnalyticsTests: XCTestCase {
    func testStreakRetentionAndHeatmap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let analytics = StudyAnalytics(calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        func record(daysAgo: Int, rating: Rating, phase: CardPhase = .review) -> ReviewRecord {
            ReviewRecord(cardID: id, reviewedAt: now.addingTimeInterval(Double(-daysAgo) * 86_400), rating: rating,
                         phaseBefore: phase, elapsedDays: 1, scheduledDays: 2, retrievability: 0.9, durationSeconds: 5)
        }
        let records = [record(daysAgo: 0, rating: .good), record(daysAgo: 1, rating: .again),
                       record(daysAgo: 2, rating: .good), record(daysAgo: 5, rating: .easy)]
        let summary = analytics.summarize(records, now: now)
        XCTAssertEqual(summary.reviewsToday, 1)
        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.retentionRate!, 0.75, accuracy: 1e-9)
        XCTAssertEqual(summary.weekly.count, 7)
        XCTAssertEqual(summary.monthly.count, 30)
        XCTAssertEqual(summary.heatmap.values.reduce(0, +), 4)
        XCTAssertEqual(StudyAnalytics.heatLevel(0), 0)
        XCTAssertEqual(StudyAnalytics.heatLevel(100), 4)
    }
}
