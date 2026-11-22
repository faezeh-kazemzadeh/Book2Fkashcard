import SwiftUI
import SwiftData
import PhotosUI
import B2FCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \BookEntity.updatedAt, order: .reverse) private var books: [BookEntity]
    @State private var viewModel = LibraryViewModel()
    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        @Bindable var viewModel = viewModel
        Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("No books yet", systemImage: "books.vertical")
                } description: {
                    Text("Import a PDF, EPUB, Word file or photos of your textbook, or scan pages with the camera.")
                } actions: {
                    importMenu.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(books) { book in
                            NavigationLink(value: book.id) {
                                BookCard(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if book.status == .failed || book.allLessons.contains(where: { $0.generationStatus != .ready }) {
                                    Button("Resume processing", systemImage: "arrow.clockwise") {
                                        viewModel.resume(bookID: book.id, model: model)
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    viewModel.delete(book, model: model)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Library")
        .navigationDestination(for: UUID.self) { id in
            if let book = books.first(where: { $0.id == id }) { BookDetailView(book: book) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { importMenu }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: DocumentImporter.supportedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): urls.first.map { viewModel.prepareImport(url: $0, model: model) }
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItems, maxSelectionCount: 50, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                photoItems = []
                viewModel.prepareImport(images: images, scanned: false, model: model)
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { images in
                showingScanner = false
                viewModel.prepareImport(images: images, scanned: true, model: model)
            } onCancel: {
                showingScanner = false
            } onError: { error in
                showingScanner = false
                viewModel.errorMessage = error.localizedDescription
            }
            .ignoresSafeArea()
        }
        .sheet(item: $viewModel.pendingImport) { pending in
            ImportOptionsSheet(pending: pending) { confirmed in
                viewModel.confirm(confirmed, model: model)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { viewModel.errorMessage != nil },
                                                             set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: model.pendingOpenURL, initial: true) { _, url in
            guard let url else { return }
            model.pendingOpenURL = nil
            viewModel.prepareImport(url: url, model: model)
        }
    }

    private var importMenu: some View {
        Menu {
            Button("Import File", systemImage: "doc.badge.plus") { showingFileImporter = true }
            if DocumentScannerView.isSupported {
                Button("Scan Pages", systemImage: "doc.viewfinder") { showingScanner = true }
            }
            Button("Photos", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
            Button("Import Anki Deck", systemImage: "rectangle.stack.badge.plus") { showingFileImporter = true }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .accessibilityIdentifier("addBookMenu")
    }
}

struct BookCard: View {
    let book: BookEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary)
                if let data = book.coverThumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)

            Text(book.title).font(.headline).lineLimit(2)
            if book.status.isActive {
                ProgressView(value: book.progress) {
                    Text(book.status.label).font(.caption)
                } currentValueLabel: {
                    Text(book.statusMessage).font(.caption2)
                }
            } else if book.status == .failed {
                Label(book.statusMessage.isEmpty ? "Import failed" : book.statusMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
            } else {
                Text("\(book.allLessons.count) lessons · \(book.allCards.count) cards")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the book")
    }
}

/// Confirms title and languages before processing starts.
struct ImportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var pending: LibraryViewModel.PendingImport
    let onConfirm: (LibraryViewModel.PendingImport) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Book") {
                    TextField("Title", text: $pending.title)
                }
                Section {
                    Picker("Language you are learning", selection: $pending.target) {
                        ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                    }
                    Picker("Your native language", selection: $pending.native) {
                        ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                    }
                } footer: {
                    Text("Used for OCR, translations and explanations.")
                }
            }
            .navigationTitle("New Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onConfirm(pending); dismiss() }
                        .accessibilityIdentifier("confirmImport")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
