import Foundation
import CloudKit
import Network
import Observation
import CoreData

/// Observes connectivity, the iCloud account and CloudKit mirroring events
/// so the UI can show offline / syncing / synced / error states.
///
/// The app is offline-first: SwiftData is the source of truth on device and
/// NSPersistentCloudKitContainer (behind SwiftData) queues changes made offline
/// and exports them automatically once the network returns.
@MainActor
@Observable
final class SyncStatusMonitor {
    enum AccountState: Equatable { case unknown, available, noAccount, restricted, temporarilyUnavailable }
    enum SyncState: Equatable { case disabled, idle, syncing, failed(String) }

    private(set) var isOnline = true
    private(set) var account: AccountState = .unknown
    private(set) var sync: SyncState = .disabled
    private(set) var lastSuccessfulSync: Date?

    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "b2f.network"))

        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        })
    }

    deinit {
        pathMonitor.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(syncEnabled: Bool) async {
        sync = syncEnabled ? .idle : .disabled
        if syncEnabled { await refreshAccount() }
    }

    func refreshAccount() async {
        let status = try? await CKContainer(identifier: AppConstants.cloudKitContainer).accountStatus()
        switch status {
        case .available: account = .available
        case .noAccount: account = .noAccount
        case .restricted: account = .restricted
        case .temporarilyUnavailable: account = .temporarilyUnavailable
        default: account = .unknown
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard sync != .disabled else { return }
        if event.endDate == nil {
            sync = .syncing
        } else if let error = event.error {
            sync = .failed(error.localizedDescription)
        } else {
            sync = .idle
            lastSuccessfulSync = event.endDate
        }
    }

    var statusText: String {
        if !isOnline { return String(localized: "Offline – changes will sync later") }
        switch sync {
        case .disabled: return String(localized: "iCloud sync is off")
        case .syncing: return String(localized: "Syncing…")
        case .failed(let message): return String(localized: "Sync error: \(message)")
        case .idle:
            if account == .noAccount { return String(localized: "Sign in to iCloud to sync") }
            if let last = lastSuccessfulSync {
                return String(localized: "Synced \(last.formatted(.relative(presentation: .named)))")
            }
            return String(localized: "iCloud sync is on")
        }
    }
}
