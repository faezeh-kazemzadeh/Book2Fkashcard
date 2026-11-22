import Foundation

/// The four generated card families plus generic cards that come from Anki imports.
public enum CardKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case vocabulary
    case grammar
    case reading
    case speaking
    case basic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vocabulary: return "Vocabulary"
        case .grammar: return "Grammar"
        case .reading: return "Reading"
        case .speaking: return "Speaking"
        case .basic: return "Basic"
        }
    }
}

/// How valuable a card is for a serious learner. Used for ordering new cards
/// and for the quality filter.
public enum LearningPriority: Int, Codable, Comparable, CaseIterable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case essential = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct VocabularyContent: Codable, Hashable, Sendable {
    public var term: String
    public var translation: String
    public var definition: String
    public var ipa: String
    public var pronunciation: String
    public var partOfSpeech: String
    public var example: String
    public var exampleTranslation: String
    public var synonyms: [String]
    public var antonyms: [String]

    public init(term: String, translation: String = "", definition: String = "", ipa: String = "",
                pronunciation: String = "", partOfSpeech: String = "", example: String = "",
                exampleTranslation: String = "", synonyms: [String] = [], antonyms: [String] = []) {
        self.term = term
        self.translation = translation
        self.definition = definition
        self.ipa = ipa
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.synonyms = synonyms
        self.antonyms = antonyms
    }
}

public struct GrammarContent: Codable, Hashable, Sendable {
    public var rule: String
    public var explanation: String
    public var formula: String
    public var examples: [String]
    public var commonMistakes: [String]

    public init(rule: String, explanation: String = "", formula: String = "",
                examples: [String] = [], commonMistakes: [String] = []) {
        self.rule = rule
        self.explanation = explanation
        self.formula = formula
        self.examples = examples
        self.commonMistakes = commonMistakes
    }
}

public struct ReadingContent: Codable, Hashable, Sendable {
    public var question: String
    public var answer: String
    public var explanation: String
    public var passageExcerpt: String

    public init(question: String, answer: String, explanation: String = "", passageExcerpt: String = "") {
        self.question = question
        self.answer = answer
        self.explanation = explanation
        self.passageExcerpt = passageExcerpt
    }
}

public struct SpeakingContent: Codable, Hashable, Sendable {
    public var prompt: String
    public var sampleAnswer: String
    public var usefulPhrases: [String]

    public init(prompt: String, sampleAnswer: String, usefulPhrases: [String] = []) {
        self.prompt = prompt
        self.sampleAnswer = sampleAnswer
        self.usefulPhrases = usefulPhrases
    }
}

public struct BasicContent: Codable, Hashable, Sendable {
    public var front: String
    public var back: String
    public var extra: String

    public init(front: String, back: String, extra: String = "") {
        self.front = front
        self.back = back
        self.extra = extra
    }
}

/// Type-safe card payload. Persisted as JSON so new kinds can be added without
/// a database migration.
public enum CardContent: Codable, Hashable, Sendable {
    case vocabulary(VocabularyContent)
    case grammar(GrammarContent)
    case reading(ReadingContent)
    case speaking(SpeakingContent)
    case basic(BasicContent)

    public var kind: CardKind {
        switch self {
        case .vocabulary: return .vocabulary
        case .grammar: return .grammar
        case .reading: return .reading
        case .speaking: return .speaking
        case .basic: return .basic
        }
    }

    /// Plain text for the question side. Used for search, accessibility and quizzes.
    public var frontText: String {
        switch self {
        case .vocabulary(let v): return v.term
        case .grammar(let g): return g.rule
        case .reading(let r): return r.question
        case .speaking(let s): return s.prompt
        case .basic(let b): return b.front
        }
    }

    /// Plain multi-line text for the answer side.
    public var backText: String {
        switch self {
        case .vocabulary(let v):
            return [
                v.translation,
                v.partOfSpeech.isEmpty ? "" : "(\(v.partOfSpeech))",
                v.ipa.isEmpty ? "" : "/\(v.ipa.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/",
                v.definition,
                v.example,
                v.exampleTranslation,
                v.synonyms.isEmpty ? "" : "Synonyms: " + v.synonyms.joined(separator: ", "),
                v.antonyms.isEmpty ? "" : "Antonyms: " + v.antonyms.joined(separator: ", ")
            ].filter { !$0.isEmpty }.joined(separator: "\n")
        case .grammar(let g):
            return ([g.explanation, g.formula] + g.examples.map { "• " + $0 }
                    + g.commonMistakes.map { "✗ " + $0 })
                .filter { !$0.isEmpty }.joined(separator: "\n")
        case .reading(let r):
            return [r.answer, r.explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        case .speaking(let s):
            return ([s.sampleAnswer] + s.usefulPhrases.map { "• " + $0 })
                .filter { !$0.isEmpty }.joined(separator: "\n")
        case .basic(let b):
            return [b.back, b.extra].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    /// Text used to detect duplicates across a deck.
    public var deduplicationKey: String {
        TextNormalizer.searchKey(kind.rawValue + "|" + frontText)
    }

    // MARK: Codable (discriminated union)

    private enum CodingKeys: String, CodingKey { case kind, payload }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(CardKind.self, forKey: .kind)
        switch kind {
        case .vocabulary: self = .vocabulary(try container.decode(VocabularyContent.self, forKey: .payload))
        case .grammar: self = .grammar(try container.decode(GrammarContent.self, forKey: .payload))
        case .reading: self = .reading(try container.decode(ReadingContent.self, forKey: .payload))
        case .speaking: self = .speaking(try container.decode(SpeakingContent.self, forKey: .payload))
        case .basic: self = .basic(try container.decode(BasicContent.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .vocabulary(let v): try container.encode(v, forKey: .payload)
        case .grammar(let g): try container.encode(g, forKey: .payload)
        case .reading(let r): try container.encode(r, forKey: .payload)
        case .speaking(let s): try container.encode(s, forKey: .payload)
        case .basic(let b): try container.encode(b, forKey: .payload)
        }
    }
}

/// A card before it is persisted. Produced by the AI generator, the offline
/// heuristic generator and the Anki/CSV importers.
public struct FlashcardDraft: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var content: CardContent
    public var tags: [String]
    public var priority: LearningPriority
    /// 0...1. Confidence that the card is correct (OCR confidence × model self-rating).
    public var confidence: Double
    /// Media file names (relative to the media folder) referenced by this card.
    public var audioFileName: String?
    public var imageFileName: String?
    /// Imported scheduling, when the source (e.g. an Anki deck) carried review state.
    public var scheduling: SchedulingState?

    public init(id: UUID = UUID(), content: CardContent, tags: [String] = [],
                priority: LearningPriority = .normal, confidence: Double = 1,
                audioFileName: String? = nil, imageFileName: String? = nil,
                scheduling: SchedulingState? = nil) {
        self.id = id
        self.content = content
        self.tags = tags
        self.priority = priority
        self.confidence = confidence
        self.audioFileName = audioFileName
        self.imageFileName = imageFileName
        self.scheduling = scheduling
    }

    public var kind: CardKind { content.kind }
}
