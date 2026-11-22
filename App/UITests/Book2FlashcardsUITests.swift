import XCTest

/// UI tests run against an in-memory store seeded with sample data and a
/// mocked AI provider, so they need no network or real purchases.
final class Book2FlashcardsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestInMemoryStore", "-UITestSeedData", "-UITestMockAI", "-SkipOnboarding", "-PremiumOverride"]
        app.launch()
    }

    func testLibraryShowsSeededBook() {
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["English File Intermediate"].waitForExistence(timeout: 5))
    }

    func testStudyFlowRatesCard() {
        app.tabBars.buttons["Study"].tap()
        app.buttons["studyAll"].tap()
        let showAnswer = app.buttons["showAnswer"]
        guard showAnswer.waitForExistence(timeout: 5) else {
            // Nothing due in the seed for today: the finished state must be shown instead.
            XCTAssertTrue(app.staticTexts["All done!"].exists)
            return
        }
        showAnswer.tap()
        let good = app.buttons["rating-3"]
        XCTAssertTrue(good.waitForExistence(timeout: 2))
        good.tap()
    }

    func testOpenLessonAndExportSheet() {
        app.tabBars.buttons["Library"].tap()
        app.staticTexts["English File Intermediate"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Lesson 1A – Mood food"].waitForExistence(timeout: 5))
        app.buttons["exportMenu"].tap()
        app.buttons["Export Entire Book"].tap()
        XCTAssertTrue(app.navigationBars["Export to Anki"].waitForExistence(timeout: 3))
    }

    func testSearchFindsVocabulary() {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("resil")
        XCTAssertTrue(app.staticTexts["resilient"].waitForExistence(timeout: 3))
    }

    func testDashboardAccessibility() throws {
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 5))
        if #available(iOS 17.0, *) {
            var issues: [String] = []
            try app.performAccessibilityAudit(for: [.dynamicType, .contrast, .elementDetection]) { issue in
                let element = issue.element
                // Charts expose decorative axis elements; ignore those.
                if element?.elementType == .other { return true }
                issues.append("\(issue.compactDescription): '\(element?.label ?? "?")' type=\(element?.elementType.rawValue ?? 0) id='\(element?.identifier ?? "")'")
                return true // reported below as one readable failure
            }
            XCTAssertTrue(issues.isEmpty, "Accessibility issues: " + issues.joined(separator: " | "))
        }
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
