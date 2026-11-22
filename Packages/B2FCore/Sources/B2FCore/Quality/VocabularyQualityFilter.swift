import Foundation

/// A word or phrase proposed for a vocabulary card.
public struct VocabularyCandidate: Hashable, Sendable {
    public var term: String
    /// Sentence the term was found in (helps the AI pick the right sense).
    public var context: String
    /// Occurrences in the lesson.
    public var occurrences: Int
    /// True when the term came from a vocabulary list/box (author-curated).
    public var fromVocabularyList: Bool
    /// Translation found next to the term in the book, if any.
    public var inlineTranslation: String?
    public var score: Double
    public var priority: LearningPriority

    public init(term: String, context: String = "", occurrences: Int = 1, fromVocabularyList: Bool = false,
                inlineTranslation: String? = nil, score: Double = 0, priority: LearningPriority = .normal) {
        self.term = term
        self.context = context
        self.occurrences = occurrences
        self.fromVocabularyList = fromVocabularyList
        self.inlineTranslation = inlineTranslation
        self.score = score
        self.priority = priority
    }
}

/// Decides which words deserve a flashcard.
///
/// Rejects articles, function words, very common words, numbers, OCR garbage
/// and duplicates (including inflectional variants). Ranks the rest so that
/// author-curated vocabulary, academic/exam words and topic-specific terms
/// come first.
public struct VocabularyQualityFilter: Sendable {

    public struct Configuration: Sendable {
        public var language: StudyLanguage
        public var minimumLength: Int
        public var excludeVeryCommonWords: Bool
        public var maximumCandidates: Int
        public var extraStopWords: Set<String>

        public init(language: StudyLanguage, minimumLength: Int = 3, excludeVeryCommonWords: Bool = true,
                    maximumCandidates: Int = 40, extraStopWords: Set<String> = []) {
            self.language = language
            self.minimumLength = minimumLength
            self.excludeVeryCommonWords = excludeVeryCommonWords
            self.maximumCandidates = maximumCandidates
            self.extraStopWords = extraStopWords
        }
    }

    public enum RejectionReason: String, Sendable {
        case stopWord, veryCommon, tooShort, numeric, noise, duplicate, properNoun
    }

    public let configuration: Configuration
    private let stopWords: Set<String>
    private let veryCommon: Set<String>

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.stopWords = Set(WordLists.stopWords(for: configuration.language).map(TextNormalizer.searchKey))
            .union(configuration.extraStopWords.map(TextNormalizer.searchKey))
        self.veryCommon = Set(WordLists.veryCommonWords(for: configuration.language).map(TextNormalizer.searchKey))
    }

    // MARK: Single-term checks

    /// Returns the reason a term should be rejected, or nil if acceptable.
    public func rejectionReason(for rawTerm: String, isSentenceInitial: Bool = true) -> RejectionReason? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let key = TextNormalizer.searchKey(term)
        guard !key.isEmpty else { return .noise }

        let words = key.split(separator: " ").map(String.init)
        if words.allSatisfy({ $0.allSatisfy { $0.isNumber || $0.isPunctuation } }) { return .numeric }

        let letters = term.filter(\.isLetter).count
        if Double(letters) / Double(max(term.count, 1)) < 0.6 { return .noise }
        if hasOCRNoise(term) { return .noise }

        if words.count == 1 {
            if stopWords.contains(key) { return .stopWord }
            if configuration.excludeVeryCommonWords && veryCommon.contains(lemma(key)) { return .veryCommon }
            let minimum = configuration.language.isRightToLeft ? 2 : configuration.minimumLength
            if key.count < minimum { return .tooShort }
            if !isSentenceInitial, let first = term.first, first.isUppercase,
               configuration.language != .german, // German capitalises all nouns
               term.dropFirst().allSatisfy({ $0.isLowercase }) {
                return .properNoun
            }
        } else if words.allSatisfy({ stopWords.contains($0) }) {
            return .stopWord
        }
        return nil
    }

    // MARK: Lesson-level extraction

    /// Extracts and ranks candidates from a lesson's text plus any vocabulary-list rows.
    public func candidates(fromText text: String, vocabularyRows: [[String]] = []) -> [VocabularyCandidate] {
        var byLemma: [String: VocabularyCandidate] = [:]

        // 1. Author-curated vocabulary lists carry the strongest signal.
        for row in vocabularyRows {
            guard let rawTerm = row.first?.trimmingCharacters(in: .whitespaces), !rawTerm.isEmpty else { continue }
            let term = cleanListTerm(rawTerm)
            guard rejectionReason(for: term) == nil || term.contains(" ") else { continue }
            let key = lemma(TextNormalizer.searchKey(term))
            let translation = row.count > 1 ? row[1...].joined(separator: " ").trimmingCharacters(in: .whitespaces) : nil
            var candidate = byLemma[key] ?? VocabularyCandidate(term: term, fromVocabularyList: true)
            candidate.fromVocabularyList = true
            if candidate.inlineTranslation == nil, let translation, !translation.isEmpty {
                candidate.inlineTranslation = translation
            }
            byLemma[key] = candidate
        }

        // 2. Running text: count lemma frequency and keep a context sentence.
        let sentences = splitSentences(text)
        for sentence in sentences {
            let tokens = TextNormalizer.tokens(sentence)
            for (index, token) in tokens.enumerated() {
                guard rejectionReason(for: token, isSentenceInitial: index == 0) == nil else { continue }
                let key = lemma(TextNormalizer.searchKey(token))
                if var existing = byLemma[key] {
                    existing.occurrences += existing.context.isEmpty ? 0 : 1
                    if existing.context.isEmpty { existing.context = sentence }
                    byLemma[key] = existing
                } else {
                    byLemma[key] = VocabularyCandidate(term: token.lowercased(), context: sentence)
                }
            }
        }

        let scored = byLemma.values.map(score)
        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.term < rhs.term
            }
            .prefix(configuration.maximumCandidates)
            .map { $0 }
    }

    /// Filters generated card drafts: drops low-value vocabulary and duplicates,
    /// both within the batch and against `existingKeys` (already-saved cards).
    public func filterDrafts(_ drafts: [FlashcardDraft], existingKeys: Set<String> = []) -> [FlashcardDraft] {
        var seen = existingKeys
        var lemmaSeen = Set(existingKeys.map { lemma($0) })
        var result: [FlashcardDraft] = []
        for draft in drafts {
            let key = draft.content.deduplicationKey
            guard !seen.contains(key) else { continue }
            if case .vocabulary(let vocab) = draft.content {
                if let reason = rejectionReason(for: vocab.term), reason != .properNoun { continue }
                let lemmaKey = "vocabulary|" + lemma(TextNormalizer.searchKey(vocab.term))
                guard !lemmaSeen.contains(lemmaKey) else { continue }
                lemmaSeen.insert(lemmaKey)
                if vocab.translation.isEmpty && vocab.definition.isEmpty { continue }
            }
            if draft.content.frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if draft.content.backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            seen.insert(key)
            result.append(draft)
        }
        return result.sorted { $0.priority > $1.priority }
    }

    // MARK: Scoring

    func score(_ candidate: VocabularyCandidate) -> VocabularyCandidate {
        var c = candidate
        let key = TextNormalizer.searchKey(c.term)
        var score = 0.0
        if c.fromVocabularyList { score += 5 }
        if c.inlineTranslation != nil { score += 1 }
        if configuration.language == .english && WordLists.academicWords.contains(lemma(key)) { score += 3 }
        score += min(Double(c.occurrences - 1), 4) * 0.75     // topic-specific repetition
        score += min(Double(key.count), 12) / 6               // longer words are rarer
        if key.contains(" ") { score += 1.5 }                 // collocations / phrasal verbs
        c.score = score
        switch score {
        case 7...: c.priority = .essential
        case 4..<7: c.priority = .high
        case 2..<4: c.priority = .normal
        default: c.priority = .low
        }
        return c
    }

    // MARK: Helpers

    /// Light, language-aware lemmatisation sufficient for duplicate detection.
    public func lemma(_ key: String) -> String {
        guard configuration.language == .english, !key.contains(" ") else { return key }
        let rules: [(String, String)] = [("ies", "y"), ("ied", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")]
        for (suffix, replacement) in rules where key.hasSuffix(suffix) && key.count - suffix.count >= 3 {
            if suffix == "s" && (key.hasSuffix("ss") || key.hasSuffix("us") || key.hasSuffix("is")) { return key }
            if suffix == "es" && !(key.hasSuffix("ses") || key.hasSuffix("xes") || key.hasSuffix("zes")
                                   || key.hasSuffix("ches") || key.hasSuffix("shes")) { continue }
            var stem = String(key.dropLast(suffix.count)) + replacement
            // Undo consonant doubling: "stopped" -> "stop".
            if (suffix == "ing" || suffix == "ed"), let last = stem.last, stem.count >= 4,
               stem.dropLast().last == last, !"aeiouls".contains(last) {
                stem.removeLast()
            }
            return stem
        }
        return key
    }

    private func cleanListTerm(_ term: String) -> String {
        // Remove numbering ("1.", "a)") and trailing part-of-speech markers ("(n)", "adj.").
        var t = term.replacingOccurrences(of: "^\\s*(\\d+|[a-z])[\\.)]\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s*\\((n|v|adj|adv|prep|phr v|pv)\\.?\\)\\s*$", with: "",
                                   options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func hasOCRNoise(_ term: String) -> Bool {
        // Mixed scripts within a word, or letters interleaved with digits ("w0rd", "l1ke").
        let hasDigit = term.contains(where: \.isNumber)
        let hasLetter = term.contains(where: \.isLetter)
        if hasDigit && hasLetter { return true }
        var latin = false, arabic = false
        for scalar in term.unicodeScalars {
            if (0x41...0x7A).contains(scalar.value) { latin = true }
            if (0x0600...0x06FF).contains(scalar.value) { arabic = true }
        }
        return latin && arabic
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?؟\n".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return sentences
    }
}
