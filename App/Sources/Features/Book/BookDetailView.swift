import SwiftUI
import SwiftData
import B2FCore

struct BookDetailView: View {
    @Environment(AppModel.self) private var model
    let book: BookEntity
    @State private var exportScope: AnkiExportScope?
    @State private var selectedLessons: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    @State private var confirmingRebuild = false

    var body: some View {
        List(selection: $selectedLessons) {
            Section {
                header
            }

            if !book.lowConfidencePages.isEmpty {
                Section {
                    NavigationLink {
                        PageReviewListView(book: book)
                    } label: {
                        Label("\(book.lowConfidencePages.count) pages need review", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Text on these pages was recognised with low confidence. Correct it to improve your cards.")
                }
            }

            ForEach(book.sortedUnits) { unit in
                Section(unit.title) {
                    ForEach(unit.sortedLessons) { lesson in
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            LessonRow(lesson: lesson)
                        }
                        .tag(lesson.id)
                    }
                }
            }

            Section {
                NavigationLink("All pages") { PageReviewListView(book: book, showAll: true) }
            }
        }
        .navigationTitle(book.title)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink {
                    StudySessionView(scope: .init(lessonIDs: Set(book.allLessons.map(\.id))))
                } label: {
                    Label("Study", systemImage: "play.fill")
                }
                .disabled(book.allCards.isEmpty)

                Menu {
                    Button("Export Entire Book", systemImage: "books.vertical") { export(.book(book.id)) }
                    Button(editMode.isEditing ? "Export Selected Lessons" : "Select Lessons…", systemImage: "checklist") {
                        if editMode.isEditing, !selectedLessons.isEmpty {
                            export(.lessons(selectedLessons))
                            editMode = .inactive
                        } else {
                            editMode = .active
                        }
                    }
                } label: {
                    Label("Export to Anki", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("exportMenu")

                Menu {
                    Button("Rebuild lessons from pages", systemImage: "arrow.triangle.2.circlepath") { confirmingRebuild = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Rebuild lessons?", isPresented: $confirmingRebuild, titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) { rebuild() }
        } message: {
            Text("Lessons are detected again from the (corrected) page text and new cards are generated. Existing cards and their review history for this book are replaced.")
        }
        .sheet(item: $exportScope) { scope in
            AnkiExportView(scope: scope)
        }
        .onAppear { book.lastOpenedAt = Date() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let data = book.coverThumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary) }
                Text("\(book.targetLanguage.englishName) → \(book.nativeLanguage.englishName)")
                Text("\(book.pageCount) pages · \(book.allLessons.count) lessons · \(book.allCards.count) cards")
                    .font(.footnote).foregroundStyle(.secondary)
                if book.status.isActive {
                    ProgressView(value: book.progress) { Text(book.status.label) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rebuild() {
        let pipeline = model.makePipeline(target: book.targetLanguage, native: book.nativeLanguage)
        let bookID = book.id
        Task {
            do {
                try await pipeline.structure(bookID: bookID, continuation: nil)
                for await event in await pipeline.resume(bookID: bookID) {
                    if case .finished(_, let cards) = event { model.toast = String(localized: "Created \(cards) flashcards") }
                    if case .limitReached(let feature) = event { model.presentedPaywall = feature }
                }
                model.invalidateSearch()
            } catch {
                model.toast = error.localizedDescription
            }
        }
    }

    private func export(_ scope: AnkiExportScope) {
        guard model.require(model.gate.check(.ankiExport)) else { return }
        exportScope = scope
    }
}

extension AnkiExportScope: Identifiable {
    var id: String {
        switch self {
        case .lesson(let id): return "lesson-\(id)"
        case .lessons(let ids): return "lessons-\(ids.map(\.uuidString).sorted().joined())"
        case .book(let id): return "book-\(id)"
        }
    }
}

struct LessonRow: View {
    let lesson: LessonEntity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.body.weight(.medium))
                HStack(spacing: 10) {
                    ForEach(CardKind.allCases, id: \.self) { kind in
                        let count = (lesson.cards ?? []).filter { $0.kind == kind }.count
                        if count > 0 {
                            Label("\(count)", systemImage: kind.systemImage)
                                .accessibilityLabel("\(count) \(kind.displayName) cards")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if lesson.generationStatus == .generating {
                ProgressView()
            } else if lesson.generationStatus == .pending {
                Image(systemName: "hourglass").foregroundStyle(.secondary).accessibilityLabel("Waiting for cards")
            }
        }
    }
}
