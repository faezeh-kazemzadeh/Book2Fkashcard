import SwiftUI
import B2FCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(StoreManager.self) private var store
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Subscription") {
                HStack {
                    Label(store.tier == .premium ? "Premium" : "Free plan", systemImage: store.tier == .premium ? "crown.fill" : "person")
                    Spacer()
                    if store.tier == .free {
                        Button("Upgrade") { model.presentedPaywall = .unlimitedBooks }
                    }
                }
                if store.tier == .free {
                    Text("\(model.repository.bookCount())/\(FeatureGate.freeBookLimit) books · \(model.repository.cardCount())/\(FeatureGate.freeCardLimit) cards")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Restore Purchases") { Task { await store.restore() } }
                Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            }

            Section("Languages") {
                Picker("Learning", selection: $settings.targetLanguage) {
                    ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                }
                Picker("Native language", selection: $settings.nativeLanguage) {
                    ForEach(StudyLanguage.allCases) { Text($0.englishName).tag($0) }
                }
                Picker("Level", selection: $settings.level) {
                    ForEach(GenerationOptions.CEFRLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Exam focus (e.g. IELTS)", text: $settings.examFocus)
            }

            Section {
                Toggle("Reading comprehension cards", isOn: $settings.generateReading)
                Toggle("Speaking cards", isOn: $settings.generateSpeaking)
            } header: {
                Text("Card generation")
            } footer: {
                Text("Vocabulary and grammar cards are always generated. Articles, very common words and duplicates are filtered out automatically.")
            }

            Section {
                Picker("Algorithm", selection: $settings.algorithm) {
                    ForEach(SRSAlgorithm.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.algorithm == .fsrs {
                    VStack(alignment: .leading) {
                        Text("Desired retention: \(settings.desiredRetention.formatted(.percent.precision(.fractionLength(0))))")
                        Slider(value: $settings.desiredRetention, in: 0.75...0.97, step: 0.01)
                            .accessibilityLabel("Desired retention")
                    }
                }
                Stepper("New cards per day: \(settings.newCardsPerDay)", value: $settings.newCardsPerDay, in: 0...200, step: 5)
                Button("Reset all scheduling…", role: .destructive) { confirmingReset = true }
            } header: {
                Text("Spaced repetition")
            } footer: {
                Text("FSRS predicts when you will forget each card and schedules reviews at your target retention. Switching algorithms keeps your review history.")
            }

            Section("Audio") {
                Picker("English accent", selection: $settings.accent) {
                    ForEach(EnglishAccent.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Playback speed", selection: $settings.playbackSpeed) {
                    ForEach(PlaybackSpeed.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Play pronunciation automatically", isOn: $settings.autoplayAudio)
            }

            Section("AI") {
                NavigationLink {
                    AIProviderSettingsView()
                } label: {
                    LabeledContent("Provider", value: settings.aiProvider.displayName)
                }
            }

            Section {
                Toggle("iCloud Sync", isOn: Binding(get: { settings.cloudSyncEnabled },
                                                    set: { value in Task { await model.setCloudSync(value) } }))
                Text(model.syncMonitor.statusText).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Sync")
            } footer: {
                Text("Syncs books, OCR text, page images, flashcards, statistics and preferences through your private iCloud database. Subscriptions are restored automatically via your Apple Account.")
            }

            Section("Anki") {
                Toggle("Include audio in exports", isOn: $settings.includeAudioInExport)
                Toggle("Include review scheduling", isOn: $settings.includeSchedulingInExport)
                NavigationLink("AnkiConnect (desktop)") { AnkiConnectSettingsView() }
            }

            Section("About") {
                Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
                Link("Terms of Use", destination: AppConstants.termsURL)
                Link("Support", destination: AppConstants.supportURL)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset scheduling for all cards?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { try? model.repository.resetSchedulingForAll() }
        } message: {
            Text("All cards become new. Review history is kept for statistics.")
        }
    }
}

struct AIProviderSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var openAIKey = ""
    @State private var azureKey = ""
    @State private var proxyToken = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Provider", selection: $settings.aiProvider) {
                    ForEach(AIProviderKind.allCases.filter { $0 != .localModel }) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Your keys are stored only on this device, protected by the Secure Enclave. Book text is sent to the selected provider to create cards; nothing is used for training by the app.")
            }

            switch settings.aiProvider {
            case .openAI:
                Section("OpenAI") {
                    SecureField(model.credentials.hasValue(.openAIKey) ? "Key saved – enter to replace" : "API key (sk-…)", text: $openAIKey)
                        .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Model", text: $settings.openAIModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            case .azureOpenAI:
                Section("Azure OpenAI") {
                    TextField("Endpoint (https://…openai.azure.com)", text: $settings.azureEndpoint)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Deployment name", text: $settings.azureDeployment).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("API version", text: $settings.azureAPIVersion).autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField(model.credentials.hasValue(.azureKey) ? "Key saved – enter to replace" : "API key", text: $azureKey)
                        .textContentType(.password)
                }
            case .proxy:
                Section("Book2Flashcards Cloud") {
                    TextField("Service URL", text: $settings.proxyBaseURL).keyboardType(.URL).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(model.credentials.hasValue(.proxyToken) ? "Token saved – enter to replace" : "Access token", text: $proxyToken)
                }
            case .appleOnDevice:
                Section {
                    Label(AppleOnDeviceProvider.isAvailable ? "Available on this device" : "Requires an Apple Intelligence–capable device with iOS 26 or later",
                          systemImage: AppleOnDeviceProvider.isAvailable ? "checkmark.circle" : "xmark.circle")
                } footer: {
                    Text("Runs entirely on device and offline. Best for explanations and short lessons.")
                }
            case .localModel:
                EmptyView()
            }

            Section {
                Button(isTesting ? "Testing…" : "Save & Test Connection") { saveAndTest() }
                    .disabled(isTesting)
                if let testResult { Text(testResult).font(.footnote) }
            }
        }
        .navigationTitle("AI Provider")
    }

    private func saveAndTest() {
        do {
            if !openAIKey.isEmpty { try model.credentials.set(openAIKey, for: .openAIKey) }
            if !azureKey.isEmpty { try model.credentials.set(azureKey, for: .azureKey) }
            if !proxyToken.isEmpty { try model.credentials.set(proxyToken, for: .proxyToken) }
        } catch {
            testResult = error.localizedDescription
            return
        }
        openAIKey = ""; azureKey = ""; proxyToken = ""
        guard let provider = model.aiProvider else {
            testResult = AIError.notConfigured.localizedDescription
            return
        }
        isTesting = true
        Task {
            defer { isTesting = false }
            do {
                let response = try await provider.complete(AIRequest(system: "Reply with the single word OK.", user: "Ping", maxOutputTokens: 200))
                let preview = String(response.text.prefix(20))
                testResult = String(localized: "Connected ✓ (\(preview))")
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}

struct AnkiConnectSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var status: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TextField("http://192.168.1.10:8765", text: $settings.ankiConnectURL)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Test connection") {
                    guard let url = URL(string: settings.ankiConnectURL) else { status = "Invalid URL"; return }
                    Task {
                        let client = AnkiConnectClient(endpoint: url, apiKey: model.credentials.value(.ankiConnectKey))
                        status = await client.isReachable() ? String(localized: "Connected to Anki ✓") : String(localized: "Anki not reachable")
                    }
                }
                if let status { Text(status).font(.footnote) }
            } footer: {
                Text("Preview: push cards straight into Anki on your computer. Install the AnkiConnect add-on, set webBindAddress to 0.0.0.0, and keep both devices on the same network. Exported .apkg files work without this.")
            }
        }
        .navigationTitle("AnkiConnect")
    }
}
