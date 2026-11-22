import SwiftUI
import SwiftData
import B2FCore

struct QuizHomeView: View {
    /// nil = all lessons.
    let lessonIDs: Set<UUID>?

    var body: some View {
        List(QuizType.allCases) { type in
            NavigationLink {
                QuizSessionView(type: type, lessonIDs: lessonIDs)
            } label: {
                Label(type.displayName, systemImage: icon(type))
            }
        }
        .navigationTitle("Quizzes")
    }

    private func icon(_ type: QuizType) -> String {
        switch type {
        case .multipleChoice: return "list.bullet.circle"
        case .fillInTheBlank: return "text.insert"
        case .listening: return "ear"
        case .speaking: return "mic"
        case .translation: return "character.bubble"
        case .typing: return "keyboard"
        case .vocabularyChallenge: return "bolt"
        case .grammarChallenge: return "text.book.closed"
        case .readingComprehension: return "doc.text.magnifyingglass"
        }
    }
}

struct QuizSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Query private var allCards: [FlashcardEntity]
    @State private var viewModel: QuizViewModel
    @State private var recognizer = SpeechRecognizer()
    @FocusState private var fieldFocused: Bool
    let lessonIDs: Set<UUID>?

    init(type: QuizType, lessonIDs: Set<UUID>?) {
        _viewModel = State(initialValue: QuizViewModel(type: type))
        self.lessonIDs = lessonIDs
    }

    private var scopedCards: [FlashcardEntity] {
        guard let lessonIDs else { return allCards }
        return allCards.filter { $0.lesson.map { lessonIDs.contains($0.id) } ?? false }
    }

    private var language: StudyLanguage {
        scopedCards.first?.lesson?.unit?.book?.targetLanguage ?? settings.targetLanguage
    }

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isLoading {
                ProgressView("Preparing quiz…")
            } else if let question = viewModel.current {
                Text("\(viewModel.index + 1) / \(viewModel.questions.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                questionView(question)
                Spacer(minLength: 0)
                feedback(question)
            } else {
                ContentUnavailableView {
                    Label(viewModel.questions.isEmpty ? "Not enough cards" : "Quiz complete",
                          systemImage: viewModel.questions.isEmpty ? "tray" : "rosette")
                } description: {
                    if viewModel.questions.isEmpty {
                        Text("This quiz needs more cards of the right type. Generate cards for a lesson first.")
                    } else {
                        Text("Score: \(viewModel.score) / \(viewModel.questions.count)")
                    }
                } actions: {
                    if !viewModel.questions.isEmpty {
                        Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .navigationTitle(viewModel.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { recognizer.stop() }
    }

    private func load() async {
        let repository = model.repository
        let passage = lessonIDs.map { ids in
            ids.compactMap { repository.lesson(id: $0) }
                .flatMap { $0.sections.filter { $0.kind == .reading } }
                .map(\.text)
                .joined(separator: "\n")
        }
        await viewModel.load(cards: scopedCards.filter { !$0.isSuspended }.map(\.quizInput), passage: passage,
                             provider: model.aiProvider)
    }

    @ViewBuilder
    private func questionView(_ question: QuizQuestion) -> some View {
        VStack(spacing: 16) {
            if let audio = question.audioText {
                Button {
                    model.speech.speak(audio, language: language, accent: settings.accent, speed: settings.playbackSpeed)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill").font(.title2)
                }
                .buttonStyle(.bordered)
                .onAppear { model.speech.speak(audio, language: language, accent: settings.accent, speed: settings.playbackSpeed) }
            }
            AdaptiveText(question.prompt, font: .title2.weight(.semibold))

            switch question.format {
            case .choice(let options, _):
                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            viewModel.submit(choice: index)
                        } label: {
                            AdaptiveText(option).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint(for: index, question: question))
                        .disabled(viewModel.grade != nil)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    }
                }
            case .typed:
                TextField("Your answer", text: Bindable(viewModel).typedAnswer)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
                    .onSubmit { viewModel.submitTyped() }
                    .disabled(viewModel.grade != nil)
                    .onAppear { fieldFocused = true }
                Button("Check") { viewModel.submitTyped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.typedAnswer.isEmpty || viewModel.grade != nil)
            case .spoken:
                VStack(spacing: 12) {
                    Text(recognizer.transcript.isEmpty ? String(localized: "Tap the microphone and speak") : recognizer.transcript)
                        .foregroundStyle(recognizer.transcript.isEmpty ? .secondary : .primary)
                    Button {
                        toggleListening()
                    } label: {
                        Image(systemName: recognizer.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 64))
                    }
                    .accessibilityLabel(recognizer.state == .listening ? "Stop recording" : "Start recording")
                    if case .unavailable(let message) = recognizer.state {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func feedback(_ question: QuizQuestion) -> some View {
        if let grade = viewModel.grade {
            VStack(spacing: 8) {
                switch grade {
                case .correct:
                    Label("Correct", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .almostCorrect(let expected):
                    Label("Almost – \(expected)", systemImage: "checkmark.circle").foregroundStyle(.orange)
                case .incorrect(let expected):
                    Label("Answer: \(expected)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
                if !question.explanation.isEmpty {
                    AdaptiveText(question.explanation, font: .callout).foregroundStyle(.secondary)
                }
                Button("Next") { viewModel.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .font(.headline)
            .accessibilityElement(children: .combine)
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: grade.isAcceptable ? "Correct" : "Incorrect")
            }
        }
    }

    private func tint(for index: Int, question: QuizQuestion) -> Color {
        guard viewModel.grade != nil, case .choice(_, let correct) = question.format else { return .accentColor }
        return index == correct ? .green : .secondary
    }

    private func toggleListening() {
        if recognizer.state == .listening {
            recognizer.stop()
            viewModel.submitSpoken(transcript: recognizer.transcript)
        } else {
            Task {
                guard await recognizer.requestAuthorization() else {
                    model.toast = String(localized: "Allow microphone and speech recognition in Settings to use speaking quizzes.")
                    return
                }
                recognizer.start(language: language, accent: settings.accent)
            }
        }
    }
}
