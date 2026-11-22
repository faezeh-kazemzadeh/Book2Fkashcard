import SwiftUI
import B2FCore

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "books.vertical.fill").font(.system(size: 44)).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Turn your textbooks into flashcards").font(.title2.bold())
                        Text("Import a book or scan pages. Book2Flashcards finds the lessons, extracts vocabulary and grammar, and builds study-ready cards you can review here or export to Anki.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("About you") {
                    Picker("I'm learning", selection: $settings.targetLanguage) {
                        ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                    }
                    Picker("My native language", selection: $settings.nativeLanguage) {
                        ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                    }
                    Picker("My level", selection: $settings.level) {
                        ForEach(GenerationOptions.CEFRLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Get Started") { settings.onboardingComplete = true }
                        .accessibilityIdentifier("getStarted")
                }
            }
        }
    }
}
