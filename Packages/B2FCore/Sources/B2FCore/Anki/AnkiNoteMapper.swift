import Foundation

/// Converts imported Anki notes into app flashcards.
///
/// Notes created by this app's own note types round-trip losslessly back into
/// structured vocabulary/grammar/reading/speaking cards. Any other note type
/// becomes a `.basic` card (cloze notes are rendered with the cloze hidden).
public struct AnkiNoteMapper {

    public init() {}

    public func draft(from note: ImportedAnkiNote) -> FlashcardDraft {
        let media = mediaReferences(in: note.fieldValues)
        let tags = note.tags + ["anki-import"]
        let id = note.field("B2FID").flatMap { UUID(uuidString: TextNormalizer.stripHTML($0)) } ?? UUID()
        let content: CardContent

        if note.noteTypeName == AnkiNoteTypes.vocabularyName {
            let f = { (name: String) in TextNormalizer.stripHTML(note.field(name) ?? "") }
            content = .vocabulary(VocabularyContent(
                term: f("Term"), translation: f("Translation"), definition: f("Definition"), ipa: f("IPA"),
                pronunciation: f("Pronunciation"), partOfSpeech: f("PartOfSpeech"), example: stripSound(f("Example")),
                exampleTranslation: f("ExampleTranslation"),
                synonyms: list(f("Synonyms")), antonyms: list(f("Antonyms"))))
        } else if note.noteTypeName == AnkiNoteTypes.basicName {
            let front = TextNormalizer.stripHTML(note.field("Front") ?? "")
            let back = TextNormalizer.stripHTML(note.field("Back") ?? "")
            let extra = TextNormalizer.stripHTML(note.field("Extra") ?? "")
            switch TextNormalizer.stripHTML(note.field("Kind") ?? "") {
            case "grammar":
                let lines = back.components(separatedBy: "\n")
                content = .grammar(GrammarContent(rule: front, explanation: lines.first ?? "",
                                                  examples: Array(lines.dropFirst()),
                                                  commonMistakes: extra.components(separatedBy: "\n")
                                                    .filter { $0 != "Common mistakes" && !$0.isEmpty }
                                                    .map { $0.replacingOccurrences(of: "✗ ", with: "") }))
            case "reading":
                content = .reading(ReadingContent(question: front, answer: back, explanation: extra))
            case "speaking":
                content = .speaking(SpeakingContent(prompt: front, sampleAnswer: back,
                                                    usefulPhrases: extra.components(separatedBy: "\n")
                                                        .filter { $0 != "Useful phrases" && !$0.isEmpty }))
            default:
                content = .basic(BasicContent(front: front, back: back, extra: extra))
            }
        } else {
            content = .basic(genericContent(note))
        }

        return FlashcardDraft(id: id, content: content, tags: tags, priority: .normal, confidence: 1,
                              audioFileName: media.audio, imageFileName: media.image, scheduling: note.scheduling)
    }

    func genericContent(_ note: ImportedAnkiNote) -> BasicContent {
        let values = note.fieldValues
        let first = values.first ?? ""
        if first.contains("{{c") {
            let hidden = first.replacingOccurrences(of: "\\{\\{c\\d+::(.*?)(::(.*?))?\\}\\}", with: "[…]", options: .regularExpression)
            let revealed = first.replacingOccurrences(of: "\\{\\{c\\d+::(.*?)(::(.*?))?\\}\\}", with: "$1", options: .regularExpression)
            return BasicContent(front: stripSound(TextNormalizer.stripHTML(hidden)),
                                back: stripSound(TextNormalizer.stripHTML(revealed)),
                                extra: values.dropFirst().map { stripSound(TextNormalizer.stripHTML($0)) }.joined(separator: "\n"))
        }
        let front = stripSound(TextNormalizer.stripHTML(first))
        let back = values.count > 1 ? stripSound(TextNormalizer.stripHTML(values[1])) : ""
        let extra = values.dropFirst(2).map { stripSound(TextNormalizer.stripHTML($0)) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        return BasicContent(front: front, back: back, extra: extra)
    }

    func mediaReferences(in fields: [String]) -> (audio: String?, image: String?) {
        let joined = fields.joined(separator: " ")
        var audio: String?
        if let range = joined.range(of: "\\[sound:([^\\]]+)\\]", options: .regularExpression) {
            audio = String(joined[range]).replacingOccurrences(of: "[sound:", with: "").replacingOccurrences(of: "]", with: "")
        }
        var image: String?
        if let range = joined.range(of: "<img[^>]+src=[\"']?([^\"' >]+)", options: [.regularExpression, .caseInsensitive]) {
            let tag = String(joined[range])
            if let srcRange = tag.range(of: "src=[\"']?", options: .regularExpression) {
                image = String(tag[srcRange.upperBound...])
            }
        }
        return (audio, image)
    }

    private func stripSound(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
