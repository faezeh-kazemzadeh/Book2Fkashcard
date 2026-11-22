import Foundation

/// Learner profile that shapes generation.
public struct GenerationOptions: Sendable, Hashable {
    public enum CEFRLevel: String, Codable, CaseIterable, Sendable { case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1", c2 = "C2" }

    public var targetLanguage: StudyLanguage
    public var nativeLanguage: StudyLanguage
    public var accent: EnglishAccent
    public var level: CEFRLevel
    public var kinds: Set<CardKind>
    public var maxVocabulary: Int
    public var maxGrammar: Int
    public var maxReading: Int
    public var maxSpeaking: Int
    /// Exam focus ("IELTS", "TOEFL", "Goethe B1"...), optional.
    public var examFocus: String?

    public init(targetLanguage: StudyLanguage = .english, nativeLanguage: StudyLanguage = .persian,
                accent: EnglishAccent = .american, level: CEFRLevel = .b1,
                kinds: Set<CardKind> = [.vocabulary, .grammar, .reading, .speaking],
                maxVocabulary: Int = 25, maxGrammar: Int = 5, maxReading: Int = 4, maxSpeaking: Int = 3,
                examFocus: String? = nil) {
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.accent = accent
        self.level = level
        self.kinds = kinds
        self.maxVocabulary = maxVocabulary
        self.maxGrammar = maxGrammar
        self.maxReading = maxReading
        self.maxSpeaking = maxSpeaking
        self.examFocus = examFocus
    }
}

/// Central place for prompts and JSON schemas. Versioned so cached results
/// can be invalidated when prompts change.
public enum PromptLibrary {
    public static let version = "2026.11.1"

    // MARK: Card generation

    public static func cardGenerationSystemPrompt(_ o: GenerationOptions) -> String {
        """
        You are an expert \(o.targetLanguage.englishName) teacher and lexicographer building study material for a \
        \(o.level.rawValue)-level learner whose native language is \(o.nativeLanguage.englishName).\
        \(o.examFocus.map { " The learner is preparing for \($0)." } ?? "")

        You receive text extracted by OCR from one lesson of a language textbook. OCR may contain errors; silently \
        correct obvious recognition mistakes, but never invent content unrelated to the lesson.

        Quality rules:
        - Vocabulary: choose words and multi-word expressions that are worth memorising at this level: \
        academic and exam vocabulary, topic-specific terms, collocations, phrasal verbs, idioms, and words the book \
        itself highlights. NEVER include articles, pronouns, auxiliaries, prepositions, numbers, names, or extremely \
        common words (e.g. "the", "go", "good", "house"). No duplicates or mere inflections of the same lemma.
        - Prefer words listed in the provided vocabulary boxes; use the candidate list as hints, not as an obligation.
        - translation: natural \(o.nativeLanguage.englishName) equivalent(s) for the sense used in the lesson.
        - definition: a short learner's-dictionary definition in \(o.targetLanguage.englishName).
        - ipa: \(o.targetLanguage == .english ? (o.accent == .british ? "British (RP)" : "General American") + " IPA" : "standard IPA") without slashes.
        - pronunciation: a simple respelling a learner can read (e.g. "ab-SORB").
        - example: a new natural sentence (not copied from the book) using the word in the lesson's sense; \
        exampleTranslation: its \(o.nativeLanguage.englishName) translation.
        - synonyms/antonyms: 0–3 each, same register; empty when none fit.
        - Grammar: one card per grammar point actually taught in the lesson. rule = short name of the point; \
        formula = structure pattern (e.g. "subject + have/has + past participle"); 2–3 examples; 1–3 typical learner \
        mistakes written as "✗ wrong → ✓ right", especially those typical for \(o.nativeLanguage.englishName) speakers.
        - Reading: comprehension questions answerable only from the lesson's reading text; include a short \
        passageExcerpt (≤ 200 characters) that supports the answer.
        - Speaking: open prompts that make the learner reuse the lesson's vocabulary and grammar, with a model answer \
        of 2–4 sentences at \(o.level.rawValue) level and useful phrases.
        - priority: "essential" for words the book highlights or exam-critical items, "high" for strong topic words, \
        "normal" otherwise, "low" for marginal items.
        - confidence: 0–1, how sure you are the item is correct given possible OCR errors.
        Return at most \(o.maxVocabulary) vocabulary, \(o.maxGrammar) grammar, \(o.maxReading) reading and \
        \(o.maxSpeaking) speaking items. Return empty arrays for card types not requested or not present.
        """
    }

    public static func cardGenerationUserPrompt(bookTitle: String, unitTitle: String, lessonTitle: String,
                                                lessonText: String, vocabularyHints: [VocabularyCandidate],
                                                kinds: Set<CardKind>) -> String {
        let requested = CardKind.allCases.filter { kinds.contains($0) && $0 != .basic }.map(\.rawValue).joined(separator: ", ")
        let hints = vocabularyHints.prefix(60).map { candidate -> String in
            var line = "- \(candidate.term)"
            if let translation = candidate.inlineTranslation { line += " — book gloss: \(translation)" }
            if candidate.fromVocabularyList { line += " [vocabulary box]" }
            return line
        }.joined(separator: "\n")
        return """
        Book: \(bookTitle)
        Unit: \(unitTitle)
        Lesson: \(lessonTitle)
        Requested card types: \(requested)

        Candidate vocabulary (pre-filtered, ranked):
        \(hints.isEmpty ? "(none)" : hints)

        Lesson text:
        <<<
        \(lessonText)
        >>>
        """
    }

    public static let cardGenerationSchema: StructuredOutputSchema = {
        let priority = JSONSchemaBuilder.enumeration(["essential", "high", "normal", "low"])
        let vocabulary = JSONSchemaBuilder.object([
            ("term", JSONSchemaBuilder.string), ("translation", JSONSchemaBuilder.string), ("definition", JSONSchemaBuilder.string),
            ("ipa", JSONSchemaBuilder.string), ("pronunciation", JSONSchemaBuilder.string), ("partOfSpeech", JSONSchemaBuilder.string),
            ("example", JSONSchemaBuilder.string), ("exampleTranslation", JSONSchemaBuilder.string),
            ("synonyms", JSONSchemaBuilder.array(JSONSchemaBuilder.string)), ("antonyms", JSONSchemaBuilder.array(JSONSchemaBuilder.string)),
            ("priority", priority), ("confidence", JSONSchemaBuilder.number)
        ])
        let grammar = JSONSchemaBuilder.object([
            ("rule", JSONSchemaBuilder.string), ("explanation", JSONSchemaBuilder.string), ("formula", JSONSchemaBuilder.string),
            ("examples", JSONSchemaBuilder.array(JSONSchemaBuilder.string)), ("commonMistakes", JSONSchemaBuilder.array(JSONSchemaBuilder.string)),
            ("priority", priority), ("confidence", JSONSchemaBuilder.number)
        ])
        let reading = JSONSchemaBuilder.object([
            ("question", JSONSchemaBuilder.string), ("answer", JSONSchemaBuilder.string), ("explanation", JSONSchemaBuilder.string),
            ("passageExcerpt", JSONSchemaBuilder.string), ("confidence", JSONSchemaBuilder.number)
        ])
        let speaking = JSONSchemaBuilder.object([
            ("prompt", JSONSchemaBuilder.string), ("sampleAnswer", JSONSchemaBuilder.string),
            ("usefulPhrases", JSONSchemaBuilder.array(JSONSchemaBuilder.string)), ("confidence", JSONSchemaBuilder.number)
        ])
        return StructuredOutputSchema(name: "lesson_flashcards", schema: JSONSchemaBuilder.object([
            ("vocabulary", JSONSchemaBuilder.array(vocabulary)), ("grammar", JSONSchemaBuilder.array(grammar)),
            ("reading", JSONSchemaBuilder.array(reading)), ("speaking", JSONSchemaBuilder.array(speaking))
        ]))
    }()

    // MARK: Lesson refinement

    public static let lessonRefinementSystemPrompt = """
    You organise OCR-extracted language textbooks. You receive a draft table of contents with numbered lessons, \
    each with its section headings and opening lines. Return clean lesson titles (fix OCR errors, keep the book's \
    numbering such as "1A"), and classify every section as one of: vocabulary, grammar, reading, listening, \
    speaking, writing, exercises, general. Keep the same lesson indices and section order. Do not invent lessons.
    """

    public static let lessonRefinementSchema = StructuredOutputSchema(name: "lesson_outline", schema: JSONSchemaBuilder.object([
        ("lessons", JSONSchemaBuilder.array(JSONSchemaBuilder.object([
            ("index", JSONSchemaBuilder.integer),
            ("title", JSONSchemaBuilder.string),
            ("sectionKinds", JSONSchemaBuilder.array(JSONSchemaBuilder.enumeration(LessonSectionKind.allCases.map(\.rawValue))))
        ])))
    ]))

    // MARK: Quizzes

    public static let readingQuizSystemPrompt = """
    You write reading-comprehension questions for language learners. Questions must be answerable from the passage \
    alone. Each question has exactly four options, one correct, with plausible distractors drawn from the passage. \
    Explanations quote or paraphrase the supporting sentence.
    """

    public static let readingQuizSchema = StructuredOutputSchema(name: "reading_quiz", schema: JSONSchemaBuilder.object([
        ("questions", JSONSchemaBuilder.array(JSONSchemaBuilder.object([
            ("question", JSONSchemaBuilder.string),
            ("options", JSONSchemaBuilder.array(JSONSchemaBuilder.string)),
            ("correctIndex", JSONSchemaBuilder.integer),
            ("explanation", JSONSchemaBuilder.string)
        ])))
    ]))

    // MARK: Explanations & OCR

    public static func explanationSystemPrompt(_ o: GenerationOptions) -> String {
        """
        You are a patient \(o.targetLanguage.englishName) tutor. Explain the item for a \(o.level.rawValue) learner \
        whose native language is \(o.nativeLanguage.englishName). Cover meaning, usage, register, common collocations \
        and a typical mistake. Use short paragraphs and at most 150 words. Write the explanation in \
        \(o.nativeLanguage.englishName) and give examples in \(o.targetLanguage.englishName).
        """
    }

    public static func ocrCorrectionSystemPrompt(languages: [StudyLanguage]) -> String {
        """
        You transcribe photographed textbook pages. Languages present: \(languages.map(\.englishName).joined(separator: ", ")). \
        Output the page text exactly as printed, preserving line breaks, headings, tables (as tab-separated rows) and \
        numbering. Use standard \(languages.contains(.persian) ? "Persian orthography (ی, ک, ZWNJ where appropriate)" : "orthography"). \
        Do not translate, summarise or add commentary.
        """
    }
}

/// Helpers that produce strict-mode-compatible JSON Schemas
/// (every property required, `additionalProperties: false`).
public enum JSONSchemaBuilder {
    public static let string: JSONValue = .object(["type": .string("string")])
    public static let number: JSONValue = .object(["type": .string("number")])
    public static let integer: JSONValue = .object(["type": .string("integer")])

    public static func array(_ items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items])
    }

    public static func enumeration(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))])
    }

    public static func object(_ properties: [(String, JSONValue)]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(Dictionary(uniqueKeysWithValues: properties)),
            "required": .array(properties.map { .string($0.0) }),
            "additionalProperties": .bool(false)
        ])
    }
}
