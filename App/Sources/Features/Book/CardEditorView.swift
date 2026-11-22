import SwiftUI
import B2FCore

/// Edits any card type. Also offers an AI explanation (premium).
struct CardEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let card: FlashcardEntity

    @State private var vocabulary = VocabularyContent(term: "")
    @State private var grammar = GrammarContent(rule: "")
    @State private var reading = ReadingContent(question: "", answer: "")
    @State private var speaking = SpeakingContent(prompt: "", sampleAnswer: "")
    @State private var basic = BasicContent(front: "", back: "")
    @State private var explanation: String?
    @State private var isExplaining = false

    var body: some View {
        NavigationStack {
            Form {
                switch card.kind {
                case .vocabulary: vocabularyForm
                case .grammar: grammarForm
                case .reading: readingForm
                case .speaking: speakingForm
                case .basic: basicForm
                }

                Section {
                    Button {
                        explain()
                    } label: {
                        Label(isExplaining ? "Thinking…" : "Explain with AI", systemImage: "sparkles")
                    }
                    .disabled(isExplaining)
                    if let explanation {
                        AdaptiveText(explanation, font: .callout, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } footer: {
                    if card.isFlaggedForReview {
                        Text("This card came from low-confidence OCR. Saving your edits marks it as verified.")
                    }
                }
            }
            .navigationTitle(card.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Forms

    private var vocabularyForm: some View {
        Group {
            Section("Front") {
                TextField("Word or phrase", text: $vocabulary.term)
                TextField("IPA", text: $vocabulary.ipa)
                TextField("Pronunciation", text: $vocabulary.pronunciation)
                TextField("Part of speech", text: $vocabulary.partOfSpeech)
            }
            Section("Back") {
                TextField("Translation", text: $vocabulary.translation, axis: .vertical)
                TextField("Definition", text: $vocabulary.definition, axis: .vertical)
                TextField("Example sentence", text: $vocabulary.example, axis: .vertical)
                TextField("Example translation", text: $vocabulary.exampleTranslation, axis: .vertical)
                TextField("Synonyms (comma separated)", text: listBinding(\.synonyms))
                TextField("Antonyms (comma separated)", text: listBinding(\.antonyms))
            }
        }
    }

    private var grammarForm: some View {
        Group {
            Section("Rule") { TextField("Grammar rule", text: $grammar.rule, axis: .vertical) }
            Section("Explanation") {
                TextField("Explanation", text: $grammar.explanation, axis: .vertical)
                TextField("Formula", text: $grammar.formula)
            }
            Section("Examples (one per line)") { TextEditor(text: lines($grammar.examples)).frame(minHeight: 90) }
            Section("Common mistakes (one per line)") { TextEditor(text: lines($grammar.commonMistakes)).frame(minHeight: 90) }
        }
    }

    private var readingForm: some View {
        Group {
            Section("Question") {
                TextField("Question", text: $reading.question, axis: .vertical)
                TextField("Passage excerpt", text: $reading.passageExcerpt, axis: .vertical)
            }
            Section("Answer") {
                TextField("Answer", text: $reading.answer, axis: .vertical)
                TextField("Explanation", text: $reading.explanation, axis: .vertical)
            }
        }
    }

    private var speakingForm: some View {
        Group {
            Section("Prompt") { TextField("Speaking prompt", text: $speaking.prompt, axis: .vertical) }
            Section("Sample answer") { TextField("Sample answer", text: $speaking.sampleAnswer, axis: .vertical) }
            Section("Useful phrases (one per line)") { TextEditor(text: lines($speaking.usefulPhrases)).frame(minHeight: 90) }
        }
    }

    private var basicForm: some View {
        Group {
            Section("Front") { TextField("Front", text: $basic.front, axis: .vertical) }
            Section("Back") {
                TextField("Back", text: $basic.back, axis: .vertical)
                TextField("Extra", text: $basic.extra, axis: .vertical)
            }
        }
    }

    // MARK: Bindings

    private func listBinding(_ keyPath: WritableKeyPath<VocabularyContent, [String]>) -> Binding<String> {
        Binding(get: { vocabulary[keyPath: keyPath].joined(separator: ", ") },
                set: { vocabulary[keyPath: keyPath] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    private func lines(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(get: { binding.wrappedValue.joined(separator: "\n") },
                set: { binding.wrappedValue = $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } })
    }

    // MARK: Actions

    private func load() {
        switch card.content {
        case .vocabulary(let v): vocabulary = v
        case .grammar(let g): grammar = g
        case .reading(let r): reading = r
        case .speaking(let s): speaking = s
        case .basic(let b): basic = b
        }
    }

    private var editedContent: CardContent {
        switch card.kind {
        case .vocabulary: return .vocabulary(vocabulary)
        case .grammar: return .grammar(grammar)
        case .reading: return .reading(reading)
        case .speaking: return .speaking(speaking)
        case .basic: return .basic(basic)
        }
    }

    private func save() {
        do {
            try model.repository.update(card, content: editedContent)
            model.invalidateSearch()
            dismiss()
        } catch {
            model.toast = error.localizedDescription
        }
    }

    private func explain() {
        guard model.require(model.gate.check(.aiExplanations)) else { return }
        guard let provider = model.aiProvider else {
            model.toast = AIError.notConfigured.localizedDescription
            return
        }
        let book = card.lesson?.unit?.book
        let options = model.settings.generationOptions(target: book?.targetLanguage, native: book?.nativeLanguage)
        let prompt = "\(editedContent.frontText)\n\n\(editedContent.backText)"
        isExplaining = true
        Task {
            defer { isExplaining = false }
            do {
                let response = try await provider.complete(AIRequest(system: PromptLibrary.explanationSystemPrompt(options),
                                                                     user: prompt, maxOutputTokens: 600))
                explanation = response.text
            } catch {
                explanation = error.localizedDescription
            }
        }
    }
}
