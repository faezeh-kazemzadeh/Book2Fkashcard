import Foundation

public struct ImportedAnkiNote: Sendable, Hashable {
    public var guid: String
    public var noteTypeName: String
    public var fieldNames: [String]
    public var fieldValues: [String]
    public var tags: [String]
    public var deckPath: [String]
    public var scheduling: SchedulingState?
    public var isSuspended: Bool

    public func field(_ name: String) -> String? {
        guard let index = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
              index < fieldValues.count else { return nil }
        return fieldValues[index]
    }
}

public struct AnkiImportResult: Sendable {
    public var notes: [ImportedAnkiNote]
    public var deckNames: [String]
    /// Media written to the destination directory, by file name.
    public var mediaFiles: [String]
}

/// Reads `.apkg` (and `.colpkg`) files produced by Anki 2.1.x, AnkiMobile and AnkiDroid.
///
/// Supports schema 11 (`collection.anki2`, `collection.anki21`) and uncompressed
/// schema 18 collections. Zstandard-compressed `collection.anki21b` packages are
/// detected and reported with instructions to re-export in compatibility mode.
public struct AnkiPackageReader {

    public init() {}

    public func read(packageAt url: URL, mediaDestination: URL) throws -> AnkiImportResult {
        let data = try Data(contentsOf: url)
        let entries: [ZipArchive.CentralEntry]
        do {
            entries = try ZipArchive.listEntries(in: data)
        } catch {
            throw AnkiError.invalidPackage("not a ZIP archive")
        }
        let names = Set(entries.map(\.path))

        let collectionName: String
        if names.contains("collection.anki21") {
            collectionName = "collection.anki21"
        } else if names.contains("collection.anki21b") {
            throw AnkiError.unsupportedCollectionFormat
        } else if names.contains("collection.anki2") {
            collectionName = "collection.anki2"
        } else {
            throw AnkiError.invalidPackage("no collection found")
        }

        guard let collectionEntry = entries.first(where: { $0.path == collectionName }) else {
            throw AnkiError.invalidPackage("missing collection")
        }
        let collectionData = try ZipArchive.extract(collectionEntry, from: data)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("anki-import-\(UUID().uuidString).sqlite")
        try collectionData.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let db = try SQLiteDatabase(path: temp.path, readOnly: true)
        let notes = try readNotes(db)

        // Media
        var mediaFiles: [String] = []
        if let mediaEntry = entries.first(where: { $0.path == "media" }),
           let mediaData = try? ZipArchive.extract(mediaEntry, from: data),
           let map = (try? JSONSerialization.jsonObject(with: mediaData)) as? [String: String], !map.isEmpty {
            try FileManager.default.createDirectory(at: mediaDestination, withIntermediateDirectories: true)
            let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            for (index, name) in map {
                guard let entry = byPath[index] else { continue }
                let safeName = (name as NSString).lastPathComponent
                guard !safeName.isEmpty, safeName != "." , safeName != ".." else { continue }
                let fileData = try ZipArchive.extract(entry, from: data)
                try fileData.write(to: mediaDestination.appendingPathComponent(safeName), options: .atomic)
                mediaFiles.append(safeName)
            }
        }

        let deckNames = Array(Set(notes.map { $0.deckPath.joined(separator: "::") })).sorted()
        return AnkiImportResult(notes: notes, deckNames: deckNames, mediaFiles: mediaFiles.sorted())
    }

    // MARK: Collection parsing

    func readNotes(_ db: SQLiteDatabase) throws -> [ImportedAnkiNote] {
        guard let col = try db.query("SELECT crt, models, decks FROM col LIMIT 1").first else {
            throw AnkiError.invalidPackage("empty collection")
        }
        let creation = col["crt"]?.int64 ?? 0
        let decks = try deckNames(db, colJSON: col["decks"]?.string)
        let models = try noteTypes(db, colJSON: col["models"]?.string)

        let rows = try db.query("""
            SELECT n.guid, n.mid, n.tags, n.flds, c.did, c.type, c.queue, c.due, c.ivl, c.factor, c.reps, c.lapses
            FROM notes n JOIN cards c ON c.id = (SELECT MIN(id) FROM cards WHERE nid = n.id)
            ORDER BY c.did, c.due, n.id
            """)

        return rows.map { row -> ImportedAnkiNote in
            let modelID = row["mid"]?.int64 ?? 0
            let model = models[modelID] ?? (name: "Unknown", fields: [])
            let values = (row["flds"]?.string ?? "").components(separatedBy: "\u{1f}")
            let fieldNames = model.fields.count == values.count ? model.fields
                : (0..<values.count).map { $0 < model.fields.count ? model.fields[$0] : "Field \($0 + 1)" }
            let deckName = decks[row["did"]?.int64 ?? 1] ?? "Imported"
            let tags = (row["tags"]?.string ?? "").split(separator: " ").map(String.init)
            let queue = row["queue"]?.int64 ?? 0
            return ImportedAnkiNote(
                guid: row["guid"]?.string ?? UUID().uuidString,
                noteTypeName: model.name,
                fieldNames: fieldNames,
                fieldValues: values,
                tags: tags,
                deckPath: deckName.components(separatedBy: "::"),
                scheduling: scheduling(from: row, collectionCreation: creation),
                isSuspended: queue == -1
            )
        }
    }

    private func deckNames(_ db: SQLiteDatabase, colJSON: String?) throws -> [Int64: String] {
        var result: [Int64: String] = [:]
        if let json = colJSON, let data = json.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]], !object.isEmpty {
            for (key, deck) in object {
                if let id = Int64(key), let name = deck["name"] as? String { result[id] = name }
            }
        } else if db.tableExists("decks") {
            for row in try db.query("SELECT id, name FROM decks") {
                if let id = row["id"]?.int64, let name = row["name"]?.string {
                    result[id] = name.replacingOccurrences(of: "\u{1f}", with: "::")
                }
            }
        }
        return result
    }

    private func noteTypes(_ db: SQLiteDatabase, colJSON: String?) throws -> [Int64: (name: String, fields: [String])] {
        var result: [Int64: (name: String, fields: [String])] = [:]
        if let json = colJSON, let data = json.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]], !object.isEmpty {
            for (key, model) in object {
                guard let id = Int64(key) else { continue }
                let fields = (model["flds"] as? [[String: Any]] ?? [])
                    .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                    .compactMap { $0["name"] as? String }
                result[id] = (model["name"] as? String ?? "Note", fields)
            }
        } else if db.tableExists("notetypes") {
            var fieldsByType: [Int64: [(Int64, String)]] = [:]
            if db.tableExists("fields") {
                for row in try db.query("SELECT ntid, ord, name FROM fields") {
                    guard let ntid = row["ntid"]?.int64 else { continue }
                    fieldsByType[ntid, default: []].append((row["ord"]?.int64 ?? 0, row["name"]?.string ?? ""))
                }
            }
            for row in try db.query("SELECT id, name FROM notetypes") {
                guard let id = row["id"]?.int64 else { continue }
                let fields = (fieldsByType[id] ?? []).sorted { $0.0 < $1.0 }.map(\.1)
                result[id] = (row["name"]?.string ?? "Note", fields)
            }
        }
        return result
    }

    private func scheduling(from row: [String: SQLiteValue], collectionCreation: Int64) -> SchedulingState? {
        let type = row["type"]?.int64 ?? 0
        let due = row["due"]?.int64 ?? 0
        let ivl = Double(row["ivl"]?.int64 ?? 0)
        let factor = Double(row["factor"]?.int64 ?? 0)
        let ease = factor > 0 ? factor / 1000 : 2.5
        let reps = Int(row["reps"]?.int64 ?? 0)
        let lapses = Int(row["lapses"]?.int64 ?? 0)
        switch type {
        case 2:
            let dueDate = Date(timeIntervalSince1970: TimeInterval(collectionCreation + due * 86_400))
            return SchedulingState(phase: .review, due: dueDate,
                                   lastReview: dueDate.addingTimeInterval(-max(ivl, 1) * 86_400),
                                   intervalDays: max(ivl, 1), easeFactor: ease, repetitions: reps, lapses: lapses)
        case 1, 3:
            let dueDate = Date(timeIntervalSince1970: TimeInterval(due))
            return SchedulingState(phase: type == 1 ? .learning : .relearning, due: dueDate,
                                   lastReview: dueDate.addingTimeInterval(-600), intervalDays: 0,
                                   easeFactor: ease, repetitions: reps, lapses: lapses)
        default:
            return nil
        }
    }
}
