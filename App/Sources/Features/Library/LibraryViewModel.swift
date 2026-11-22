import Foundation
import UIKit
import Observation
import B2FCore

@MainActor
@Observable
final class LibraryViewModel {
    struct PendingImport: Identifiable {
        enum Source { case file(URL), images([UIImage], scanned: Bool) }
        let id = UUID()
        var source: Source
        var title: String
        var target: StudyLanguage
        var native: StudyLanguage
    }

    var pendingImport: PendingImport?
    var errorMessage: String?
    var lastWarnings: [String] = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Entry points

    func prepareImport(url: URL, model: AppModel) {
        if DocumentImporter.isAnkiFile(url) {
            importAnkiDeck(url: url, model: model)
            return
        }
        guard model.require(model.gate.canAddBook(currentBookCount: model.repository.bookCount())) else { return }
        pendingImport = PendingImport(source: .file(url), title: url.deletingPathExtension().lastPathComponent,
                                      target: model.settings.targetLanguage, native: model.settings.nativeLanguage)
    }

    func prepareImport(images: [UIImage], scanned: Bool, model: AppModel) {
        guard !images.isEmpty else { return }
        guard model.require(model.gate.canAddBook(currentBookCount: model.repository.bookCount())) else { return }
        let title = scanned ? String(localized: "Scan \(Date().formatted(date: .abbreviated, time: .shortened))")
                            : String(localized: "Photos \(Date().formatted(date: .abbreviated, time: .omitted))")
        pendingImport = PendingImport(source: .images(images, scanned: scanned), title: title,
                                      target: model.settings.targetLanguage, native: model.settings.nativeLanguage)
    }

    func confirm(_ pending: PendingImport, model: AppModel) {
        pendingImport = nil
        let document: ImportedDocument
        do {
            switch pending.source {
            case .file(let url):
                document = try DocumentImporter().open(url: url)
            case .images(let images, let scanned):
                document = DocumentImporter().open(images: images, title: pending.title, scanned: scanned)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        var titled = document
        titled.title = pending.title.isEmpty ? document.title : pending.title
        run(titled, target: pending.target, native: pending.native, model: model)
    }

    private func run(_ document: ImportedDocument, target: StudyLanguage, native: StudyLanguage, model: AppModel) {
        let pipeline = model.makePipeline(target: target, native: native)
        let key = UUID()
        // Keep processing alive briefly if the user leaves the app mid-import.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BookImport")
        tasks[key] = Task { [weak self] in
            let stream = await pipeline.process(document)
            for await event in stream {
                self?.handle(event, model: model)
            }
            self?.tasks[key] = nil
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    func resume(bookID: UUID, model: AppModel) {
        guard let book = model.repository.book(id: bookID) else { return }
        let pipeline = model.makePipeline(target: book.targetLanguage, native: book.nativeLanguage)
        tasks[bookID] = Task { [weak self] in
            let stream = await pipeline.resume(bookID: bookID)
            for await event in stream { self?.handle(event, model: model) }
            self?.tasks[bookID] = nil
        }
    }

    func importAnkiDeck(url: URL, model: AppModel) {
        let service = AnkiImportService(writer: model.writer, files: model.files)
        let gate = model.gate
        let count = model.repository.cardCount()
        let settings = model.settings
        Task {
            do {
                let summary = try await service.importDeck(at: url, target: settings.targetLanguage, native: settings.nativeLanguage,
                                                           gate: gate, currentCardCount: count)
                model.toast = summary.skipped > 0
                    ? String(localized: "Imported \(summary.imported) cards. \(summary.skipped) skipped (free plan limit).")
                    : String(localized: "Imported \(summary.imported) cards.")
                model.invalidateSearch()
            } catch let error as PremiumRequiredError {
                model.presentedPaywall = error.feature
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handle(_ event: ProcessingEvent, model: AppModel) {
        switch event {
        case .warning(let message):
            lastWarnings.append(message)
        case .limitReached(let feature):
            model.presentedPaywall = feature
        case .finished(_, let cards):
            model.toast = String(localized: "Created \(cards) flashcards")
            model.invalidateSearch()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failed(let message):
            errorMessage = message
        case .started, .page, .structured, .generating:
            break
        }
    }

    func delete(_ book: BookEntity, model: AppModel) {
        model.files.removeOriginal(bookID: book.id)
        do {
            try model.repository.delete(book)
            model.invalidateSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
