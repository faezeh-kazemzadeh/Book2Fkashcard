import XCTest
@testable import B2FCore

final class ChecksumTests: XCTestCase {
    func testSHA1KnownVectors() {
        XCTAssertEqual(SHA1.hexDigest("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hexDigest(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1.hexDigest("The quick brown fox jumps over the lazy dog"),
                       "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }
}

final class ZipArchiveTests: XCTestCase {
    func testRoundTripStoredAndCompressed() throws {
        let big = Data(String(repeating: "flashcard ", count: 2_000).utf8)
        for compress in [false, true] {
            let archive = ZipArchive.create(entries: [
                .init(path: "a.txt", data: Data("hello".utf8)),
                .init(path: "folder/b.txt", data: big),
                .init(path: "persian/درس.txt", data: Data("سلام".utf8))
            ], compress: compress)
            let files = try ZipArchive.extractAll(from: archive)
            XCTAssertEqual(files["a.txt"], Data("hello".utf8))
            XCTAssertEqual(files["folder/b.txt"], big)
            XCTAssertEqual(files["persian/درس.txt"], Data("سلام".utf8))
        }
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ZipArchive.listEntries(in: Data("not a zip".utf8)))
    }
}

final class AnkiRoundTripTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func makeRequest() throws -> AnkiExportRequest {
        let mediaDir = tempDirectory.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try Data([0, 1, 2, 3]).write(to: mediaDir.appendingPathComponent("abandon.m4a"))

        let vocabID = UUID()
        let grammarID = UUID()
        return AnkiExportRequest(cards: [
            .init(id: vocabID,
                  content: .vocabulary(VocabularyContent(term: "abandon", translation: "رها کردن",
                                                         definition: "to leave behind", ipa: "əˈbændən",
                                                         example: "They had to abandon the car.",
                                                         synonyms: ["desert", "leave"], antonyms: ["keep"])),
                  deckPath: ["English File", "Unit 1", "Lesson 1A", "Vocabulary"],
                  tags: ["B2F", "unit 1"], audioFileName: "abandon.m4a",
                  scheduling: SchedulingState(phase: .review, due: Date().addingTimeInterval(86_400 * 3),
                                              lastReview: Date(), intervalDays: 3, easeFactor: 2.5, repetitions: 2)),
            .init(id: grammarID,
                  content: .grammar(GrammarContent(rule: "Present perfect", explanation: "Past action, present result.",
                                                   formula: "have/has + past participle",
                                                   examples: ["I have lost my keys."],
                                                   commonMistakes: ["✗ I have seen him yesterday → ✓ I saw him yesterday"])),
                  deckPath: ["English File", "Unit 1", "Lesson 1A", "Grammar"])
        ], mediaDirectory: mediaDir, includeScheduling: true)
    }

    func testExportProducesValidCollection() throws {
        let output = tempDirectory.appendingPathComponent("deck.apkg")
        let result = try AnkiPackageWriter().write(try makeRequest(), to: output)
        XCTAssertEqual(result.noteCount, 2)
        XCTAssertEqual(result.mediaCount, 1)
        XCTAssertTrue(result.missingMedia.isEmpty)
        // Book, Unit, Lesson, Vocabulary, Grammar
        XCTAssertEqual(result.deckCount, 5)

        let files = try ZipArchive.extractAll(from: try Data(contentsOf: output))
        XCTAssertNotNil(files["collection.anki2"])
        XCTAssertNotNil(files["0"])
        let media = try JSONSerialization.jsonObject(with: files["media"]!) as? [String: String]
        XCTAssertEqual(media?["0"], "abandon.m4a")

        let dbURL = tempDirectory.appendingPathComponent("check.sqlite")
        try files["collection.anki2"]!.write(to: dbURL)
        let db = try SQLiteDatabase(path: dbURL.path, readOnly: true)
        let notes = try db.query("SELECT flds, tags, csum, sfld FROM notes ORDER BY id")
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes[0]["flds"]!.string!.hasPrefix("abandon\u{1f}رها کردن"))
        XCTAssertTrue(notes[0]["flds"]!.string!.contains("[sound:abandon.m4a]"))
        XCTAssertEqual(notes[0]["tags"]?.string, " B2F unit_1 ")
        let expectedChecksum = Int64(SHA1.hexDigest("abandon").prefix(8), radix: 16)
        XCTAssertEqual(notes[0]["csum"]?.int64, expectedChecksum)
        let cards = try db.query("SELECT type, queue, ivl, factor FROM cards ORDER BY id")
        XCTAssertEqual(cards[0]["type"]?.int64, 2)
        XCTAssertEqual(cards[0]["ivl"]?.int64, 3)
        XCTAssertEqual(cards[0]["factor"]?.int64, 2500)
        XCTAssertEqual(cards[1]["type"]?.int64, 0)
        let decks = try db.query("SELECT decks FROM col")[0]["decks"]!.string!
        XCTAssertTrue(decks.contains("English File::Unit 1::Lesson 1A::Vocabulary"))
    }

    func testImportRoundTripsStructuredCards() throws {
        let request = try makeRequest()
        let output = tempDirectory.appendingPathComponent("deck.apkg")
        _ = try AnkiPackageWriter().write(request, to: output)

        let importedMedia = tempDirectory.appendingPathComponent("imported-media")
        let result = try AnkiPackageReader().read(packageAt: output, mediaDestination: importedMedia)
        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(result.mediaFiles, ["abandon.m4a"])
        XCTAssertTrue(result.deckNames.contains("English File::Unit 1::Lesson 1A::Vocabulary"))

        let mapper = AnkiNoteMapper()
        let drafts = result.notes.map(mapper.draft)
        let vocab = try XCTUnwrap(drafts.first { $0.kind == .vocabulary })
        guard case .vocabulary(let v) = vocab.content else { return XCTFail("expected vocabulary") }
        XCTAssertEqual(v.term, "abandon")
        XCTAssertEqual(v.translation, "رها کردن")
        XCTAssertEqual(v.synonyms, ["desert", "leave"])
        XCTAssertEqual(vocab.id, request.cards[0].id, "B2FID must round-trip so re-imports update")
        XCTAssertEqual(vocab.audioFileName, "abandon.m4a")
        XCTAssertEqual(vocab.scheduling?.phase, .review)

        let grammar = try XCTUnwrap(drafts.first { $0.kind == .grammar })
        guard case .grammar(let g) = grammar.content else { return XCTFail("expected grammar") }
        XCTAssertEqual(g.rule, "Present perfect")
    }

    func testGuidIsStablePerCard() {
        let id = UUID()
        XCTAssertEqual(AnkiPackageWriter.guid(for: id), AnkiPackageWriter.guid(for: id))
        XCTAssertNotEqual(AnkiPackageWriter.guid(for: id), AnkiPackageWriter.guid(for: UUID()))
    }

    func testEmptyExportThrows() {
        XCTAssertThrowsError(try AnkiPackageWriter().write(AnkiExportRequest(cards: []),
                                                           to: tempDirectory.appendingPathComponent("x.apkg")))
    }

    func testNewestFormatIsReportedClearly() throws {
        let url = tempDirectory.appendingPathComponent("new.apkg")
        try ZipArchive.create(entries: [.init(path: "collection.anki21b", data: Data([1, 2, 3])),
                                        .init(path: "collection.anki2", data: Data([1]))]).write(to: url)
        XCTAssertThrowsError(try AnkiPackageReader().read(packageAt: url, mediaDestination: tempDirectory)) { error in
            XCTAssertEqual(error as? AnkiError, .unsupportedCollectionFormat)
        }
    }

    func testGenericAndClozeNotesMapToBasic() {
        let mapper = AnkiNoteMapper()
        let cloze = ImportedAnkiNote(guid: "g", noteTypeName: "Cloze", fieldNames: ["Text", "Extra"],
                                     fieldValues: ["The {{c1::capital}} of France is Paris.", ""],
                                     tags: [], deckPath: ["French"], scheduling: nil, isSuspended: false)
        guard case .basic(let b) = mapper.draft(from: cloze).content else { return XCTFail() }
        XCTAssertEqual(b.front, "The […] of France is Paris.")
        XCTAssertEqual(b.back, "The capital of France is Paris.")

        let basic = ImportedAnkiNote(guid: "h", noteTypeName: "Basic", fieldNames: ["Front", "Back"],
                                     fieldValues: ["<b>Haus</b> [sound:haus.mp3]", "house<br><img src=\"haus.jpg\">"],
                                     tags: ["german"], deckPath: ["German"], scheduling: nil, isSuspended: false)
        let draft = mapper.draft(from: basic)
        guard case .basic(let c) = draft.content else { return XCTFail() }
        XCTAssertEqual(c.front, "Haus")
        XCTAssertEqual(c.back, "house")
        XCTAssertEqual(draft.audioFileName, "haus.mp3")
        XCTAssertEqual(draft.imageFileName, "haus.jpg")
    }
}

final class AnkiTextImporterTests: XCTestCase {
    func testAnkiHeaderedExport() throws {
        let text = [
            "#separator:tab",
            "#html:true",
            "#deck column:3",
            "#tags column:4",
            "abandon\tرها کردن\tEnglish::Unit 1\tverb b1",
            "\"multi\tline\"\t\"he said \"\"hi\"\"\"\tEnglish::Unit 1\t"
        ].joined(separator: "\n")
        let notes = try AnkiTextImporter().parse(text)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].fieldValues, ["abandon", "رها کردن"])
        XCTAssertEqual(notes[0].deckPath, ["English", "Unit 1"])
        XCTAssertEqual(notes[0].tags, ["verb", "b1"])
        XCTAssertEqual(notes[1].fieldValues[0], "multi\tline")
        XCTAssertEqual(notes[1].fieldValues[1], "he said \"hi\"")
    }

    func testCSVWithHeaderRowAndDetectedDelimiter() throws {
        let text = "front;back;tags\nHund;dog;animals\nKatze;cat;animals\n"
        let notes = try AnkiTextImporter().parse(text, options: .init(defaultDeck: "German"))
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[1].field("front"), "Katze")
        XCTAssertEqual(notes[1].tags, ["animals"])
        XCTAssertEqual(notes[1].deckPath, ["German"])
    }

    func testEmptyFileThrows() {
        XCTAssertThrowsError(try AnkiTextImporter().parse("\n\n"))
    }
}
