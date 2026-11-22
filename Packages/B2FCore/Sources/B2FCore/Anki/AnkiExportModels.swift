import Foundation

/// What to put in an `.apkg`. The deck tree mirrors the book:
/// `Book::Unit::Lesson::Vocabulary`, using Anki's `::` hierarchy separator.
public struct AnkiExportRequest: Sendable {
    public struct Card: Sendable {
        public var id: UUID
        public var content: CardContent
        /// Deck path components, e.g. ["English File", "Unit 1", "Lesson 1A", "Vocabulary"].
        public var deckPath: [String]
        public var tags: [String]
        public var audioFileName: String?
        public var exampleAudioFileName: String?
        public var imageFileName: String?
        public var scheduling: SchedulingState?

        public init(id: UUID, content: CardContent, deckPath: [String], tags: [String] = [],
                    audioFileName: String? = nil, exampleAudioFileName: String? = nil,
                    imageFileName: String? = nil, scheduling: SchedulingState? = nil) {
            self.id = id
            self.content = content
            self.deckPath = deckPath
            self.tags = tags
            self.audioFileName = audioFileName
            self.exampleAudioFileName = exampleAudioFileName
            self.imageFileName = imageFileName
            self.scheduling = scheduling
        }
    }

    public var cards: [Card]
    /// Media files available for packaging, keyed by file name.
    public var mediaDirectory: URL?
    public var includeScheduling: Bool
    public var includeMedia: Bool

    public init(cards: [Card], mediaDirectory: URL? = nil, includeScheduling: Bool = false, includeMedia: Bool = true) {
        self.cards = cards
        self.mediaDirectory = mediaDirectory
        self.includeScheduling = includeScheduling
        self.includeMedia = includeMedia
    }
}

public struct AnkiExportResult: Sendable {
    public var fileURL: URL
    public var noteCount: Int
    public var deckCount: Int
    public var mediaCount: Int
    public var missingMedia: [String]
}

public enum AnkiError: Error, LocalizedError, Equatable {
    case emptyExport
    case invalidPackage(String)
    case unsupportedCollectionFormat
    case invalidCSV(String)

    public var errorDescription: String? {
        switch self {
        case .emptyExport:
            return "There are no cards to export."
        case .invalidPackage(let reason):
            return "This Anki package could not be read (\(reason))."
        case .unsupportedCollectionFormat:
            return "This deck was exported in Anki's newest compressed format. In Anki, choose File › Export, select “Anki Deck Package”, and tick “Support older Anki versions”, then import again."
        case .invalidCSV(let reason):
            return "The text file could not be imported (\(reason))."
        }
    }
}

/// Note types written to exported collections. Field order is part of the
/// format contract with `AnkiNoteMapper` on import, so append-only.
public enum AnkiNoteTypes {
    public static let vocabularyName = "Book2Flashcards Vocabulary"
    public static let basicName = "Book2Flashcards Basic"

    public static let vocabularyFields = [
        "Term", "Translation", "Definition", "IPA", "Pronunciation", "PartOfSpeech", "Example",
        "ExampleTranslation", "Synonyms", "Antonyms", "Audio", "ExampleAudio", "Image", "B2FID"
    ]
    public static let basicFields = ["Front", "Back", "Extra", "Kind", "Audio", "Image", "B2FID"]

    public static let css = """
    .card { font-family: -apple-system, "Helvetica Neue", Arial, "Vazirmatn", "Noto Naskh Arabic", sans-serif;
            font-size: 22px; text-align: center; color: #1c1c1e; background: #ffffff; line-height: 1.45; }
    .nightMode .card, .card.nightMode { color: #f2f2f7; background: #1c1c1e; }
    .term { font-size: 34px; font-weight: 600; }
    .ipa { color: #6e6e73; font-family: "Charis SIL", "Doulos SIL", serif; }
    .translation { font-size: 26px; margin: 8px 0; }
    .definition, .explanation { text-align: start; }
    .example { font-style: italic; margin-top: 10px; }
    .muted { color: #8e8e93; font-size: 18px; }
    .formula { font-family: Menlo, monospace; background: rgba(127,127,127,.12); padding: 6px 10px; border-radius: 8px; display: inline-block; }
    ul { text-align: start; display: inline-block; }
    [dir=rtl] { text-align: right; }
    """

    public static let vocabularyFront = """
    <div class="term">{{Term}}</div>
    {{#IPA}}<div class="ipa">/{{IPA}}/</div>{{/IPA}}
    {{Audio}}
    """

    public static let vocabularyBack = """
    {{FrontSide}}
    <hr id="answer">
    <div class="translation" dir="auto">{{Translation}}</div>
    {{#PartOfSpeech}}<div class="muted">{{PartOfSpeech}}</div>{{/PartOfSpeech}}
    {{#Pronunciation}}<div class="muted">{{Pronunciation}}</div>{{/Pronunciation}}
    {{#Definition}}<div class="definition">{{Definition}}</div>{{/Definition}}
    {{#Example}}<div class="example">{{Example}} {{ExampleAudio}}</div>{{/Example}}
    {{#ExampleTranslation}}<div class="muted" dir="auto">{{ExampleTranslation}}</div>{{/ExampleTranslation}}
    {{#Synonyms}}<div class="muted">≈ {{Synonyms}}</div>{{/Synonyms}}
    {{#Antonyms}}<div class="muted">≠ {{Antonyms}}</div>{{/Antonyms}}
    {{#Image}}<div>{{Image}}</div>{{/Image}}
    """

    public static let basicFront = """
    <div class="term" dir="auto">{{Front}}</div>
    {{Audio}}
    """

    public static let basicBack = """
    {{FrontSide}}
    <hr id="answer">
    <div class="explanation" dir="auto">{{Back}}</div>
    {{#Extra}}<div class="muted" dir="auto">{{Extra}}</div>{{/Extra}}
    {{#Image}}<div>{{Image}}</div>{{/Image}}
    """
}
