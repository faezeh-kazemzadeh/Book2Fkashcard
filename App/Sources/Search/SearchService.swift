import Foundation
import SwiftData
import B2FCore

/// Builds and queries the in-memory `SearchIndex` from SwiftData.
/// Rebuilt lazily when the store changes; the index itself is never persisted.
@MainActor
final class SearchService {
    private let index = SearchIndex()
    private var builtAt: Date?
    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func invalidate() { builtAt = nil }

    func search(_ query: String, scopes: Set<SearchScope>) -> [SearchHit] {
        if builtAt == nil { rebuild() }
        return index.search(query, scopes: scopes)
    }

    func rebuild() {
        index.removeAll()
        for book in repository.books() {
            index.upsert(SearchDocument(id: book.id, scope: .books, title: book.title, body: book.author, bookID: book.id))
            for page in book.sortedPages where !page.ocrText.isEmpty {
                index.upsert(SearchDocument(id: page.id, scope: .ocrText, title: "\(book.title) – p. \(page.index + 1)",
                                            body: page.ocrText, bookID: book.id, pageIndex: page.index))
            }
            for lesson in book.allLessons {
                index.upsert(SearchDocument(id: lesson.id, scope: .lessons, title: lesson.title,
                                            body: lesson.sections.map(\.title).joined(separator: " "),
                                            bookID: book.id, lessonID: lesson.id))
                for card in lesson.cards ?? [] {
                    indexCard(card, bookID: book.id, lessonID: lesson.id)
                }
            }
        }
        builtAt = Date()
    }

    private func indexCard(_ card: FlashcardEntity, bookID: UUID, lessonID: UUID) {
        switch card.content {
        case .vocabulary(let v):
            index.upsert(SearchDocument(id: card.id, scope: .vocabulary, title: v.term,
                                        body: [v.translation, v.synonyms.joined(separator: " ")].joined(separator: " "),
                                        bookID: bookID, lessonID: lessonID))
            if !v.definition.isEmpty {
                index.upsert(SearchDocument(id: card.id, scope: .definitions, title: v.term, body: v.definition,
                                            bookID: bookID, lessonID: lessonID))
            }
            if !v.example.isEmpty {
                index.upsert(SearchDocument(id: card.id, scope: .examples, title: v.term,
                                            body: v.example + " " + v.exampleTranslation, bookID: bookID, lessonID: lessonID))
            }
        case .grammar(let g):
            index.upsert(SearchDocument(id: card.id, scope: .grammar, title: g.rule,
                                        body: ([g.explanation, g.formula] + g.examples + g.commonMistakes).joined(separator: " "),
                                        bookID: bookID, lessonID: lessonID))
        case .reading, .speaking, .basic:
            index.upsert(SearchDocument(id: card.id, scope: .examples, title: card.frontText, body: card.backText,
                                        bookID: bookID, lessonID: lessonID))
        }
    }
}
