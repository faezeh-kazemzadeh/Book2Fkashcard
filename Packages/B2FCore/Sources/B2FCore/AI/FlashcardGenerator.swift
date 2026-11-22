import Foundation

public struct GenerationResult: Sendable {
    public var drafts: [FlashcardDraft]
    public var usedAI: Bool
    public var warnings: [String]
    public var usage: AIUsage?
}

/// Produces flashcards for a lesson.
///
/// Pipeline:
/// 1. The quality filter extracts and ranks vocabulary candidates (offline).
/// 2. If an AI provider is available, the lesson is sent in chunks with the
///    candidates as hints and a strict JSON schema; otherwise the offline
///    `HeuristicCardGenerator` builds cards from vocabulary lists and grammar boxes.
/// 3. Results pass the quality filter again (low-value words, duplicates,
///    empty answers) and are tagged with the Book/Unit/Lesson hierarchy.
public struct FlashcardGenerator: Sendable {
    public var provider: (any AIProvider)?
    public var options: GenerationOptions
    /// Lesson text is split into chunks of at most this many characters.
    public var maxCharactersPerRequest: Int

    public init(provider: (any AIProvider)?, options: GenerationOptions, maxCharactersPerRequest: Int = 12_000) {
        self.provider = provider
        self.options = options
        self.maxCharactersPerRequest = maxCharactersPerRequest
    }

    public func generate(for lesson: LessonNode, bookTitle: String, unitTitle: String,
                         existingKeys: Set<String> = []) async throws -> GenerationResult {
        let filter = VocabularyQualityFilter(configuration: .init(language: options.targetLanguage,
                                                                   maximumCandidates: options.maxVocabulary * 2))
        let vocabRows = lesson.sections.flatMap(\.blocks).filter { $0.kind == .vocabularyList || $0.kind == .table }.flatMap(\.rows)
        let candidates = filter.candidates(fromText: lesson.fullText, vocabularyRows: vocabRows)
        let sourceConfidence = averageConfidence(lesson)
        let tags = hierarchyTags(book: bookTitle, unit: unitTitle, lesson: lesson.title)

        var drafts: [FlashcardDraft] = []
        var warnings: [String] = []
        var usage: AIUsage?
        var usedAI = false

        if let provider {
            let chunks = chunk(lesson)
            let share = max(chunks.count, 1)
            var chunkOptions = options
            chunkOptions.maxVocabulary = max(5, options.maxVocabulary / share)
            chunkOptions.maxGrammar = max(1, options.maxGrammar / share)
            chunkOptions.maxReading = max(1, options.maxReading / share)
            chunkOptions.maxSpeaking = max(1, options.maxSpeaking / share)

            for text in chunks {
                let request = AIRequest(
                    system: PromptLibrary.cardGenerationSystemPrompt(chunkOptions),
                    user: PromptLibrary.cardGenerationUserPrompt(bookTitle: bookTitle, unitTitle: unitTitle,
                                                                 lessonTitle: lesson.title, lessonText: text,
                                                                 vocabularyHints: candidates, kinds: options.kinds),
                    schema: PromptLibrary.cardGenerationSchema,
                    maxOutputTokens: 8_000)
                do {
                    let response = try await provider.complete(request)
                    let payload = try response.decode(GeneratedLessonPayload.self)
                    drafts += payload.drafts(kinds: options.kinds, tags: tags, sourceConfidence: sourceConfidence)
                    usedAI = true
                    if let u = response.usage {
                        usage = AIUsage(inputTokens: (usage?.inputTokens ?? 0) + u.inputTokens,
                                        outputTokens: (usage?.outputTokens ?? 0) + u.outputTokens)
                    }
                } catch let error as AIError where error == .unauthorized || error == .notConfigured {
                    throw error
                } catch {
                    warnings.append("Part of “\(lesson.title)” could not be processed by AI: \(error.localizedDescription)")
                }
            }
        }

        if !usedAI {
            if provider != nil { warnings.append("Used offline card generation for “\(lesson.title)”.") }
            drafts = HeuristicCardGenerator(options: options)
                .generate(lesson: lesson, candidates: candidates, tags: tags, sourceConfidence: sourceConfidence)
        }

        let filtered = filter.filterDrafts(drafts, existingKeys: existingKeys)
        return GenerationResult(drafts: filtered, usedAI: usedAI, warnings: warnings, usage: usage)
    }

    // MARK: Helpers

    func chunk(_ lesson: LessonNode) -> [String] {
        var chunks: [String] = []
        var current = ""
        for section in lesson.sections {
            let piece = "## \(section.title) [\(section.kind.rawValue)]\n\(section.text)\n\n"
            if current.count + piece.count > maxCharactersPerRequest && !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            if piece.count > maxCharactersPerRequest {
                var start = piece.startIndex
                while start < piece.endIndex {
                    let end = piece.index(start, offsetBy: maxCharactersPerRequest, limitedBy: piece.endIndex) ?? piece.endIndex
                    chunks.append(String(piece[start..<end]))
                    start = end
                }
            } else {
                current += piece
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func averageConfidence(_ lesson: LessonNode) -> Double {
        let blocks = lesson.sections.flatMap(\.blocks)
        guard !blocks.isEmpty else { return 1 }
        return blocks.map(\.confidence).reduce(0, +) / Double(blocks.count)
    }

    public func hierarchyTags(book: String, unit: String, lesson: String) -> [String] {
        func tagify(_ s: String) -> String {
            TextNormalizer.collapseWhitespace(s).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "::", with: "_")
        }
        return ["B2F", "B2F::\(tagify(book))::\(tagify(unit))::\(tagify(lesson))"]
    }
}

// MARK: - AI payload

struct GeneratedLessonPayload: Decodable {
    struct Vocabulary: Decodable {
        var term: String
        var translation: String
        var definition: String
        var ipa: String
        var pronunciation: String
        var partOfSpeech: String
        var example: String
        var exampleTranslation: String
        var synonyms: [String]
        var antonyms: [String]
        var priority: String?
        var confidence: Double?
    }
    struct Grammar: Decodable {
        var rule: String
        var explanation: String
        var formula: String
        var examples: [String]
        var commonMistakes: [String]
        var priority: String?
        var confidence: Double?
    }
    struct Reading: Decodable {
        var question: String
        var answer: String
        var explanation: String
        var passageExcerpt: String
        var confidence: Double?
    }
    struct Speaking: Decodable {
        var prompt: String
        var sampleAnswer: String
        var usefulPhrases: [String]
        var confidence: Double?
    }

    var vocabulary: [Vocabulary]
    var grammar: [Grammar]
    var reading: [Reading]
    var speaking: [Speaking]

    static func priority(_ raw: String?) -> LearningPriority {
        switch raw {
        case "essential": return .essential
        case "high": return .high
        case "low": return .low
        default: return .normal
        }
    }

    func drafts(kinds: Set<CardKind>, tags: [String], sourceConfidence: Double) -> [FlashcardDraft] {
        func conf(_ c: Double?) -> Double { min(max(c ?? 0.8, 0), 1) * min(1, sourceConfidence + 0.2) }
        var result: [FlashcardDraft] = []
        if kinds.contains(.vocabulary) {
            result += vocabulary.map {
                FlashcardDraft(content: .vocabulary(VocabularyContent(
                    term: $0.term, translation: $0.translation, definition: $0.definition, ipa: $0.ipa,
                    pronunciation: $0.pronunciation, partOfSpeech: $0.partOfSpeech, example: $0.example,
                    exampleTranslation: $0.exampleTranslation, synonyms: $0.synonyms, antonyms: $0.antonyms)),
                    tags: tags + ["vocabulary"], priority: Self.priority($0.priority), confidence: conf($0.confidence))
            }
        }
        if kinds.contains(.grammar) {
            result += grammar.map {
                FlashcardDraft(content: .grammar(GrammarContent(rule: $0.rule, explanation: $0.explanation, formula: $0.formula,
                                                                examples: $0.examples, commonMistakes: $0.commonMistakes)),
                               tags: tags + ["grammar"], priority: Self.priority($0.priority), confidence: conf($0.confidence))
            }
        }
        if kinds.contains(.reading) {
            result += reading.map {
                FlashcardDraft(content: .reading(ReadingContent(question: $0.question, answer: $0.answer,
                                                                explanation: $0.explanation, passageExcerpt: $0.passageExcerpt)),
                               tags: tags + ["reading"], priority: .normal, confidence: conf($0.confidence))
            }
        }
        if kinds.contains(.speaking) {
            result += speaking.map {
                FlashcardDraft(content: .speaking(SpeakingContent(prompt: $0.prompt, sampleAnswer: $0.sampleAnswer,
                                                                  usefulPhrases: $0.usefulPhrases)),
                               tags: tags + ["speaking"], priority: .normal, confidence: conf($0.confidence))
            }
        }
        return result
    }
}

// MARK: - Offline generator

/// Builds cards without AI from what the book itself provides: vocabulary
/// lists with glosses and grammar boxes. Used on the free plan, offline, or
/// when the AI call fails.
public struct HeuristicCardGenerator: Sendable {
    public var options: GenerationOptions

    public init(options: GenerationOptions) {
        self.options = options
    }

    public func generate(lesson: LessonNode, candidates: [VocabularyCandidate], tags: [String],
                         sourceConfidence: Double) -> [FlashcardDraft] {
        var drafts: [FlashcardDraft] = []
        if options.kinds.contains(.vocabulary) {
            let contexts = Dictionary(candidates.map { (TextNormalizer.searchKey($0.term), $0.context) },
                                      uniquingKeysWith: { first, _ in first })
            for candidate in candidates.prefix(options.maxVocabulary) {
                guard let gloss = candidate.inlineTranslation, !gloss.isEmpty else { continue }
                let glossLanguage = StudyLanguage.detectScript(of: gloss)
                let isTranslation = glossLanguage == options.nativeLanguage ||
                    (glossLanguage == .arabic && options.nativeLanguage == .persian)
                drafts.append(FlashcardDraft(
                    content: .vocabulary(VocabularyContent(
                        term: candidate.term,
                        translation: isTranslation ? gloss : "",
                        definition: isTranslation ? "" : gloss,
                        example: contexts[TextNormalizer.searchKey(candidate.term)] ?? "")),
                    tags: tags + ["vocabulary", "offline"], priority: candidate.priority,
                    confidence: sourceConfidence * 0.9))
            }
        }
        if options.kinds.contains(.grammar) {
            for block in lesson.sections.flatMap(\.blocks) where block.kind == .grammarBox {
                let lines = block.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard lines.count >= 2 else { continue }
                let headerIsKeyword = LayoutAnalyzer.grammarKeywords.contains { lines[0].lowercased().hasPrefix($0) }
                let rule = headerIsKeyword && lines.count > 2 ? lines[1] : lines[0]
                let body = Array(lines.drop { $0 == lines[0] || $0 == rule })
                let examples = body.filter { $0.range(of: "^[•\\-–*]|^[0-9]+[.)]", options: .regularExpression) != nil }
                let explanation = body.filter { !examples.contains($0) }.joined(separator: " ")
                drafts.append(FlashcardDraft(
                    content: .grammar(GrammarContent(rule: rule, explanation: explanation.isEmpty ? body.joined(separator: " ") : explanation,
                                                     examples: examples)),
                    tags: tags + ["grammar", "offline"], priority: .high, confidence: block.confidence * 0.8))
                if drafts.filter({ $0.kind == .grammar }).count >= options.maxGrammar { break }
            }
        }
        return drafts
    }
}

// MARK: - Lesson refinement

/// Optional AI pass that cleans lesson titles and section types.
public struct AILessonRefiner: Sendable {
    public var provider: any AIProvider

    public init(provider: any AIProvider) {
        self.provider = provider
    }

    private struct Payload: Decodable {
        struct Lesson: Decodable {
            var index: Int
            var title: String
            var sectionKinds: [String]
        }
        var lessons: [Lesson]
    }

    public func refine(_ outline: BookOutline) async throws -> BookOutline {
        var flat: [(unit: Int, lesson: Int)] = []
        var description = ""
        for (u, unit) in outline.units.enumerated() {
            description += "UNIT: \(unit.title)\n"
            for (l, lesson) in unit.lessons.enumerated() {
                let index = flat.count
                flat.append((u, l))
                description += "  [\(index)] \(lesson.title)\n"
                for section in lesson.sections {
                    let opening = section.text.prefix(120).replacingOccurrences(of: "\n", with: " ")
                    description += "    - \(section.title): \(opening)\n"
                }
            }
        }
        guard !flat.isEmpty else { return outline }
        let response = try await provider.complete(AIRequest(
            system: PromptLibrary.lessonRefinementSystemPrompt,
            user: String(description.prefix(24_000)),
            schema: PromptLibrary.lessonRefinementSchema, maxOutputTokens: 4_000))
        let payload = try response.decode(Payload.self)

        var refined = outline
        for item in payload.lessons where item.index >= 0 && item.index < flat.count {
            let (u, l) = flat[item.index]
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { refined.units[u].lessons[l].title = title }
            for (s, raw) in item.sectionKinds.enumerated() where s < refined.units[u].lessons[l].sections.count {
                if let kind = LessonSectionKind(rawValue: raw) { refined.units[u].lessons[l].sections[s].kind = kind }
            }
        }
        return refined
    }
}
