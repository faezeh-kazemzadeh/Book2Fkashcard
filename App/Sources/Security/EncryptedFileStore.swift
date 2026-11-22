import Foundation
import CryptoKit

/// Encrypts page images and imported source files with AES-256-GCM.
///
/// The data-encryption key lives in iCloud Keychain (synchronizable,
/// after-first-unlock) so pages synced through CloudKit can be decrypted on the
/// user's other devices but are opaque to anyone holding only the CloudKit
/// records or a device backup without the keychain.
final class EncryptedFileStore: @unchecked Sendable {
    static let shared = EncryptedFileStore()

    private let keychain = KeychainStore()
    private let keyAccount = "content-encryption-key-v1"
    private var cachedKey: SymmetricKey?
    /// Overrides the Keychain-backed key (tests). Production always uses the Keychain.
    private let fixedKey: SymmetricKey?
    private let lock = NSLock()

    /// Local, non-synced storage for originals and generated media (TTS audio).
    let rootDirectory: URL
    var mediaDirectory: URL { rootDirectory.appendingPathComponent("Media", isDirectory: true) }
    var originalsDirectory: URL { rootDirectory.appendingPathComponent("Originals", isDirectory: true) }

    init(rootDirectory: URL? = nil, fixedKey: SymmetricKey? = nil) {
        self.fixedKey = fixedKey
        let base = rootDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Book2Flashcards", isDirectory: true)
        self.rootDirectory = base
        for directory in [base, base.appendingPathComponent("Media"), base.appendingPathComponent("Originals")] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key()).combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return combined
    }

    func open(_ sealed: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key())
    }

    /// Writes an encrypted copy of an imported original so it can be re-processed later.
    func storeOriginal(_ data: Data, bookID: UUID, fileExtension: String) throws -> URL {
        let url = originalsDirectory.appendingPathComponent("\(bookID.uuidString).\(fileExtension).sealed")
        try seal(data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    func removeOriginal(bookID: UUID) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: originalsDirectory.path)) ?? []
        for file in files where file.hasPrefix(bookID.uuidString) {
            try? FileManager.default.removeItem(at: originalsDirectory.appendingPathComponent(file))
        }
    }

    private func key() throws -> SymmetricKey {
        if let fixedKey { return fixedKey }
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        if let data = try keychain.data(for: keyAccount, synchronizable: true) {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        let key = SymmetricKey(size: .bits256)
        try keychain.set(key.withUnsafeBytes { Data($0) }, for: keyAccount, accessibility: .afterFirstUnlockSynchronizable)
        cachedKey = key
        return key
    }
}
