import SwiftUI
import SwiftData
import B2FCore

struct LessonDetailView: View {
    @Environment(AppModel.self) private var model
    let lesson: LessonEntity
    @State private var filter: CardKind?
    @State private var editingCard: FlashcardEntity?
    @State private var exportScope: AnkiExportScope?
    @State private var isRegenerating = false

    private var cards: [FlashcardEntity] {
        (lesson.cards ?? [])
            .filter { filter == nil || $0.kind == filter }
            .sorted { $0.priorityRaw != $1.priorityRaw ? $0.priorityRaw > $1.priorityRaw : $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                Picker("Card type", selection: $filter) {
                    Text("All").tag(CardKind?.none)
                    ForEach(CardKind.allCases.filter { kind in (lesson.cards ?? []).contains { $0.kind == kind } }) { kind in
                        Text(kind.displayName).tag(CardKind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                HStack {
                    NavigationLink {
                        StudySessionView(scope: .init(lessonIDs: [lesson.id]))
                    } label: {
                        Label("Study", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                NavigationLink {
                    QuizHomeView(lessonIDs: [lesson.id])
                } label: {
                    Label("Quiz", systemImage: "checklist")
                }
            }

            if !lesson.sections.isEmpty {
                Section("Lesson structure") {
                    ForEach(lesson.sections) { section in
                        DisclosureGroup {
                            AdaptiveText(String(section.text.prefix(1_500)), font: .callout, alignment: .leading)
                                .textSelection(.enabled)
                        } label: {
                            Label(section.title, systemImage: icon(for: section.kind))
                        }
                    }
                }
            }

            Section("\(cards.count) cards") {
                ForEach(cards) { card in
                    Button { editingCard = card } label: { CardRow(card: card) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { try? model.repository.delete(card) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { try? model.repository.setSuspended(card, !card.isSuspended) } label: {
                                Label(card.isSuspended ? "Unsuspend" : "Suspend", systemImage: "pause.circle")
                            }
                            .tint(.gray)
                        }
                }
            }
        }
        .navigationTitle(lesson.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    guard model.require(model.gate.check(.ankiExport)) else { return }
                    exportScope = .lesson(lesson.id)
                } label: {
                    Label("Export to Anki", systemImage: "square.and.arrow.up")
                }
                Button {
                    regenerate()
                } label: {
                    Label("Generate more cards", systemImage: "sparkles")
                }
                .disabled(isRegenerating)
            }
        }
        .sheet(item: $editingCard) { card in
            CardEditorView(card: card)
        }
        .sheet(item: $exportScope) { scope in
            AnkiExportView(scope: scope)
        }
    }

    private func icon(for kind: LessonSectionKind) -> String {
        switch kind {
        case .vocabulary: return "textformat.abc"
        case .grammar: return "text.book.closed"
        case .reading: return "doc.plaintext"
        case .listening: return "ear"
        case .speaking: return "waveform"
        case .writing: return "pencil"
        case .exercises: return "checklist"
        case .general: return "doc"
        }
    }

    /// Runs generation again for this lesson; the quality filter skips duplicates of existing cards.
    private func regenerate() {
        guard let book = lesson.unit?.book else { return }
        isRegenerating = true
        let generator = FlashcardGenerator(provider: model.aiProvider,
                                           options: model.settings.generationOptions(target: book.targetLanguage,
                                                                                    native: book.nativeLanguage))
        let node = lesson.node
        let keys = model.repository.existingDeduplicationKeys(in: book)
        let lessonID = lesson.id
        let unitTitle = lesson.unit?.title ?? ""
        let bookTitle = book.title
        let writer = model.writer
        let gate = model.gate
        let current = model.repository.cardCount()
        Task {
            defer { isRegenerating = false }
            do {
                let result = try await generator.generate(for: node, bookTitle: bookTitle, unitTitle: unitTitle, existingKeys: keys)
                var drafts = result.drafts
                switch gate.canAddCards(currentCardCount: current, adding: drafts.count) {
                case .allowed: break
                case .partiallyAllowed(let remaining): drafts = Array(drafts.prefix(remaining))
                case .requiresPremium(let feature): model.presentedPaywall = feature; return
                }
                try await writer.saveCards(lessonID: lessonID, drafts: drafts)
                model.toast = String(localized: "Added \(drafts.count) new cards")
                model.invalidateSearch()
            } catch {
                model.toast = error.localizedDescription
            }
        }
    }
}

struct CardRow: View {
    let card: FlashcardEntity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    AdaptiveText(card.frontText, font: .body.weight(.semibold), alignment: .leading)
                    PriorityBadge(priority: card.priority)
                }
                AdaptiveText(card.backText.components(separatedBy: "\n").first ?? "", font: .callout, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if card.isFlaggedForReview { ConfidenceWarning() }
            }
            Spacer(minLength: 0)
            if card.isSuspended {
                Image(systemName: "pause.circle").foregroundStyle(.secondary).accessibilityLabel("Suspended")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit card")
    }
}
