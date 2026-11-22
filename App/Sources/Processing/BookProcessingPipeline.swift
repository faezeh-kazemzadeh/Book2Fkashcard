import Foundation
import UIKit
import B2FCore

/// Progress events streamed to the UI while a book is processed.
enum ProcessingEvent: Sendable {
    case started(bookID: UUID)
    case page(index: Int, of: Int)
    case structured(lessons: Int)
    case generating(lesson: String, index: Int, of: Int)
    case warning(String)
    case limitReached(PremiumFeature)
    case finished(bookID: UUID, cards: Int)
    case failed(String)
}

/// Import → OCR/text extraction → layout analysis → lesson detection →
/// (AI refinement) → card generation → quality filter → persistence.
///
/// Runs off the main actor; every stage persists its results, so an
/// interrupted import can be resumed with `resume(bookID:)`.
actor BookProcessingPipeline {
    struct Dependencies: Sendable {
        var writer: LibraryWriter
        var ocr: OCREngine
        var provider: (any AIProvider)?
        var tier: PlanTier
        var options: GenerationOptions
        var encryption: EncryptedFileStore = .shared
        var refineLessonsWithAI = true
    }

    private let deps: Dependencies

    init(dependencies: Dependencies) {
        self.deps = dependencies
    }

    func process(_ document: ImportedDocument) -> AsyncStream<ProcessingEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(document, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func resume(bookID: UUID) -> AsyncStream<ProcessingEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started(bookID: bookID))
                    let total = try await self.generateCards(bookID: bookID, continuation: continuation)
                    try await self.deps.writer.updateStatus(bookID: bookID, status: .ready, progress: 1)
                    continuation.yield(.finished(bookID: bookID, cards: total))
                } catch {
                    try? await self.deps.writer.updateStatus(bookID: bookID, status: .failed, message: error.localizedDescription)
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Stages

    private func run(_ document: ImportedDocument, continuation: AsyncStream<ProcessingEvent>.Continuation) async {
        let writer = deps.writer
        var bookID: UUID?
        do {
            let id = try await writer.createBook(title: document.title, author: document.author,
                                                 target: deps.options.targetLanguage, native: deps.options.nativeLanguage,
                                                 source: document.kind, cover: document.source.thumbnail())
            bookID = id
            continuation.yield(.started(bookID: id))
            if let original = document.originalData {
                _ = try? deps.encryption.storeOriginal(original, bookID: id, fileExtension: document.fileExtension)
            }

            // 1. Pages: text extraction or OCR.
            try await writer.updateStatus(bookID: id, status: .recognizing, progress: 0)
            let languages = Array(Set([deps.options.targetLanguage, deps.options.nativeLanguage]))
            let total = document.source.pageCount
            let analyzer = LayoutAnalyzer()
            for index in 0..<total {
                try Task.checkCancellation()
                continuation.yield(.page(index: index, of: total))
                let content = try await document.source.page(at: index)
                switch content {
                case .text(let text, let headings):
                    let analyzed = analyzer.analyze(pageIndex: index, plainText: text, headingHints: headings)
                    try await writer.addPage(bookID: id, index: index, text: analyzed.plainText, analyzed: analyzed, encryptedImage: nil)
                case .image(let image, let orientation, let scanned):
                    let result = try await deps.ocr.recognize(image: image, orientation: orientation, pageIndex: index,
                                                              languages: languages, mode: FeatureGate(tier: deps.tier).ocrMode,
                                                              alreadyScanned: scanned)
                    let sealed = result.preprocessedJPEG.flatMap { try? deps.encryption.seal($0) }
                    try await writer.addPage(bookID: id, index: index, text: result.plainText, analyzed: result.analyzed,
                                             encryptedImage: sealed)
                }
                try await writer.updateStatus(bookID: id, status: .recognizing,
                                              message: "Page \(index + 1) of \(total)",
                                              progress: 0.5 * Double(index + 1) / Double(max(total, 1)))
            }

            // 2. Structure.
            try await structure(bookID: id, continuation: continuation)

            // 3. Cards.
            let cards = try await generateCards(bookID: id, continuation: continuation)
            try await writer.updateStatus(bookID: id, status: .ready, message: "", progress: 1)
            continuation.yield(.finished(bookID: id, cards: cards))
        } catch is CancellationError {
            if let bookID { try? await writer.updateStatus(bookID: bookID, status: .failed, message: "Cancelled") }
            continuation.yield(.failed("Import cancelled."))
        } catch {
            if let bookID { try? await writer.updateStatus(bookID: bookID, status: .failed, message: error.localizedDescription) }
            continuation.yield(.failed(error.localizedDescription))
        }
    }

    func structure(bookID: UUID, continuation: AsyncStream<ProcessingEvent>.Continuation?) async throws {
        try await deps.writer.updateStatus(bookID: bookID, status: .structuring, message: "Detecting lessons", progress: 0.55)
        let pages = await deps.writer.analyzedPages(bookID: bookID)
        var outline = LessonStructureDetector().detect(pages: pages)
        if deps.refineLessonsWithAI, let provider = deps.provider, outline.lessonCount > 0 {
            do {
                outline = try await AILessonRefiner(provider: provider).refine(outline)
            } catch {
                continuation?.yield(.warning("Lesson titles were detected offline."))
            }
        }
        try await deps.writer.saveOutline(bookID: bookID, outline: outline)
        continuation?.yield(.structured(lessons: outline.lessonCount))
    }

    func generateCards(bookID: UUID, continuation: AsyncStream<ProcessingEvent>.Continuation?) async throws -> Int {
        let writer = deps.writer
        try await writer.updateStatus(bookID: bookID, status: .generating, message: "Creating flashcards", progress: 0.6)
        let lessons = await writer.lessonsNeedingCards(bookID: bookID)
        let generator = FlashcardGenerator(provider: deps.provider, options: deps.options)
        var existing = await writer.deduplicationKeys(bookID: bookID)
        let gate = FeatureGate(tier: deps.tier)
        var created = 0

        for (index, item) in lessons.enumerated() {
            try Task.checkCancellation()
            continuation?.yield(.generating(lesson: item.node.title, index: index, of: lessons.count))
            try await writer.markLesson(item.id, status: .generating)

            let result = try await generator.generate(for: item.node, bookTitle: item.bookTitle,
                                                      unitTitle: item.unitTitle, existingKeys: existing)
            result.warnings.forEach { continuation?.yield(.warning($0)) }

            var drafts = result.drafts
            let currentCount = await writer.totalCardCount()
            switch gate.canAddCards(currentCardCount: currentCount, adding: drafts.count) {
            case .allowed:
                break
            case .partiallyAllowed(let remaining):
                drafts = Array(drafts.prefix(remaining))
                continuation?.yield(.limitReached(.unlimitedCards))
            case .requiresPremium(let feature):
                try await writer.markLesson(item.id, status: .pending)
                continuation?.yield(.limitReached(feature))
                return created
            }

            try await writer.saveCards(lessonID: item.id, drafts: drafts)
            existing.formUnion(drafts.map { $0.content.deduplicationKey })
            created += drafts.count
            try await writer.updateStatus(bookID: bookID, status: .generating,
                                          message: "Lesson \(index + 1) of \(lessons.count)",
                                          progress: 0.6 + 0.4 * Double(index + 1) / Double(max(lessons.count, 1)))
        }
        return created
    }
}
