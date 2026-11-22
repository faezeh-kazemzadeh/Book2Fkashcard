import SwiftUI
import SwiftData
import B2FCore

struct StudyHomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \BookEntity.updatedAt, order: .reverse) private var books: [BookEntity]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    StudySessionView(scope: .all)
                } label: {
                    Label("Study all due cards", systemImage: "play.circle.fill").font(.headline)
                }
                .accessibilityIdentifier("studyAll")
                NavigationLink {
                    QuizHomeView(lessonIDs: nil)
                } label: {
                    Label("Quizzes", systemImage: "checklist")
                }
            }
            Section("By book") {
                ForEach(books.filter { !$0.allCards.isEmpty }) { book in
                    NavigationLink {
                        StudySessionView(scope: .init(lessonIDs: Set(book.allLessons.map(\.id))))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(book.title)
                            Text(counts(for: book))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Study")
    }

    private func counts(for book: BookEntity) -> String {
        let now = Date()
        let newPhase = CardPhase.new.rawValue
        var due = 0
        var fresh = 0
        for card in book.allCards {
            if card.phaseRaw == newPhase {
                fresh += 1
            } else if card.due <= now {
                due += 1
            }
        }
        return String(localized: "\(due) due · \(fresh) new")
    }
}

struct StudySessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: StudySessionViewModel
    @AccessibilityFocusState private var answerFocused: Bool

    init(scope: LibraryRepository.StudyScope) {
        _viewModel = State(initialValue: StudySessionViewModel(scope: scope))
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.progress)
                .accessibilityLabel("Session progress")
                .accessibilityValue("\(viewModel.remaining) cards remaining")

            if let card = viewModel.current {
                CardFaceView(card: card, showAnswer: viewModel.isAnswerShown, onSpeak: { speak(card) })
                    .id(card.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                    .onTapGesture { reveal() }
                    .accessibilityAction(named: "Show answer") { reveal() }

                if let prediction = viewModel.prediction {
                    Text("Predicted recall: \(prediction.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                controls
            } else {
                finishedView
            }
        }
        .padding()
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(repository: model.repository, settings: settings) }
        .animation(.snappy, value: viewModel.position)
        .sensoryFeedback(.selection, trigger: viewModel.isAnswerShown)
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.isAnswerShown {
            HStack(spacing: 8) {
                ForEach(Rating.allCases) { rating in
                    Button {
                        answer(rating)
                    } label: {
                        VStack(spacing: 2) {
                            Text(LocalizedStringKey(rating.label)).font(.headline)
                            Text(viewModel.intervalPreview[rating].map(IntervalFormatter.short) ?? "")
                                .font(.caption2).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: rating))
                    .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
                    .accessibilityLabel(Text(LocalizedStringKey(rating.label)))
                    .accessibilityHint(Text("Next review in \(viewModel.intervalPreview[rating].map(IntervalFormatter.short) ?? "")"))
                    .accessibilityIdentifier("rating-\(rating.rawValue)")
                }
            }
            .accessibilityFocused($answerFocused)
        } else {
            Button {
                reveal()
            } label: {
                Text("Show Answer").frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityIdentifier("showAnswer")
        }
    }

    private var finishedView: some View {
        ContentUnavailableView {
            Label("All done!", systemImage: "checkmark.seal.fill")
        } description: {
            if viewModel.reviewedCount > 0 {
                let correct = viewModel.reviewedCount - viewModel.againCount
                Text("You reviewed \(viewModel.reviewedCount) cards. \(correct) remembered.")
            } else {
                Text("No cards are due. Come back later or import a new book.")
            }
        }
    }

    private func reveal() {
        viewModel.reveal()
        answerFocused = true
        if settings.autoplayAudio, let card = viewModel.current, card.kind == .vocabulary { speak(card) }
    }

    private func answer(_ rating: Rating) {
        do {
            try viewModel.answer(rating, repository: model.repository)
            if settings.autoplayAudio, let next = viewModel.current, next.kind == .vocabulary, !viewModel.isAnswerShown {
                speak(next)
            }
        } catch {
            model.toast = error.localizedDescription
        }
    }

    private func speak(_ card: FlashcardEntity) {
        let language = card.lesson?.unit?.book?.targetLanguage ?? settings.targetLanguage
        model.speech.speak(card.frontText, language: language, accent: settings.accent, speed: settings.playbackSpeed)
    }

    private func color(for rating: Rating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }
}
