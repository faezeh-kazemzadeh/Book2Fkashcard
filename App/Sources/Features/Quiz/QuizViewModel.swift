import Foundation
import Observation
import B2FCore

@MainActor
@Observable
final class QuizViewModel {
    let type: QuizType
    private(set) var questions: [QuizQuestion] = []
    private(set) var index = 0
    private(set) var grade: AnswerGrade?
    private(set) var score = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var typedAnswer = ""

    init(type: QuizType) {
        self.type = type
    }

    var current: QuizQuestion? { index < questions.count ? questions[index] : nil }
    var isFinished: Bool { !isLoading && current == nil }

    func load(cards: [QuizCardInput], passage: String?, provider: (any AIProvider)?, count: Int = 10) async {
        isLoading = true
        defer { isLoading = false }
        var engine = QuizEngine()
        questions = engine.makeQuiz(type: type, cards: cards, count: count)
        // Reading comprehension: add AI multiple-choice questions on the lesson text when possible.
        if type == .readingComprehension, let provider, let passage, passage.count > 200 {
            do {
                let generated = try await ReadingQuizGenerator(provider: provider).generate(passage: passage, count: 5)
                questions = Array((generated + questions).prefix(count))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        index = 0
        score = 0
        grade = nil
    }

    func submit(choice: Int) {
        guard let question = current, grade == nil else { return }
        record(QuizEngine.grade(choice: choice, question: question))
    }

    func submitTyped() {
        guard let question = current, grade == nil else { return }
        switch question.format {
        case .typed(let accepted): record(QuizEngine.grade(typedAnswer, accepted: accepted))
        case .spoken(let expected): record(QuizEngine.gradeSpoken(transcript: typedAnswer, expected: expected))
        case .choice: break
        }
    }

    func submitSpoken(transcript: String) {
        typedAnswer = transcript
        submitTyped()
    }

    func next() {
        grade = nil
        typedAnswer = ""
        index += 1
    }

    private func record(_ result: AnswerGrade) {
        grade = result
        if result.isAcceptable { score += 1 }
    }
}
