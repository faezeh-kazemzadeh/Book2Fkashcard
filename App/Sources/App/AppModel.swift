import Foundation
import SwiftData
import Observation
import B2FCore

/// Composition root. Owns long-lived services and hands them to view models.
/// Injected into the SwiftUI environment once, at the app root.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let store: StoreManager
    let syncMonitor: SyncStatusMonitor
    let speech: SpeechService
    let credentials = APICredentialStore()
    let files = EncryptedFileStore.shared

    private(set) var container: ModelContainer
    private(set) var containerGeneration = 0
    private(set) var startupError: String?

    /// Book imports in progress, keyed by book ID once known.
    var activeImports: [UUID: ImportProgress] = [:]
    var presentedPaywall: PremiumFeature?
    var toast: String?
    /// A document opened from another app ("Open in Book2Flashcards" / share sheet).
    var pendingOpenURL: URL?

    struct ImportProgress: Equatable {
        var title: String
        var detail: String
        var fraction: Double
    }

    @ObservationIgnored private var searchServiceCache: SearchService?

    init(settings: AppSettings = AppSettings(), inMemory: Bool = false) {
        self.settings = settings
        self.store = StoreManager()
        self.syncMonitor = SyncStatusMonitor()
        self.speech = SpeechService()
        if inMemory || ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") {
            // swiftlint:disable:next force_try
            self.container = try! PersistenceController.makeContainer(cloudSync: false, inMemory: true)
            if ProcessInfo.processInfo.arguments.contains("-UITestSeedData") { PreviewData.populate(container.mainContext) }
        } else {
            let (container, error) = PersistenceController.makeContainerWithFallback(cloudSync: settings.cloudSyncEnabled)
            self.container = container
            self.startupError = error?.localizedDescription
        }
    }

    func start() async {
        await store.start()
        // Sync is a premium feature; turn it off if the entitlement lapsed.
        if settings.cloudSyncEnabled && store.tier == .free {
            await setCloudSync(false)
        }
        await syncMonitor.configure(syncEnabled: settings.cloudSyncEnabled)
        settings.pullFromCloud()
    }

    // MARK: Factories

    var repository: LibraryRepository { LibraryRepository(context: container.mainContext) }
    var writer: LibraryWriter { LibraryWriter(modelContainer: container) }
    var aiProvider: (any AIProvider)? { AIProviderFactory(settings: settings, credentials: credentials).makeProvider() }
    var gate: FeatureGate { store.gate }

    var searchService: SearchService {
        if let cached = searchServiceCache { return cached }
        let service = SearchService(repository: repository)
        searchServiceCache = service
        return service
    }

    func makePipeline(target: StudyLanguage, native: StudyLanguage) -> BookProcessingPipeline {
        let provider = aiProvider
        return BookProcessingPipeline(dependencies: .init(
            writer: writer,
            ocr: OCREngine(aiCorrector: store.tier == .premium ? provider : nil),
            provider: provider,
            tier: store.tier,
            options: settings.generationOptions(target: target, native: native)))
    }

    // MARK: Cloud sync

    /// Rebuilds the model container with or without CloudKit mirroring.
    func setCloudSync(_ enabled: Bool) async {
        if enabled, case .requiresPremium(let feature) = gate.check(.cloudSync) {
            presentedPaywall = feature
            return
        }
        settings.cloudSyncEnabled = enabled
        if enabled { settings.pushAllToCloud() }
        do {
            container = try PersistenceController.makeContainer(cloudSync: enabled)
            containerGeneration += 1
            searchServiceCache = nil
        } catch {
            toast = error.localizedDescription
        }
        await syncMonitor.configure(syncEnabled: enabled)
    }

    // MARK: Gating helpers

    /// Returns true when allowed; otherwise presents the paywall.
    func require(_ decision: GateDecision) -> Bool {
        switch decision {
        case .allowed, .partiallyAllowed: return true
        case .requiresPremium(let feature):
            presentedPaywall = feature
            return false
        }
    }

    func invalidateSearch() { searchServiceCache?.invalidate() }
}
