import Foundation

public enum QuizType: String, Codable, CaseIterable, Identifiable, Sendable {
    case multipleChoice
    case fillInTheBlank
    case listening
    case speaking
    case translation
    case typing
    case vocabularyChallenge
    case grammarChallenge
    case readingComprehension

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .fillInTheBlank: return "Fill in the Blank"
        case .listening: return "Listening Quiz"
        case .speaking: return "Speaking Quiz"
        case .translation: return "Translation Quiz"
        case .typing: return "Typing Test"
        case .vocabularyChallenge: return "Vocabulary Challenge"
        case .grammarChallenge: return "Grammar Challenge"
        case .readingComprehension: return "Reading Comprehension"
        }
    }
}

public struct QuizQuestion: Identifiable, Hashable, Sendable {
    public enum Format: Hashable, Sendable {
        /// Pick one of the options.
        case choice(options: [String], correctIndex: Int)
        /// Type the answer; graded with tolerance.
        case typed(acceptedAnswers: [String])
        /// Say the answer; graded on the speech transcript.
        case spoken(expected: String)
    }

    public var id: UUID
    public var type: QuizType
    public var cardID: UUID?
    public var prompt: String
    /// Text to speak for listening questions.
    public var audioText: String?
    public var format: Format
    public var explanation: String

    public init(id: UUID = UUID(), type: QuizType, cardID: UUID?, prompt: String, audioText: String? = nil,
                format: Format, explanation: String = "") {
        self.id = id
        self.type = type
        self.cardID = cardID
        self.prompt = prompt
        self.audioText = audioText
        self.format = format
        self.explanation = explanation
    }
}

public struct QuizCardInput: Sendable, Hashable {
    public var id: UUID
    public var content: CardContent
    public init(id: UUID, content: CardContent) {
        self.id = id
        self.content = content
    }
}

public enum AnswerGrade: Equatable, Sendable {
    case correct
    /// Right word, minor typo or missing accent.
    case almostCorrect(expected: String)
    case incorrect(expected: String)

    public var isAcceptable: Bool {
        if case .incorrect = self { return false }
        return true
    }
}

/// Generates quizzes from a lesson's cards (deterministic, offline) and grades answers.
/// Reading comprehension uses the AI provider when available.
public struct QuizEngine {
    /// Type-erased generator so tests can inject a seeded one.
    struct AnyGenerator: RandomNumberGenerator {
        var base: any RandomNumberGenerator
        mutating func next() -> UInt64 { base.next() }
    }

    private var generator: AnyGenerator

    public init<G: RandomNumberGenerator>(generator: G) {
        self.generator = AnyGenerator(base: generator)
    }

    public init() {
        self.generator = AnyGenerator(base: SystemRandomNumberGenerator())
    }

    public mutating func makeQuiz(type: QuizType, cards: [QuizCardInput], count: Int = 10) -> [QuizQuestion] {
        let vocabulary = cards.compactMap { card -> (UUID, VocabularyContent)? in
            if case .vocabulary(let v) = card.content { return (card.id, v) }
            return nil
        }
        let grammar = cards.compactMap { card -> (UUID, GrammarContent)? in
            if case .grammar(let g) = card.content { return (card.id, g) }
            return nil
        }
        var questions: [QuizQuestion] = []

        switch type {
        case .multipleChoice, .vocabularyChallenge:
            for (id, v) in vocabulary.shuffled(using: &generator) where !v.translation.isEmpty || !v.definition.isEmpty {
                let answer = v.translation.isEmpty ? v.definition : v.translation
                let pool = vocabulary.filter { $0.0 != id }.map { $0.1.translation.isEmpty ? $0.1.definition : $0.1.translation }
                guard let options = choiceOptions(correct: answer, pool: pool) else { continue }
                questions.append(QuizQuestion(type: type, cardID: id, prompt: v.term,
                                              format: .choice(options: options.0, correctIndex: options.1),
                                              explanation: v.definition))
            }
            if type == .vocabularyChallenge {
                // Reverse direction: meaning → term.
                for (id, v) in vocabulary.shuffled(using: &generator) where !v.translation.isEmpty {
                    let pool = vocabulary.filter { $0.0 != id }.map(\.1.term)
                    guard let options = choiceOptions(correct: v.term, pool: pool) else { continue }
                    questions.append(QuizQuestion(type: type, cardID: id, prompt: v.translation,
                                                  format: .choice(options: options.0, correctIndex: options.1)))
                }
                questions.shuffle(using: &generator)
            }

        case .fillInTheBlank:
            for (id, v) in vocabulary.shuffled(using: &generator) {
                guard let blanked = Self.blank(term: v.term, in: v.example) else { continue }
                questions.append(QuizQuestion(type: type, cardID: id, prompt: blanked,
                                              format: .typed(acceptedAnswers: [v.term]),
                                              explanation: v.translation))
            }

        case .listening:
            for (id, v) in vocabulary.shuffled(using: &generator) {
                questions.append(QuizQuestion(type: type, cardID: id, prompt: "Type the word you hear.",
                                              audioText: v.term, format: .typed(acceptedAnswers: [v.term]),
                                              explanation: v.translation))
            }

        case .speaking:
            for (id, v) in vocabulary.shuffled(using: &generator) where !v.translation.isEmpty {
                questions.append(QuizQuestion(type: type, cardID: id, prompt: "Say in the target language: \(v.translation)",
                                              format: .spoken(expected: v.term), explanation: v.ipa))
            }
            for card in cards {
                if case .speaking(let s) = card.content {
                    questions.append(QuizQuestion(type: type, cardID: card.id, prompt: s.prompt,
                                                  format: .spoken(expected: s.sampleAnswer), explanation: s.sampleAnswer))
                }
            }

        case .translation:
            for (id, v) in vocabulary.shuffled(using: &generator) where !v.exampleTranslation.isEmpty && !v.example.isEmpty {
                questions.append(QuizQuestion(type: type, cardID: id, prompt: v.exampleTranslation,
                                              format: .typed(acceptedAnswers: [v.example]), explanation: v.example))
            }
            for (id, v) in vocabulary.shuffled(using: &generator) where !v.translation.isEmpty {
                questions.append(QuizQuestion(type: type, cardID: id, prompt: v.translation,
                                              format: .typed(acceptedAnswers: [v.term] + v.synonyms)))
            }

        case .typing:
            for (id, v) in vocabulary.shuffled(using: &generator) {
                let clue = [v.translation, v.definition].filter { !$0.isEmpty }.joined(separator: " — ")
                guard !clue.isEmpty else { continue }
                questions.append(QuizQuestion(type: type, cardID: id, prompt: clue,
                                              format: .typed(acceptedAnswers: [v.term]), explanation: v.example))
            }

        case .grammarChallenge:
            for (id, g) in grammar.shuffled(using: &generator) {
                // Pick the correct sentence vs. typical mistakes.
                for mistake in g.commonMistakes {
                    let parts = mistake.replacingOccurrences(of: "✗", with: "").replacingOccurrences(of: "✓", with: "")
                        .components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
                    var options = [parts[1], parts[0]]
                    options.shuffle(using: &generator)
                    questions.append(QuizQuestion(type: type, cardID: id, prompt: "Which sentence is correct? (\(g.rule))",
                                                  format: .choice(options: options, correctIndex: options.firstIndex(of: parts[1]) ?? 0),
                                                  explanation: g.explanation))
                }
                if let example = g.examples.first, !g.formula.isEmpty {
                    let pool = grammar.filter { $0.0 != id }.map(\.1.rule)
                    if let options = choiceOptions(correct: g.rule, pool: pool, count: min(4, pool.count + 1)) {
                        questions.append(QuizQuestion(type: type, cardID: id, prompt: "Which grammar point does this show?\n“\(example)”",
                                                      format: .choice(options: options.0, correctIndex: options.1),
                                                      explanation: g.formula))
                    }
                }
            }
            questions.shuffle(using: &generator)

        case .readingComprehension:
            for card in cards {
                if case .reading(let r) = card.content {
                    questions.append(QuizQuestion(type: type, cardID: card.id,
                                                  prompt: r.passageExcerpt.isEmpty ? r.question : "\(r.passageExcerpt)\n\n\(r.question)",
                                                  format: .typed(acceptedAnswers: [r.answer]), explanation: r.explanation))
                }
            }
        }
        return Array(questions.prefix(count))
    }

    /// Builds four options (or `count`) with the correct answer at a random index.
    mutating func choiceOptions(correct: String, pool: [String], count: Int = 4) -> ([String], Int)? {
        let correctKey = TextNormalizer.searchKey(correct)
        var distractors: [String] = []
        var seen: Set<String> = [correctKey]
        for candidate in pool.shuffled(using: &generator) {
            let key = TextNormalizer.searchKey(candidate)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            distractors.append(candidate)
            if distractors.count == count - 1 { break }
        }
        guard distractors.count >= 1 else { return nil }
        let index = Int.random(in: 0...distractors.count, using: &generator)
        var options = distractors
        options.insert(correct, at: index)
        return (options, index)
    }

    /// Replaces the term (or an inflected form starting with it) with a blank.
    public static func blank(term: String, in sentence: String) -> String? {
        guard !sentence.isEmpty, !term.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "\\b\(escaped)\\w*"
        guard let range = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return sentence.replacingCharacters(in: range, with: "_____")
    }

    // MARK: Grading

    public static func grade(_ answer: String, accepted: [String]) -> AnswerGrade {
        let given = TextNormalizer.searchKey(answer.trimmingCharacters(in: .punctuationCharacters))
        let expected = accepted.first ?? ""
        guard !given.isEmpty else { return .incorrect(expected: expected) }
        for candidate in accepted {
            let key = TextNormalizer.searchKey(candidate.trimmingCharacters(in: .punctuationCharacters))
            if key == given {
                // Exact after folding; check whether accents/case differed.
                let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
                let strictEqual = answer.trimmingCharacters(in: trimSet).lowercased()
                    == candidate.trimmingCharacters(in: trimSet).lowercased()
                return strictEqual ? .correct : .almostCorrect(expected: candidate)
            }
            let tolerance = key.count <= 4 ? 0 : key.count <= 8 ? 1 : 2
            if TextNormalizer.editDistance(key, given) <= tolerance { return .almostCorrect(expected: candidate) }
        }
        return .incorrect(expected: expected)
    }

    public static func grade(choice: Int, question: QuizQuestion) -> AnswerGrade {
        guard case .choice(let options, let correct) = question.format else { return .incorrect(expected: "") }
        return choice == correct ? .correct : .incorrect(expected: options[correct])
    }

    /// Grades a spoken answer from a speech-recognition transcript. Longer
    /// expected answers (sample answers) are graded on content-word overlap.
    public static func gradeSpoken(transcript: String, expected: String) -> AnswerGrade {
        let expectedTokens = TextNormalizer.tokens(TextNormalizer.searchKey(expected))
        if expectedTokens.count <= 3 { return grade(transcript, accepted: [expected]) }
        let given = Set(TextNormalizer.tokens(TextNormalizer.searchKey(transcript)))
        let content = expectedTokens.filter { $0.count > 3 }
        guard !content.isEmpty else { return grade(transcript, accepted: [expected]) }
        let overlap = Double(content.filter(given.contains).count) / Double(content.count)
        if overlap >= 0.6 { return .correct }
        if overlap >= 0.35 { return .almostCorrect(expected: expected) }
        return .incorrect(expected: expected)
    }
}

/// AI-generated reading comprehension (multiple choice) from a passage.
public struct ReadingQuizGenerator: Sendable {
    public var provider: any AIProvider
    public init(provider: any AIProvider) { self.provider = provider }

    private struct Payload: Decodable {
        struct Question: Decodable {
            var question: String
            var options: [String]
            var correctIndex: Int
            var explanation: String
        }
        var questions: [Question]
    }

    public func generate(passage: String, count: Int = 5) async throws -> [QuizQuestion] {
        let response = try await provider.complete(AIRequest(
            system: PromptLibrary.readingQuizSystemPrompt,
            user: "Write \(count) questions.\n\nPassage:\n<<<\n\(passage.prefix(10_000))\n>>>",
            schema: PromptLibrary.readingQuizSchema, maxOutputTokens: 3_000))
        return try response.decode(Payload.self).questions.compactMap { q in
            guard q.options.count >= 2, q.options.indices.contains(q.correctIndex) else { return nil }
            return QuizQuestion(type: .readingComprehension, cardID: nil, prompt: q.question,
                                format: .choice(options: q.options, correctIndex: q.correctIndex), explanation: q.explanation)
        }
    }
}
