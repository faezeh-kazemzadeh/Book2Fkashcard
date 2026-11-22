import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction over destinations that can receive cards directly (instead of a
/// file export). Today: AnkiConnect on a desktop on the same network. Future:
/// a self-hosted sync server or AnkiWeb, should a public API become available.
public protocol AnkiSyncTarget: Sendable {
    func isReachable() async -> Bool
    func deckNames() async throws -> [String]
    func push(_ request: AnkiExportRequest) async throws -> AnkiPushResult
}

public struct AnkiPushResult: Sendable, Equatable {
    public var added: Int
    public var updated: Int
    public var failed: Int
}

/// Client for the AnkiConnect add-on (API version 6).
///
/// The desktop must run Anki with AnkiConnect, configured with
/// `"webBindAddress": "0.0.0.0"` and this app's origin in `webCorsOriginList`.
/// The iOS app needs `NSLocalNetworkUsageDescription` to reach it.
public struct AnkiConnectClient: AnkiSyncTarget {
    public var endpoint: URL
    public var apiKey: String?
    private let session: URLSession

    public init(endpoint: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public struct ConnectError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { "AnkiConnect: \(message)" }
    }

    // MARK: AnkiSyncTarget

    public func isReachable() async -> Bool {
        (try? await invoke("version", params: [String: Any]()) as? Int).map { $0 >= 6 } ?? false
    }

    public func deckNames() async throws -> [String] {
        (try await invoke("deckNames", params: [String: Any]()) as? [String]) ?? []
    }

    public func push(_ request: AnkiExportRequest) async throws -> AnkiPushResult {
        try await ensureNoteTypes()
        let writer = AnkiPackageWriter()
        var added = 0, updated = 0, failed = 0

        for deck in Set(request.cards.map { $0.deckPath.joined(separator: "::") }) {
            _ = try await invoke("createDeck", params: ["deck": deck])
        }

        for card in request.cards {
            let (modelID, values) = writer.noteFields(for: card, availableMedia: [])
            let modelName = modelID == AnkiPackageWriter.vocabularyModelID ? AnkiNoteTypes.vocabularyName : AnkiNoteTypes.basicName
            let names = modelID == AnkiPackageWriter.vocabularyModelID ? AnkiNoteTypes.vocabularyFields : AnkiNoteTypes.basicFields
            let fields = Dictionary(uniqueKeysWithValues: zip(names, values))
            do {
                // Notes are matched on the B2FID field so pushes are idempotent.
                let existing = try await invoke("findNotes", params: ["query": "B2FID:\(card.id.uuidString)"]) as? [Int] ?? []
                if let noteID = existing.first {
                    _ = try await invoke("updateNoteFields", params: ["note": ["id": noteID, "fields": fields] as [String: Any]])
                    updated += 1
                } else {
                    let note: [String: Any] = [
                        "deckName": card.deckPath.joined(separator: "::"),
                        "modelName": modelName,
                        "fields": fields,
                        "tags": card.tags.map { $0.replacingOccurrences(of: " ", with: "_") },
                        "options": ["allowDuplicate": false]
                    ]
                    _ = try await invoke("addNote", params: ["note": note])
                    added += 1
                }
            } catch {
                failed += 1
            }
        }
        return AnkiPushResult(added: added, updated: updated, failed: failed)
    }

    // MARK: Note types

    func ensureNoteTypes() async throws {
        let existing = (try await invoke("modelNames", params: [String: Any]()) as? [String]) ?? []
        let definitions: [(String, [String], String, String)] = [
            (AnkiNoteTypes.vocabularyName, AnkiNoteTypes.vocabularyFields, AnkiNoteTypes.vocabularyFront, AnkiNoteTypes.vocabularyBack),
            (AnkiNoteTypes.basicName, AnkiNoteTypes.basicFields, AnkiNoteTypes.basicFront, AnkiNoteTypes.basicBack)
        ]
        for (name, fields, front, back) in definitions where !existing.contains(name) {
            _ = try await invoke("createModel", params: [
                "modelName": name,
                "inOrderFields": fields,
                "css": AnkiNoteTypes.css,
                "cardTemplates": [["Name": "Card 1", "Front": front, "Back": back]]
            ] as [String: Any])
        }
    }

    // MARK: Transport

    @discardableResult
    func invoke(_ action: String, params: [String: Any]) async throws -> Any? {
        var body: [String: Any] = ["action": action, "version": 6, "params": params]
        if let apiKey { body["key"] = apiKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.b2fData(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectError(message: "invalid response")
        }
        if let error = object["error"] as? String { throw ConnectError(message: error) }
        return object["result"]
    }
}
