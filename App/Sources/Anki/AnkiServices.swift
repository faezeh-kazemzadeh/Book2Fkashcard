import Foundation
import SwiftData
import B2FCore

/// What to export.
enum AnkiExportScope: Hashable {
    case lesson(UUID)
    case lessons(Set<UUID>)
    case book(UUID)

    var description: String {
        switch self {
        case .lesson: return "Lesson"
        case .lessons(let ids): return "\(ids.count) lessons"
        case .book: return "Book"
        }
    }
}

/// Collects cards for a scope, renders pronunciation audio and writes an `.apkg`.
/// Works fully offline (on-device TTS + local packaging).
@MainActor
struct AnkiExportService {
    let repository: LibraryRepository
    let settings: AppSettings
    let files: EncryptedFileStore

    struct Options {
        var includeAudio: Bool
        var includeScheduling: Bool
        var includeSuspended: Bool = false
    }

    func export(scope: AnkiExportScope, options: Options,
                progress: @escaping @MainActor (Double) -> Void) async throws -> AnkiExportResult {
        let (lessons, books, fileStem) = resolve(scope)
        var cards: [AnkiExportRequest.Card] = []
        let renderer = AudioRenderer(directory: files.mediaDirectory)
        let all = lessons.flatMap { lesson in (lesson.cards ?? []).map { (lesson, $0) } }
            .filter { options.includeSuspended || !$0.1.isSuspended }

        for (index, (lesson, card)) in all.enumerated() {
            var audio = card.audioFileName
            var exampleAudio: String?
            let book = lesson.unit?.book
            if options.includeAudio, case .vocabulary(let v) = card.content, let book {
                if audio == nil || !FileManager.default.fileExists(atPath: files.mediaDirectory.appendingPathComponent(audio!).path) {
                    audio = try? await renderer.render(v.term, language: book.targetLanguage, accent: settings.accent)
                    card.audioFileName = audio
                }
                if !v.example.isEmpty {
                    exampleAudio = try? await renderer.render(v.example, language: book.targetLanguage, accent: settings.accent)
                }
            }
            let section = card.kind == .basic ? [] : [card.kind.displayName]
            cards.append(AnkiExportRequest.Card(
                id: card.id, content: card.content, deckPath: lesson.deckPath + section, tags: card.tags,
                audioFileName: options.includeAudio ? audio : nil, exampleAudioFileName: exampleAudio,
                imageFileName: card.imageFileName, scheduling: card.scheduling))
            progress(Double(index + 1) / Double(max(all.count, 1)) * 0.9)
        }

        let safeStem = fileStem.replacingOccurrences(of: "[/\\\\:?%*|\"<>]", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeStem).apkg")
        let request = AnkiExportRequest(cards: cards, mediaDirectory: files.mediaDirectory,
                                        includeScheduling: options.includeScheduling, includeMedia: options.includeAudio)
        let result = try await Task.detached(priority: .userInitiated) {
            try AnkiPackageWriter().write(request, to: url)
        }.value
        try repository.recordExport(scope: scope.description, cardCount: result.noteCount, books: books)
        progress(1)
        return result
    }

    private func resolve(_ scope: AnkiExportScope) -> ([LessonEntity], [BookEntity], String) {
        switch scope {
        case .lesson(let id):
            guard let lesson = repository.lesson(id: id) else { return ([], [], "Lesson") }
            return ([lesson], lesson.unit?.book.map { [$0] } ?? [], "\(lesson.unit?.book?.title ?? "Book") - \(lesson.title)")
        case .lessons(let ids):
            let lessons = ids.compactMap(repository.lesson(id:)).sorted { lhs, rhs in
                let lhsUnit: Int = lhs.unit?.order ?? 0
                let rhsUnit: Int = rhs.unit?.order ?? 0
                return lhsUnit != rhsUnit ? lhsUnit < rhsUnit : lhs.order < rhs.order
            }
            let books = Array(Set(lessons.compactMap { $0.unit?.book?.id })).compactMap(repository.book(id:))
            return (lessons, books, books.first?.title ?? "Lessons")
        case .book(let id):
            guard let book = repository.book(id: id) else { return ([], [], "Book") }
            return (book.allLessons, [book], book.title)
        }
    }
}

/// Imports `.apkg`, `.colpkg`, `.csv`, `.tsv` and `.txt` decks as a new book.
struct AnkiImportService {
    let writer: LibraryWriter
    let files: EncryptedFileStore

    struct Summary: Sendable {
        let bookID: UUID
        let imported: Int
        let skipped: Int
    }

    func importDeck(at url: URL, target: StudyLanguage, native: StudyLanguage, gate: FeatureGate,
                    currentCardCount: Int) async throws -> Summary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let notes: [ImportedAnkiNote]
        if ext == "apkg" || ext == "colpkg" {
            notes = try AnkiPackageReader().read(packageAt: url, mediaDestination: files.mediaDirectory).notes
        } else {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            notes = try AnkiTextImporter().parse(text, options: .init(defaultDeck: url.deletingPathExtension().lastPathComponent))
        }

        let mapper = AnkiNoteMapper()
        var drafts = notes.filter { !$0.isSuspended }.map { ($0.deckPath, mapper.draft(from: $0)) }
        let skipped: Int
        switch gate.canAddCards(currentCardCount: currentCardCount, adding: drafts.count) {
        case .allowed:
            skipped = 0
        case .partiallyAllowed(let remaining):
            skipped = drafts.count - remaining
            drafts = Array(drafts.prefix(remaining))
        case .requiresPremium:
            throw PremiumRequiredError(feature: .unlimitedCards)
        }
        let title = notes.first?.deckPath.first ?? url.deletingPathExtension().lastPathComponent
        let result = try await writer.importDeckCards(bookTitle: title, target: target, native: native,
                                                      cards: drafts.map { (deckPath: $0.0, draft: $0.1) })
        return Summary(bookID: result.bookID, imported: result.imported, skipped: skipped)
    }
}

struct PremiumRequiredError: Error, LocalizedError {
    let feature: PremiumFeature
    var errorDescription: String? { "\(feature.title) requires Premium." }
}
