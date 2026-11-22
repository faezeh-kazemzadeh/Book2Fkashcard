import Foundation
import SwiftData
import B2FCore

// SwiftData + CloudKit rules applied throughout:
// every attribute has a default or is optional, no unique constraints,
// all relationships are optional and have inverses.

enum BookSourceKind: String, Codable, CaseIterable {
    case pdf, scannedPDF, epub, docx, txt, images, camera, ankiDeck
}

enum ProcessingStatus: String, Codable {
    case pending, extracting, recognizing, structuring, generating, ready, failed

    var isActive: Bool { ![.ready, .failed].contains(self) }
}

@Model
final class BookEntity {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var targetLanguageRaw: String = StudyLanguage.english.rawValue
    var nativeLanguageRaw: String = StudyLanguage.persian.rawValue
    var sourceKindRaw: String = BookSourceKind.pdf.rawValue
    var statusRaw: String = ProcessingStatus.pending.rawValue
    var statusMessage: String = ""
    var progress: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastOpenedAt: Date?
    var pageCount: Int = 0
    var exportCount: Int = 0
    @Attribute(.externalStorage) var coverThumbnail: Data?

    @Relationship(deleteRule: .cascade, inverse: \PageEntity.book) var pages: [PageEntity]? = []
    @Relationship(deleteRule: .cascade, inverse: \UnitEntity.book) var units: [UnitEntity]? = []

    init(title: String, author: String = "", targetLanguage: StudyLanguage, nativeLanguage: StudyLanguage, source: BookSourceKind) {
        self.title = title
        self.author = author
        self.targetLanguageRaw = targetLanguage.rawValue
        self.nativeLanguageRaw = nativeLanguage.rawValue
        self.sourceKindRaw = source.rawValue
    }

    var targetLanguage: StudyLanguage { StudyLanguage(rawValue: targetLanguageRaw) ?? .english }
    var nativeLanguage: StudyLanguage { StudyLanguage(rawValue: nativeLanguageRaw) ?? .persian }
    var sourceKind: BookSourceKind { BookSourceKind(rawValue: sourceKindRaw) ?? .pdf }
    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var sortedUnits: [UnitEntity] { (units ?? []).sorted { $0.order < $1.order } }
    var sortedPages: [PageEntity] { (pages ?? []).sorted { $0.index < $1.index } }
    var allLessons: [LessonEntity] { sortedUnits.flatMap(\.sortedLessons) }
    var allCards: [FlashcardEntity] { allLessons.flatMap { $0.cards ?? [] } }
    var lowConfidencePages: [PageEntity] { sortedPages.filter(\.isLowConfidence) }
}

@Model
final class PageEntity {
    var id: UUID = UUID()
    var index: Int = 0
    var ocrText: String = ""
    /// JSON-encoded `AnalyzedPage` (blocks, confidences).
    var layoutData: Data?
    var averageConfidence: Double = 1
    var isLowConfidence: Bool = false
    var isUserCorrected: Bool = false
    /// AES-GCM sealed JPEG of the page (see `EncryptedFileStore`). Synced via CloudKit as an asset.
    @Attribute(.externalStorage) var encryptedImage: Data?
    var book: BookEntity?

    init(index: Int, ocrText: String, analyzed: AnalyzedPage?, encryptedImage: Data?, lowConfidenceThreshold: Double = 0.6) {
        self.index = index
        self.ocrText = ocrText
        self.layoutData = analyzed.flatMap { try? JSONEncoder().encode($0) }
        self.averageConfidence = analyzed?.averageConfidence ?? 1
        self.isLowConfidence = (analyzed?.averageConfidence ?? 1) < lowConfidenceThreshold
            || !(analyzed?.lowConfidenceBlockIDs.isEmpty ?? true)
        self.encryptedImage = encryptedImage
    }

    var analyzed: AnalyzedPage? {
        layoutData.flatMap { try? JSONDecoder().decode(AnalyzedPage.self, from: $0) }
    }
}

@Model
final class UnitEntity {
    var id: UUID = UUID()
    var title: String = ""
    var order: Int = 0
    var book: BookEntity?
    @Relationship(deleteRule: .cascade, inverse: \LessonEntity.unit) var lessons: [LessonEntity]? = []

    init(title: String, order: Int) {
        self.title = title
        self.order = order
    }

    var sortedLessons: [LessonEntity] { (lessons ?? []).sorted { $0.order < $1.order } }
}

@Model
final class LessonEntity {
    var id: UUID = UUID()
    var title: String = ""
    var order: Int = 0
    var pageStart: Int = 0
    var pageEnd: Int = 0
    /// JSON-encoded `[LessonSection]`.
    var sectionsData: Data?
    var generationStatusRaw: String = ProcessingStatus.pending.rawValue
    var unit: UnitEntity?
    @Relationship(deleteRule: .cascade, inverse: \FlashcardEntity.lesson) var cards: [FlashcardEntity]? = []

    init(node: LessonNode, order: Int) {
        self.id = node.id
        self.title = node.title
        self.order = order
        self.pageStart = node.pageRange.lowerBound
        self.pageEnd = node.pageRange.upperBound
        self.sectionsData = try? JSONEncoder().encode(node.sections)
    }

    var sections: [LessonSection] {
        sectionsData.flatMap { try? JSONDecoder().decode([LessonSection].self, from: $0) } ?? []
    }

    var node: LessonNode {
        LessonNode(id: id, title: title, sections: sections, pageRange: pageStart...max(pageStart, pageEnd))
    }

    var generationStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: generationStatusRaw) ?? .pending }
        set { generationStatusRaw = newValue.rawValue }
    }

    var deckPath: [String] {
        [unit?.book?.title ?? "Book2Flashcards", unit?.title ?? "Unit", title]
    }
}

@Model
final class FlashcardEntity {
    var id: UUID = UUID()
    var kindRaw: String = CardKind.basic.rawValue
    var contentData: Data?
    /// Denormalised plain text for search, lists and accessibility.
    var frontText: String = ""
    var backText: String = ""
    /// Tags separated by a single space (Anki convention: tags never contain spaces).
    var tagsRaw: String = ""
    var priorityRaw: Int = LearningPriority.normal.rawValue
    var confidence: Double = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSuspended: Bool = false
    var audioFileName: String?
    var imageFileName: String?

    // Scheduling (mirrors `SchedulingState`).
    var phaseRaw: String = CardPhase.new.rawValue
    var due: Date = Date()
    var lastReview: Date?
    var intervalDays: Double = 0
    var easeFactor: Double = 2.5
    var repetitions: Int = 0
    var lapses: Int = 0
    var stability: Double?
    var difficulty: Double?
    var learningStep: Int = 0

    var lesson: LessonEntity?
    @Relationship(deleteRule: .cascade, inverse: \ReviewLogEntity.card) var reviews: [ReviewLogEntity]? = []

    init(draft: FlashcardDraft) {
        self.id = draft.id
        self.tagsRaw = draft.tags.map { $0.replacingOccurrences(of: " ", with: "_") }.joined(separator: " ")
        self.priorityRaw = draft.priority.rawValue
        self.confidence = draft.confidence
        self.audioFileName = draft.audioFileName
        self.imageFileName = draft.imageFileName
        self.content = draft.content
        if let scheduling = draft.scheduling { self.scheduling = scheduling }
    }

    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .basic }
    var priority: LearningPriority { LearningPriority(rawValue: priorityRaw) ?? .normal }
    var tags: [String] { tagsRaw.split(separator: " ").map(String.init) }
    var isFlaggedForReview: Bool { confidence < 0.6 }

    var content: CardContent {
        get {
            contentData.flatMap { try? JSONDecoder().decode(CardContent.self, from: $0) }
                ?? .basic(BasicContent(front: frontText, back: backText))
        }
        set {
            contentData = try? JSONEncoder().encode(newValue)
            kindRaw = newValue.kind.rawValue
            frontText = newValue.frontText
            backText = newValue.backText
            updatedAt = Date()
        }
    }

    var scheduling: SchedulingState {
        get {
            SchedulingState(phase: CardPhase(rawValue: phaseRaw) ?? .new, due: due, lastReview: lastReview,
                            intervalDays: intervalDays, easeFactor: easeFactor, repetitions: repetitions,
                            lapses: lapses, stability: stability, difficulty: difficulty, learningStep: learningStep)
        }
        set {
            phaseRaw = newValue.phase.rawValue
            due = newValue.due
            lastReview = newValue.lastReview
            intervalDays = newValue.intervalDays
            easeFactor = newValue.easeFactor
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            stability = newValue.stability
            difficulty = newValue.difficulty
            learningStep = newValue.learningStep
        }
    }

    var quizInput: QuizCardInput { QuizCardInput(id: id, content: content) }
}

@Model
final class ReviewLogEntity {
    var id: UUID = UUID()
    var cardID: UUID = UUID()
    var reviewedAt: Date = Date()
    var ratingRaw: Int = Rating.good.rawValue
    var phaseBeforeRaw: String = CardPhase.new.rawValue
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var retrievability: Double?
    var durationSeconds: Double = 0
    var algorithmRaw: String = SRSAlgorithm.fsrs.rawValue
    var card: FlashcardEntity?

    init(cardID: UUID, outcome: ReviewOutcome, rating: Rating, phaseBefore: CardPhase, duration: TimeInterval,
         algorithm: SRSAlgorithm, at date: Date) {
        self.cardID = cardID
        self.reviewedAt = date
        self.ratingRaw = rating.rawValue
        self.phaseBeforeRaw = phaseBefore.rawValue
        self.elapsedDays = outcome.elapsedDays
        self.scheduledDays = outcome.scheduledInterval / 86_400
        self.retrievability = outcome.retrievabilityAtReview
        self.durationSeconds = duration
        self.algorithmRaw = algorithm.rawValue
    }

    var record: ReviewRecord {
        ReviewRecord(cardID: cardID, reviewedAt: reviewedAt, rating: Rating(rawValue: ratingRaw) ?? .good,
                     phaseBefore: CardPhase(rawValue: phaseBeforeRaw) ?? .new, elapsedDays: elapsedDays,
                     scheduledDays: scheduledDays, retrievability: retrievability, durationSeconds: durationSeconds)
    }
}

@Model
final class ExportRecordEntity {
    var id: UUID = UUID()
    var date: Date = Date()
    var scopeDescription: String = ""
    var cardCount: Int = 0
    var format: String = "apkg"

    init(scopeDescription: String, cardCount: Int, format: String = "apkg") {
        self.scopeDescription = scopeDescription
        self.cardCount = cardCount
        self.format = format
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        BookEntity.self, PageEntity.self, UnitEntity.self, LessonEntity.self,
        FlashcardEntity.self, ReviewLogEntity.self, ExportRecordEntity.self
    ]
}
