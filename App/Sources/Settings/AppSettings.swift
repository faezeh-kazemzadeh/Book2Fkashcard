import Foundation
import Observation
import B2FCore

/// User preferences. Stored in `UserDefaults` and mirrored to iCloud through
/// `NSUbiquitousKeyValueStore` (when sync is on), so they follow the user
/// across devices. Secrets are never stored here (see `APICredentialStore`).
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var observer: NSObjectProtocol?

    enum Key: String, CaseIterable {
        case algorithm, desiredRetention, newCardsPerDay, targetLanguage, nativeLanguage, accent, playbackSpeed
        case autoplayAudio, level, examFocus, aiProvider, openAIModel, azureEndpoint, azureDeployment, azureAPIVersion
        case proxyBaseURL, cloudSyncEnabled, includeSchedulingInExport, includeAudioInExport, generateReading
        case generateSpeaking, onboardingComplete, ankiConnectURL
    }

    /// Keys never mirrored to iCloud (device-specific).
    private static let localOnly: Set<Key> = [.cloudSyncEnabled, .ankiConnectURL]

    var algorithm: SRSAlgorithm { didSet { save(.algorithm, algorithm.rawValue) } }
    var desiredRetention: Double { didSet { save(.desiredRetention, desiredRetention) } }
    var newCardsPerDay: Int { didSet { save(.newCardsPerDay, newCardsPerDay) } }
    var targetLanguage: StudyLanguage { didSet { save(.targetLanguage, targetLanguage.rawValue) } }
    var nativeLanguage: StudyLanguage { didSet { save(.nativeLanguage, nativeLanguage.rawValue) } }
    var accent: EnglishAccent { didSet { save(.accent, accent.rawValue) } }
    var playbackSpeed: PlaybackSpeed { didSet { save(.playbackSpeed, playbackSpeed.rawValue) } }
    var autoplayAudio: Bool { didSet { save(.autoplayAudio, autoplayAudio) } }
    var level: GenerationOptions.CEFRLevel { didSet { save(.level, level.rawValue) } }
    var examFocus: String { didSet { save(.examFocus, examFocus) } }
    var aiProvider: AIProviderKind { didSet { save(.aiProvider, aiProvider.rawValue) } }
    var openAIModel: String { didSet { save(.openAIModel, openAIModel) } }
    var azureEndpoint: String { didSet { save(.azureEndpoint, azureEndpoint) } }
    var azureDeployment: String { didSet { save(.azureDeployment, azureDeployment) } }
    var azureAPIVersion: String { didSet { save(.azureAPIVersion, azureAPIVersion) } }
    var proxyBaseURL: String { didSet { save(.proxyBaseURL, proxyBaseURL) } }
    var cloudSyncEnabled: Bool { didSet { save(.cloudSyncEnabled, cloudSyncEnabled) } }
    var includeSchedulingInExport: Bool { didSet { save(.includeSchedulingInExport, includeSchedulingInExport) } }
    var includeAudioInExport: Bool { didSet { save(.includeAudioInExport, includeAudioInExport) } }
    var generateReading: Bool { didSet { save(.generateReading, generateReading) } }
    var generateSpeaking: Bool { didSet { save(.generateSpeaking, generateSpeaking) } }
    var onboardingComplete: Bool { didSet { save(.onboardingComplete, onboardingComplete) } }
    var ankiConnectURL: String { didSet { save(.ankiConnectURL, ankiConnectURL) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func string(_ key: Key) -> String? { defaults.string(forKey: key.rawValue) }
        algorithm = string(.algorithm).flatMap(SRSAlgorithm.init) ?? .fsrs
        desiredRetention = defaults.object(forKey: Key.desiredRetention.rawValue) as? Double ?? 0.9
        newCardsPerDay = defaults.object(forKey: Key.newCardsPerDay.rawValue) as? Int ?? 20
        targetLanguage = string(.targetLanguage).flatMap(StudyLanguage.init) ?? .english
        nativeLanguage = string(.nativeLanguage).flatMap(StudyLanguage.init) ?? Self.defaultNativeLanguage()
        accent = string(.accent).flatMap(EnglishAccent.init) ?? .american
        playbackSpeed = (defaults.object(forKey: Key.playbackSpeed.rawValue) as? Double).flatMap(PlaybackSpeed.init) ?? .normal
        autoplayAudio = defaults.object(forKey: Key.autoplayAudio.rawValue) as? Bool ?? true
        level = string(.level).flatMap(GenerationOptions.CEFRLevel.init) ?? .b1
        examFocus = string(.examFocus) ?? ""
        aiProvider = string(.aiProvider).flatMap(AIProviderKind.init) ?? Self.defaultProvider()
        openAIModel = string(.openAIModel) ?? "gpt-5-mini"
        azureEndpoint = string(.azureEndpoint) ?? ""
        azureDeployment = string(.azureDeployment) ?? ""
        azureAPIVersion = string(.azureAPIVersion) ?? "2024-10-21"
        proxyBaseURL = string(.proxyBaseURL) ?? (Bundle.main.object(forInfoDictionaryKey: "B2FProxyBaseURL") as? String ?? "")
        cloudSyncEnabled = defaults.object(forKey: Key.cloudSyncEnabled.rawValue) as? Bool ?? false
        includeSchedulingInExport = defaults.object(forKey: Key.includeSchedulingInExport.rawValue) as? Bool ?? false
        includeAudioInExport = defaults.object(forKey: Key.includeAudioInExport.rawValue) as? Bool ?? true
        generateReading = defaults.object(forKey: Key.generateReading.rawValue) as? Bool ?? true
        generateSpeaking = defaults.object(forKey: Key.generateSpeaking.rawValue) as? Bool ?? true
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete.rawValue)
        ankiConnectURL = string(.ankiConnectURL) ?? ""

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in self?.pullFromCloud() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Derived

    var schedulerConfiguration: SchedulerConfiguration {
        SchedulerConfiguration(desiredRetention: desiredRetention)
    }

    var scheduler: any SpacedRepetitionScheduler {
        SchedulerFactory.make(algorithm, configuration: schedulerConfiguration)
    }

    func generationOptions(target: StudyLanguage? = nil, native: StudyLanguage? = nil) -> GenerationOptions {
        var kinds: Set<CardKind> = [.vocabulary, .grammar]
        if generateReading { kinds.insert(.reading) }
        if generateSpeaking { kinds.insert(.speaking) }
        return GenerationOptions(targetLanguage: target ?? targetLanguage, nativeLanguage: native ?? nativeLanguage,
                                 accent: accent, level: level, kinds: kinds,
                                 examFocus: examFocus.isEmpty ? nil : examFocus)
    }

    // MARK: Persistence

    private func save(_ key: Key, _ value: Any) {
        defaults.set(value, forKey: key.rawValue)
        if cloudSyncEnabled, !Self.localOnly.contains(key) {
            cloud.set(value, forKey: key.rawValue)
        }
    }

    /// Pushes every syncable preference (used when sync is first enabled).
    func pushAllToCloud() {
        for key in Key.allCases where !Self.localOnly.contains(key) {
            if let value = defaults.object(forKey: key.rawValue) { cloud.set(value, forKey: key.rawValue) }
        }
        cloud.synchronize()
    }

    func pullFromCloud() {
        guard cloudSyncEnabled else { return }
        func string(_ key: Key) -> String? { cloud.string(forKey: key.rawValue) }
        if let v = string(.algorithm).flatMap(SRSAlgorithm.init) { algorithm = v }
        if let v = cloud.object(forKey: Key.desiredRetention.rawValue) as? Double { desiredRetention = v }
        if let v = cloud.object(forKey: Key.newCardsPerDay.rawValue) as? Int { newCardsPerDay = v }
        if let v = string(.targetLanguage).flatMap(StudyLanguage.init) { targetLanguage = v }
        if let v = string(.nativeLanguage).flatMap(StudyLanguage.init) { nativeLanguage = v }
        if let v = string(.accent).flatMap(EnglishAccent.init) { accent = v }
        if let v = (cloud.object(forKey: Key.playbackSpeed.rawValue) as? Double).flatMap(PlaybackSpeed.init) { playbackSpeed = v }
        if let v = string(.level).flatMap(GenerationOptions.CEFRLevel.init) { level = v }
        if let v = string(.aiProvider).flatMap(AIProviderKind.init) { aiProvider = v }
    }

    private static func defaultNativeLanguage() -> StudyLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "fa"
        return StudyLanguage(rawValue: code) ?? .persian
    }

    private static func defaultProvider() -> AIProviderKind {
        let proxy = Bundle.main.object(forInfoDictionaryKey: "B2FProxyBaseURL") as? String ?? ""
        return proxy.isEmpty ? .openAI : .proxy
    }
}
