import Foundation
import CryptoKit

/// Protects small device-only secrets (the user's own AI API keys) with a
/// Secure Enclave P-256 key.
///
/// The Secure Enclave cannot store arbitrary data, so secrets are wrapped:
/// an ephemeral P-256 key agrees with the enclave key (ECDH), HKDF derives an
/// AES-GCM key, and the ciphertext plus ephemeral public key go to the Keychain.
/// Decryption requires the enclave-held private key, which never leaves the chip.
/// On devices/simulators without a Secure Enclave the secret is stored in the
/// Keychain with `ThisDeviceOnly` accessibility.
struct SecureSecretStore: Sendable {
    private let keychain = KeychainStore()
    private let enclaveKeyAccount = "secure-enclave-wrapping-key"

    func store(_ secret: String, account: String) throws {
        let plaintext = Data(secret.utf8)
        guard SecureEnclave.isAvailable else {
            try keychain.set(plaintext, for: account)
            return
        }
        let enclaveKey = try enclavePrivateKey()
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let symmetric = try deriveKey(shared: ephemeral.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey),
                                      ephemeralPublic: ephemeral.publicKey.rawRepresentation)
        let sealed = try AES.GCM.seal(plaintext, using: symmetric)
        guard let combined = sealed.combined else { throw CryptoKitError.incorrectParameterSize }
        // Layout: [1 byte version][65 bytes ephemeral public x9.63][AES-GCM combined]
        var blob = Data([1])
        blob.append(ephemeral.publicKey.x963Representation)
        blob.append(combined)
        try keychain.set(blob, for: account)
    }

    func secret(account: String) throws -> String? {
        guard let blob = try keychain.data(for: account) else { return nil }
        guard blob.first == 1, blob.count > 66, SecureEnclave.isAvailable else {
            return String(data: blob, encoding: .utf8)
        }
        let ephemeralPublic = try P256.KeyAgreement.PublicKey(x963Representation: blob[1..<66])
        let enclaveKey = try enclavePrivateKey()
        let symmetric = try deriveKey(shared: enclaveKey.sharedSecretFromKeyAgreement(with: ephemeralPublic),
                                      ephemeralPublic: ephemeralPublic.rawRepresentation)
        let box = try AES.GCM.SealedBox(combined: blob[66...])
        return String(data: try AES.GCM.open(box, using: symmetric), encoding: .utf8)
    }

    func remove(account: String) throws {
        try keychain.remove(account)
    }

    // MARK: Private

    private func enclavePrivateKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        if let stored = try keychain.data(for: enclaveKeyAccount) {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: stored)
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                                           .privateKeyUsage, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        // `dataRepresentation` is an encrypted handle only usable by this device's enclave.
        try keychain.set(key.dataRepresentation, for: enclaveKeyAccount)
        return key
    }

    private func deriveKey(shared: SharedSecret, ephemeralPublic: Data) throws -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: ephemeralPublic,
                                       sharedInfo: Data("b2f-secret-v1".utf8), outputByteCount: 32)
    }
}

/// Stores the user's AI provider credentials. Nothing is hard-coded in the binary;
/// in production the default provider is the backend proxy, which needs no key on device.
struct APICredentialStore: Sendable {
    enum Account: String, CaseIterable {
        case openAIKey = "ai.openai.key"
        case azureKey = "ai.azure.key"
        case proxyToken = "ai.proxy.token"
        case ankiConnectKey = "anki.connect.key"
    }

    private let store = SecureSecretStore()

    func value(_ account: Account) -> String? {
        guard let value = try? store.secret(account: account.rawValue), !value.isEmpty else { return nil }
        return value
    }

    func set(_ value: String?, for account: Account) throws {
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            try store.store(value.trimmingCharacters(in: .whitespacesAndNewlines), account: account.rawValue)
        } else {
            try store.remove(account: account.rawValue)
        }
    }

    func hasValue(_ account: Account) -> Bool { value(account) != nil }
}
