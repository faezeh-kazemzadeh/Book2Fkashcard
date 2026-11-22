import Foundation

/// What a search hit points to.
public enum SearchScope: String, CaseIterable, Codable, Sendable, Identifiable {
    case books, ocrText, lessons, vocabulary, definitions, examples, grammar

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .books: return "Books"
        case .ocrText: return "OCR Text"
        case .lessons: return "Lessons"
        case .vocabulary: return "Vocabulary"
        case .definitions: return "Definitions"
        case .examples: return "Examples"
        case .grammar: return "Grammar Notes"
        }
    }
}

public struct SearchDocument: Sendable, Hashable {
    public var id: UUID
    public var scope: SearchScope
    public var title: String
    public var body: String
    /// Identifiers for navigation (book/lesson/card/page).
    public var bookID: UUID?
    public var lessonID: UUID?
    public var pageIndex: Int?

    public init(id: UUID, scope: SearchScope, title: String, body: String,
                bookID: UUID? = nil, lessonID: UUID? = nil, pageIndex: Int? = nil) {
        self.id = id
        self.scope = scope
        self.title = title
        self.body = body
        self.bookID = bookID
        self.lessonID = lessonID
        self.pageIndex = pageIndex
    }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
    public var document: SearchDocument
    public var score: Double
    public var snippet: String
    public var id: String { "\(document.scope.rawValue)-\(document.id.uuidString)" }
}

/// In-memory inverted index with prefix matching, diacritic/case folding and
/// Persian/Arabic normalisation. Rebuilt incrementally by the app's repository.
public final class SearchIndex: @unchecked Sendable {
    private var documents: [String: SearchDocument] = [:]
    private var postings: [String: [String: Int]] = [:]   // token → docKey → term frequency
    private var sortedTokens: [String] = []
    private var tokensDirty = false
    private let lock = NSLock()

    public init() {}

    public var count: Int { lock.synchronized { documents.count } }

    private func key(_ doc: SearchDocument) -> String { "\(doc.scope.rawValue)|\(doc.id.uuidString)" }

    public func upsert(_ document: SearchDocument) {
        lock.synchronized {
            let docKey = key(document)
            removeLocked(docKey)
            documents[docKey] = document
            let titleTokens = TextNormalizer.tokens(TextNormalizer.searchKey(document.title))
            let bodyTokens = TextNormalizer.tokens(TextNormalizer.searchKey(document.body))
            var frequencies: [String: Int] = [:]
            for token in titleTokens { frequencies[token, default: 0] += 3 }   // title boost
            for token in bodyTokens { frequencies[token, default: 0] += 1 }
            for (token, frequency) in frequencies { postings[token, default: [:]][docKey] = frequency }
            tokensDirty = true
        }
    }

    public func remove(id: UUID, scope: SearchScope) {
        lock.synchronized { removeLocked("\(scope.rawValue)|\(id.uuidString)") }
    }

    public func removeAll() {
        lock.synchronized {
            documents.removeAll()
            postings.removeAll()
            sortedTokens.removeAll()
        }
    }

    private func removeLocked(_ docKey: String) {
        guard documents.removeValue(forKey: docKey) != nil else { return }
        for token in postings.keys {
            postings[token]?.removeValue(forKey: docKey)
            if postings[token]?.isEmpty == true { postings.removeValue(forKey: token) }
        }
        tokensDirty = true
    }

    /// All query tokens must match (the last as a prefix). Ranked by TF-IDF.
    public func search(_ query: String, scopes: Set<SearchScope> = Set(SearchScope.allCases), limit: Int = 50) -> [SearchHit] {
        let queryTokens = TextNormalizer.tokens(TextNormalizer.searchKey(query))
        guard !queryTokens.isEmpty else { return [] }

        return lock.synchronized { () -> [SearchHit] in
            if tokensDirty {
                sortedTokens = postings.keys.sorted()
                tokensDirty = false
            }
            let total = Double(max(documents.count, 1))
            var scores: [String: Double]?

            for (index, token) in queryTokens.enumerated() {
                let isLast = index == queryTokens.count - 1
                let matchingTokens = isLast ? prefixMatches(token) : (postings[token] != nil ? [token] : [])
                var tokenScores: [String: Double] = [:]
                for match in matchingTokens {
                    guard let docs = postings[match] else { continue }
                    let idf = log(1 + total / Double(docs.count))
                    let exactBoost = match == token ? 1.0 : 0.6
                    for (docKey, tf) in docs {
                        tokenScores[docKey, default: 0] += Double(tf) * idf * exactBoost
                    }
                }
                if let current = scores {
                    scores = current.filter { tokenScores[$0.key] != nil }
                        .reduce(into: [:]) { $0[$1.key] = $1.value + tokenScores[$1.key]! }
                } else {
                    scores = tokenScores
                }
            }

            return (scores ?? [:])
                .compactMap { docKey, score -> SearchHit? in
                    guard let doc = documents[docKey], scopes.contains(doc.scope) else { return nil }
                    return SearchHit(document: doc, score: score, snippet: Self.snippet(doc.body, query: queryTokens))
                }
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { $0 }
        }
    }

    private func prefixMatches(_ prefix: String) -> [String] {
        // Binary search for the first token ≥ prefix, then walk while it matches.
        var low = 0, high = sortedTokens.count
        while low < high {
            let mid = (low + high) / 2
            if sortedTokens[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var result: [String] = []
        var i = low
        while i < sortedTokens.count, sortedTokens[i].hasPrefix(prefix), result.count < 200 {
            result.append(sortedTokens[i])
            i += 1
        }
        return result
    }

    static func snippet(_ body: String, query: [String], radius: Int = 60) -> String {
        let folded = TextNormalizer.searchKey(body)
        guard let first = query.first, let range = folded.range(of: first) else {
            return String(body.prefix(radius * 2))
        }
        // Folding keeps character counts close enough to locate the snippet in the original.
        let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let start = max(0, offset - radius)
        let originalStart = body.index(body.startIndex, offsetBy: min(start, body.count))
        let originalEnd = body.index(originalStart, offsetBy: radius * 2, limitedBy: body.endIndex) ?? body.endIndex
        let text = TextNormalizer.collapseWhitespace(String(body[originalStart..<originalEnd]))
        return (start > 0 ? "…" : "") + text + (originalEnd < body.endIndex ? "…" : "")
    }
}

extension NSLock {
    /// Portable equivalent of `withLock` (not available on every Linux toolchain).
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
