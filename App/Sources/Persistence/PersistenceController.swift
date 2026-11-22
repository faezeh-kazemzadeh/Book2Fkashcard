import Foundation
import SwiftData
import OSLog

enum AppConstants {
    static let cloudKitContainer = "iCloud.com.book2flashcards.pro"
    static let appGroup = "group.com.book2flashcards.pro"
    static let keychainService = "com.book2flashcards.pro"
    static let subscriptionGroupID = "B2F_PREMIUM"
    static let privacyPolicyURL = URL(string: "https://book2flashcards.app/privacy")!
    static let termsURL = URL(string: "https://book2flashcards.app/terms")!
    static let supportURL = URL(string: "https://book2flashcards.app/support")!
}

let appLogger = Logger(subsystem: "com.book2flashcards.pro", category: "app")

/// Builds the SwiftData container. With `cloudSync` the store mirrors to the
/// user's private CloudKit database; otherwise it is local-only. The same store
/// file is used in both modes, so toggling sync never loses data.
enum PersistenceController {
    static func makeContainer(cloudSync: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(
            "Book2Flashcards",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: cloudSync && !inMemory ? .private(AppConstants.cloudKitContainer) : .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory { protectStoreFiles(at: configuration.url) }
        return container
    }

    /// Fallback chain used at launch: CloudKit store → local store → in-memory store,
    /// so a CloudKit configuration problem never blocks offline study.
    static func makeContainerWithFallback(cloudSync: Bool) -> (ModelContainer, Error?) {
        do {
            return (try makeContainer(cloudSync: cloudSync), nil)
        } catch {
            appLogger.error("Primary store failed: \(error.localizedDescription, privacy: .public)")
            if cloudSync, let local = try? makeContainer(cloudSync: false) { return (local, error) }
            // swiftlint:disable:next force_try
            return (try! makeContainer(cloudSync: false, inMemory: true), error)
        }
    }

    /// The store is readable after first unlock so background CloudKit sync and
    /// processing keep working; sensitive payloads (page images, source files)
    /// are additionally sealed with AES-GCM by `EncryptedFileStore`.
    private static func protectStoreFiles(at url: URL) {
        let directory = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let file = directory.appendingPathComponent(base + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: file.path)
        }
    }

    @MainActor
    static var preview: ModelContainer = {
        // swiftlint:disable:next force_try
        let container = try! makeContainer(cloudSync: false, inMemory: true)
        PreviewData.populate(container.mainContext)
        return container
    }()
}
