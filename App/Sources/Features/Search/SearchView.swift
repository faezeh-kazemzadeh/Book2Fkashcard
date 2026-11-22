import SwiftUI
import SwiftData
import Observation
import B2FCore

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var scopes: Set<SearchScope> = Set(SearchScope.allCases)
    private(set) var hits: [SearchHit] = []

    func run(service: SearchService) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hits = trimmed.isEmpty ? [] : service.search(trimmed, scopes: scopes)
    }

    func toggle(_ scope: SearchScope) {
        if scopes.contains(scope) && scopes.count > 1 { scopes.remove(scope) } else { scopes.insert(scope) }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = SearchViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(SearchScope.allCases) { scope in
                            Button {
                                viewModel.toggle(scope)
                                viewModel.run(service: model.searchService)
                            } label: {
                                Text(scope.displayName)
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.scopes.contains(scope) ? .accentColor : .secondary)
                            .accessibilityAddTraits(viewModel.scopes.contains(scope) ? .isSelected : [])
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            ForEach(viewModel.hits) { hit in
                NavigationLink {
                    destination(for: hit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            AdaptiveText(hit.document.title, font: .headline, alignment: .leading)
                            Spacer()
                            Text(hit.document.scope.displayName).font(.caption2).foregroundStyle(.secondary)
                        }
                        AdaptiveText(hit.snippet, font: .callout, alignment: .leading)
                            .foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
        .overlay {
            if !viewModel.query.isEmpty && viewModel.hits.isEmpty {
                ContentUnavailableView.search(text: viewModel.query)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $viewModel.query, prompt: "Words, definitions, grammar, page text…")
        .onChange(of: viewModel.query) { _, _ in viewModel.run(service: model.searchService) }
        .onAppear { model.searchService.rebuild() }
    }

    @ViewBuilder
    private func destination(for hit: SearchHit) -> some View {
        let repository = model.repository
        switch hit.document.scope {
        case .books:
            if let book = hit.document.bookID.flatMap(repository.book(id:)) { BookDetailView(book: book) }
        case .ocrText:
            if let book = hit.document.bookID.flatMap(repository.book(id:)),
               let page = book.sortedPages.first(where: { $0.index == hit.document.pageIndex }) {
                PageReviewView(page: page)
            }
        case .lessons:
            if let lesson = hit.document.lessonID.flatMap(repository.lesson(id:)) { LessonDetailView(lesson: lesson) }
        case .vocabulary, .definitions, .examples, .grammar:
            if let card = repository.card(id: hit.document.id) { CardEditorView(card: card) }
        }
    }
}
