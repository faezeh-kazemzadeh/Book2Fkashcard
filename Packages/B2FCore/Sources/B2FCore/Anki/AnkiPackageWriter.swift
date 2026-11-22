import Foundation

/// Writes Anki `.apkg` packages (collection schema 11, `collection.anki2`),
/// the format every Anki client imports: Anki desktop 2.1+, AnkiMobile, AnkiDroid.
///
/// Package layout:
/// ```
/// collection.anki2   SQLite collection (col, notes, cards, revlog, graves)
/// media              JSON map {"0": "word.m4a", ...}
/// 0, 1, ...          media files, renamed to their index
/// ```
/// Note GUIDs are derived from the app's card UUIDs, so re-exporting an updated
/// lesson updates existing notes in Anki instead of duplicating them.
public struct AnkiPackageWriter {

    /// Stable model IDs so repeated imports reuse the same note types.
    static let vocabularyModelID: Int64 = 1_715_000_000_101
    static let basicModelID: Int64 = 1_715_000_000_102

    public init() {}

    public func write(_ request: AnkiExportRequest, to destination: URL, now: Date = Date()) throws -> AnkiExportResult {
        guard !request.cards.isEmpty else { throw AnkiError.emptyExport }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anki-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let collectionURL = workDirectory.appendingPathComponent("collection.anki2")
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let nowS = Int64(now.timeIntervalSince1970)
        let creation = Int64(Calendar(identifier: .gregorian).startOfDay(for: now).timeIntervalSince1970)

        // Decks (including every ancestor so the hierarchy is explicit).
        var deckIDs: [String: Int64] = [:]
        var nextDeckID = nowMs
        for card in request.cards {
            let components = card.deckPath.map(sanitizeDeckComponent).filter { !$0.isEmpty }
            for depth in 1...max(components.count, 1) {
                let name = components.isEmpty ? "Book2Flashcards" : components.prefix(depth).joined(separator: "::")
                if deckIDs[name] == nil {
                    deckIDs[name] = nextDeckID
                    nextDeckID += 1
                }
            }
        }

        // Media.
        var mediaMap: [String: String] = [:]
        var mediaEntries: [ZipArchive.Entry] = []
        var missingMedia: [String] = []
        if request.includeMedia, let directory = request.mediaDirectory {
            let referenced = Set(request.cards.flatMap { [$0.audioFileName, $0.exampleAudioFileName, $0.imageFileName].compactMap { $0 } })
            for (index, name) in referenced.sorted().enumerated() {
                let url = directory.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url) {
                    mediaMap[String(index)] = name
                    mediaEntries.append(ZipArchive.Entry(path: String(index), data: data))
                } else {
                    missingMedia.append(name)
                }
            }
        }
        let availableMedia = Set(mediaMap.values)

        let db = try SQLiteDatabase(path: collectionURL.path)
        try db.execute(Self.schema)
        try db.transaction {
            try db.run("""
                INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags)
                VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')
                """, [.integer(creation), .integer(nowMs), .integer(nowMs),
                      .text(collectionConfig(nowMs: nowMs)),
                      .text(modelsJSON(nowS: nowS, defaultDeckID: deckIDs.values.min() ?? 1)),
                      .text(decksJSON(deckIDs, nowS: nowS)),
                      .text(Self.deckConfigJSON)])

            var noteID = nowMs
            var cardID = nowMs
            for (position, card) in request.cards.enumerated() {
                noteID += 1
                cardID += 1
                let components = card.deckPath.map(sanitizeDeckComponent).filter { !$0.isEmpty }
                let deckName = components.isEmpty ? "Book2Flashcards" : components.joined(separator: "::")
                let deckID = deckIDs[deckName] ?? 1
                let (modelID, fields) = noteFields(for: card, availableMedia: availableMedia)
                let sortField = TextNormalizer.stripHTML(fields[0])
                let checksum = Int64(SHA1.hexDigest(sortField).prefix(8), radix: 16) ?? 0
                let tags = card.tags.map(sanitizeTag).filter { !$0.isEmpty }
                let tagString = tags.isEmpty ? "" : " " + tags.joined(separator: " ") + " "

                try db.run("""
                    INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
                    VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')
                    """, [.integer(noteID), .text(Self.guid(for: card.id)), .integer(modelID), .integer(nowS),
                          .text(tagString), .text(fields.joined(separator: "\u{1f}")), .text(sortField),
                          .integer(checksum)])

                let sched = cardScheduling(card.scheduling, include: request.includeScheduling,
                                           position: position, collectionCreation: creation)
                try db.run("""
                    INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses,
                                       left, odue, odid, flags, data)
                    VALUES (?, ?, ?, 0, ?, -1, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, '')
                    """, [.integer(cardID), .integer(noteID), .integer(deckID), .integer(nowS),
                          .integer(sched.type), .integer(sched.queue), .integer(sched.due), .integer(sched.ivl),
                          .integer(sched.factor), .integer(sched.reps), .integer(sched.lapses)])
            }
        }

        let mediaJSON = (try? JSONSerialization.data(withJSONObject: mediaMap, options: [.sortedKeys])) ?? Data("{}".utf8)
        let collectionData = try Data(contentsOf: collectionURL)
        let archive = ZipArchive.create(entries: [
            ZipArchive.Entry(path: "collection.anki2", data: collectionData),
            ZipArchive.Entry(path: "media", data: mediaJSON)
        ] + mediaEntries)
        try archive.write(to: destination, options: .atomic)

        return AnkiExportResult(fileURL: destination, noteCount: request.cards.count, deckCount: deckIDs.count,
                                mediaCount: mediaEntries.count, missingMedia: missingMedia)
    }

    // MARK: Fields

    func noteFields(for card: AnkiExportRequest.Card, availableMedia: Set<String>) -> (Int64, [String]) {
        let e = TextNormalizer.escapeHTML
        func sound(_ name: String?) -> String {
            guard let name, availableMedia.contains(name) else { return "" }
            return "[sound:\(name)]"
        }
        func image(_ name: String?) -> String {
            guard let name, availableMedia.contains(name) else { return "" }
            return "<img src=\"\(e(name))\">"
        }
        let id = card.id.uuidString
        switch card.content {
        case .vocabulary(let v):
            return (Self.vocabularyModelID, [
                e(v.term), e(v.translation), e(v.definition), e(v.ipa.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                e(v.pronunciation), e(v.partOfSpeech), e(v.example), e(v.exampleTranslation),
                e(v.synonyms.joined(separator: ", ")), e(v.antonyms.joined(separator: ", ")),
                sound(card.audioFileName), sound(card.exampleAudioFileName), image(card.imageFileName), id
            ])
        case .grammar(let g):
            var back = "<div>\(e(g.explanation))</div>"
            if !g.formula.isEmpty { back += "<div class=\"formula\">\(e(g.formula))</div>" }
            if !g.examples.isEmpty { back += "<ul>" + g.examples.map { "<li>\(e($0))</li>" }.joined() + "</ul>" }
            let mistakes = g.commonMistakes.isEmpty ? "" :
                "<b>Common mistakes</b><ul>" + g.commonMistakes.map { "<li>✗ \(e($0))</li>" }.joined() + "</ul>"
            return (Self.basicModelID, [e(g.rule), back, mistakes, "grammar", sound(card.audioFileName), image(card.imageFileName), id])
        case .reading(let r):
            let front = r.passageExcerpt.isEmpty ? e(r.question)
                : "<div class=\"muted\">\(e(r.passageExcerpt))</div><div>\(e(r.question))</div>"
            return (Self.basicModelID, [front, e(r.answer), e(r.explanation), "reading", sound(card.audioFileName), image(card.imageFileName), id])
        case .speaking(let s):
            let phrases = s.usefulPhrases.isEmpty ? "" :
                "<b>Useful phrases</b><ul>" + s.usefulPhrases.map { "<li>\(e($0))</li>" }.joined() + "</ul>"
            return (Self.basicModelID, [e(s.prompt), e(s.sampleAnswer), phrases, "speaking", sound(card.audioFileName), image(card.imageFileName), id])
        case .basic(let b):
            // Imported Anki content is already HTML; keep it as-is.
            return (Self.basicModelID, [b.front, b.back, b.extra, "basic", sound(card.audioFileName), image(card.imageFileName), id])
        }
    }

    // MARK: Scheduling

    struct CardScheduling { var type: Int64, queue: Int64, due: Int64, ivl: Int64, factor: Int64, reps: Int64, lapses: Int64 }

    func cardScheduling(_ state: SchedulingState?, include: Bool, position: Int, collectionCreation: Int64) -> CardScheduling {
        guard include, let state, state.phase != .new else {
            return CardScheduling(type: 0, queue: 0, due: Int64(position + 1), ivl: 0, factor: 0, reps: 0, lapses: 0)
        }
        let factor = Int64((state.easeFactor * 1000).rounded())
        switch state.phase {
        case .review:
            let dayIndex = Int64((state.due.timeIntervalSince1970 - Double(collectionCreation)) / 86_400)
            return CardScheduling(type: 2, queue: 2, due: max(0, dayIndex), ivl: Int64(max(1, state.intervalDays.rounded())),
                                  factor: factor, reps: Int64(state.repetitions), lapses: Int64(state.lapses))
        case .learning, .relearning:
            return CardScheduling(type: state.phase == .learning ? 1 : 3, queue: 1,
                                  due: Int64(state.due.timeIntervalSince1970), ivl: 0, factor: factor,
                                  reps: Int64(state.repetitions), lapses: Int64(state.lapses))
        case .new:
            return CardScheduling(type: 0, queue: 0, due: Int64(position + 1), ivl: 0, factor: 0, reps: 0, lapses: 0)
        }
    }

    // MARK: JSON blobs

    func collectionConfig(nowMs: Int64) -> String {
        let config: [String: Any] = [
            "nextPos": 1, "estTimes": true, "activeDecks": [1], "sortType": "noteFld", "timeLim": 0,
            "sortBackwards": false, "addToCur": true, "curDeck": 1, "newBury": true, "newSpread": 0,
            "dueCounts": true, "curModel": String(Self.vocabularyModelID), "collapseTime": 1200
        ]
        return jsonString(config)
    }

    func modelsJSON(nowS: Int64, defaultDeckID: Int64) -> String {
        func model(id: Int64, name: String, fields: [String], qfmt: String, afmt: String) -> [String: Any] {
            [
                "id": id, "name": name, "type": 0, "mod": nowS, "usn": -1, "sortf": 0, "did": defaultDeckID,
                "tmpls": [[
                    "name": "Card 1", "ord": 0, "qfmt": qfmt, "afmt": afmt, "did": NSNull(),
                    "bqfmt": "", "bafmt": ""
                ] as [String: Any]],
                "flds": fields.enumerated().map { index, field -> [String: Any] in
                    ["name": field, "ord": index, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": [String]()]
                },
                "css": AnkiNoteTypes.css,
                "latexPre": "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
                "latexPost": "\\end{document}",
                "latexsvg": false,
                "tags": [String](), "vers": [Int](),
                "req": [[0, "any", [0]] as [Any]]
            ]
        }
        let models: [String: Any] = [
            String(Self.vocabularyModelID): model(id: Self.vocabularyModelID, name: AnkiNoteTypes.vocabularyName,
                                                  fields: AnkiNoteTypes.vocabularyFields,
                                                  qfmt: AnkiNoteTypes.vocabularyFront, afmt: AnkiNoteTypes.vocabularyBack),
            String(Self.basicModelID): model(id: Self.basicModelID, name: AnkiNoteTypes.basicName,
                                             fields: AnkiNoteTypes.basicFields,
                                             qfmt: AnkiNoteTypes.basicFront, afmt: AnkiNoteTypes.basicBack)
        ]
        return jsonString(models)
    }

    func decksJSON(_ ids: [String: Int64], nowS: Int64) -> String {
        func deck(id: Int64, name: String) -> [String: Any] {
            [
                "id": id, "name": name, "mod": nowS, "usn": -1, "lrnToday": [0, 0], "revToday": [0, 0],
                "newToday": [0, 0], "timeToday": [0, 0], "collapsed": false, "browserCollapsed": false,
                "desc": "", "dyn": 0, "conf": 1, "extendNew": 0, "extendRev": 0
            ]
        }
        var decks: [String: Any] = ["1": deck(id: 1, name: "Default")]
        for (name, id) in ids { decks[String(id)] = deck(id: id, name: name) }
        return jsonString(decks)
    }

    static let deckConfigJSON = """
    {"1":{"id":1,"name":"Default","mod":0,"usn":0,"maxTaken":60,"autoplay":true,"timer":0,"replayq":true,"dyn":false,\
    "new":{"delays":[1,10],"ints":[1,4,7],"initialFactor":2500,"order":1,"perDay":20,"bury":false,"separate":true},\
    "rev":{"perDay":200,"ease4":1.3,"ivlFct":1,"maxIvl":36500,"bury":false,"hardFactor":1.2,"fuzz":0.05,"minSpace":1},\
    "lapse":{"delays":[10],"mult":0,"minInt":1,"leechFails":8,"leechAction":1}}}
    """

    static let schema = """
    CREATE TABLE IF NOT EXISTS col (id integer primary key, crt integer not null, mod integer not null,
        scm integer not null, ver integer not null, dty integer not null, usn integer not null, ls integer not null,
        conf text not null, models text not null, decks text not null, dconf text not null, tags text not null);
    CREATE TABLE IF NOT EXISTS notes (id integer primary key, guid text not null, mid integer not null,
        mod integer not null, usn integer not null, tags text not null, flds text not null, sfld integer not null,
        csum integer not null, flags integer not null, data text not null);
    CREATE TABLE IF NOT EXISTS cards (id integer primary key, nid integer not null, did integer not null,
        ord integer not null, mod integer not null, usn integer not null, type integer not null,
        queue integer not null, due integer not null, ivl integer not null, factor integer not null,
        reps integer not null, lapses integer not null, left integer not null, odue integer not null,
        odid integer not null, flags integer not null, data text not null);
    CREATE TABLE IF NOT EXISTS revlog (id integer primary key, cid integer not null, usn integer not null,
        ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null,
        time integer not null, type integer not null);
    CREATE TABLE IF NOT EXISTS graves (usn integer not null, oid integer not null, type integer not null);
    CREATE INDEX IF NOT EXISTS ix_notes_usn ON notes (usn);
    CREATE INDEX IF NOT EXISTS ix_cards_usn ON cards (usn);
    CREATE INDEX IF NOT EXISTS ix_revlog_usn ON revlog (usn);
    CREATE INDEX IF NOT EXISTS ix_cards_nid ON cards (nid);
    CREATE INDEX IF NOT EXISTS ix_cards_sched ON cards (did, queue, due);
    CREATE INDEX IF NOT EXISTS ix_revlog_cid ON revlog (cid);
    CREATE INDEX IF NOT EXISTS ix_notes_csum ON notes (csum);
    """

    // MARK: Helpers

    /// Anki GUIDs are short base91-style strings; derive deterministically from the UUID.
    static func guid(for id: UUID) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var value: UInt64 = 0
        for byte in bytes.prefix(8) { value = value << 8 | UInt64(byte) }
        var other: UInt64 = 0
        for byte in bytes.suffix(8) { other = other << 8 | UInt64(byte) }
        value ^= other
        var result = ""
        repeat {
            result.append(alphabet[Int(value % UInt64(alphabet.count))])
            value /= UInt64(alphabet.count)
        } while value > 0
        return result
    }

    func sanitizeDeckComponent(_ name: String) -> String {
        TextNormalizer.collapseWhitespace(name.replacingOccurrences(of: "::", with: " ").replacingOccurrences(of: "\"", with: "'"))
    }

    func sanitizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\u{3000}", with: "_")
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
