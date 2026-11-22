import SwiftUI
import B2FCore

struct AnkiExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let scope: AnkiExportScope

    @State private var includeAudio = true
    @State private var includeScheduling = false
    @State private var progress: Double?
    @State private var result: AnkiExportResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Pronunciation audio", isOn: $includeAudio)
                    Toggle("Review progress (scheduling)", isOn: $includeScheduling)
                } footer: {
                    Text("Decks keep the book structure: Book › Unit › Lesson › Vocabulary / Grammar / Reading / Speaking, with tags. Audio is generated on device, so exporting works offline.")
                }

                if let progress, result == nil {
                    Section { ProgressView(value: progress) { Text("Preparing deck…") } }
                }

                if let result {
                    Section("Ready") {
                        LabeledContent("Notes", value: "\(result.noteCount)")
                        LabeledContent("Decks", value: "\(result.deckCount)")
                        LabeledContent("Audio files", value: "\(result.mediaCount)")
                        ShareLink(item: result.fileURL) {
                            Label("Share .apkg", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("shareApkg")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Export to Anki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { export() }.disabled(progress != nil && result == nil)
                }
            }
            .onAppear {
                includeAudio = settings.includeAudioInExport
                includeScheduling = settings.includeSchedulingInExport
            }
        }
    }

    private func export() {
        result = nil
        errorMessage = nil
        progress = 0
        let service = AnkiExportService(repository: model.repository, settings: settings, files: model.files)
        Task {
            do {
                result = try await service.export(scope: scope,
                                                  options: .init(includeAudio: includeAudio, includeScheduling: includeScheduling)) { value in
                    progress = value
                }
            } catch {
                errorMessage = error.localizedDescription
                progress = nil
            }
        }
    }
}
