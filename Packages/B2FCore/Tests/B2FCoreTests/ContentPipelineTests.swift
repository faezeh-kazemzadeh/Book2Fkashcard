import XCTest
@testable import B2FCore

final class TextNormalizerTests: XCTestCase {
    func testPersianNormalisation() {
        XCTAssertEqual(TextNormalizer.persianOrthography("كتاب ي"), "کتاب ی")
        XCTAssertEqual(TextNormalizer.searchKey("می‌روم"), TextNormalizer.searchKey("میروم"))
        XCTAssertEqual(TextNormalizer.searchKey("۱۲۳"), "123")
        XCTAssertEqual(TextNormalizer.searchKey("Café  CRÈME"), "cafe creme")
    }

    func testHTMLHelpers() {
        XCTAssertEqual(TextNormalizer.stripHTML("<p>Hello&nbsp;<b>world</b></p><p>&#x41;&amp;B</p>"), "Hello world\nA&B")
        XCTAssertEqual(TextNormalizer.escapeHTML("a<b & \"c\""), "a&lt;b &amp; &quot;c&quot;")
    }

    func testEditDistance() {
        XCTAssertEqual(TextNormalizer.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(TextNormalizer.editDistance("", "abc"), 3)
    }

    func testScriptDetection() {
        XCTAssertEqual(StudyLanguage.detectScript(of: "پرنده"), .persian)
        XCTAssertEqual(StudyLanguage.detectScript(of: "مرحبا"), .arabic)
        XCTAssertEqual(StudyLanguage.detectScript(of: "hello"), .english)
        XCTAssertNil(StudyLanguage.detectScript(of: "123"))
    }
}

final class VocabularyQualityFilterTests: XCTestCase {
    let filter = VocabularyQualityFilter(configuration: .init(language: .english))

    func testRejectsLowValueWords() {
        XCTAssertEqual(filter.rejectionReason(for: "the"), .stopWord)
        XCTAssertEqual(filter.rejectionReason(for: "An"), .stopWord)
        XCTAssertEqual(filter.rejectionReason(for: "house"), .veryCommon)
        XCTAssertEqual(filter.rejectionReason(for: "2024"), .numeric)
        XCTAssertEqual(filter.rejectionReason(for: "w0rd"), .noise)
        XCTAssertEqual(filter.rejectionReason(for: "London", isSentenceInitial: false), .properNoun)
        XCTAssertNil(filter.rejectionReason(for: "sustainable"))
        XCTAssertNil(filter.rejectionReason(for: "give up"))
    }

    func testLemmatisationForDuplicates() {
        XCTAssertEqual(filter.lemma("studies"), "study")
        XCTAssertEqual(filter.lemma("stopped"), "stop")
        XCTAssertEqual(filter.lemma("analyses"), "analys")
        XCTAssertEqual(filter.lemma("process"), "process")
        XCTAssertEqual(filter.lemma("watches"), "watch")
    }

    func testCandidatesPrioritiseCuratedAndAcademicWords() {
        let text = """
        The research shows that sustainable energy is important. Researchers analyse the data.
        Sustainable cities need sustainable transport. The cat sat on the mat.
        """
        let candidates = filter.candidates(fromText: text, vocabularyRows: [["commute", "رفت و آمد"]])
        let terms = candidates.map(\.term)
        XCTAssertEqual(terms.first, "commute")
        XCTAssertEqual(candidates.first?.inlineTranslation, "رفت و آمد")
        XCTAssertTrue(terms.contains("sustainable"))
        XCTAssertFalse(terms.contains("the"))
        XCTAssertFalse(terms.contains("cat"))
        let research = candidates.first { $0.term == "research" }
        let sustainable = candidates.first { $0.term == "sustainable" }
        XCTAssertNotNil(research)
        XCTAssertGreaterThan(sustainable!.occurrences, 1)
    }

    func testFilterDraftsRemovesDuplicatesAndEmptyAnswers() {
        let drafts = [
            FlashcardDraft(content: .vocabulary(VocabularyContent(term: "commute", translation: "رفت و آمد"))),
            FlashcardDraft(content: .vocabulary(VocabularyContent(term: "commutes", translation: "رفت و آمدها"))),
            FlashcardDraft(content: .vocabulary(VocabularyContent(term: "the", translation: "-"))),
            FlashcardDraft(content: .vocabulary(VocabularyContent(term: "resilient"))),
            FlashcardDraft(content: .vocabulary(VocabularyContent(term: "abandon", translation: "رها کردن"))),
        ]
        let result = filter.filterDrafts(drafts, existingKeys: [CardContent.vocabulary(VocabularyContent(term: "abandon")).deduplicationKey])
        XCTAssertEqual(result.map(\.content.frontText), ["commute"])
    }
}

final class LayoutAndLessonDetectionTests: XCTestCase {
    func observation(_ text: String, y: Double, x: Double = 0.1, height: Double = 0.015, confidence: Double = 0.95) -> OCRTextObservation {
        OCRTextObservation(text: text, boundingBox: NormalizedRect(x: x, y: y, width: 0.3, height: height), confidence: confidence)
    }

    func testDetectsHeadingsTablesAndVocabularyLists() {
        let analyzer = LayoutAnalyzer()
        var obs: [OCRTextObservation] = [observation("Unit 1 Food and you", y: 0.02, height: 0.04)]
        // Vocabulary table: two aligned columns over three rows.
        for (i, pair) in [("abandon", "رها کردن"), ("commute", "رفت و آمد"), ("resilient", "مقاوم")].enumerated() {
            obs.append(observation(pair.0, y: 0.1 + Double(i) * 0.03, x: 0.1))
            obs.append(observation(pair.1, y: 0.1 + Double(i) * 0.03, x: 0.6))
        }
        obs.append(observation("Grammar: present simple", y: 0.3))
        obs.append(observation("We use it for habits.", y: 0.32))
        obs.append(observation("1. Complete the sentences.", y: 0.5))
        obs.append(observation("2. Match the words.", y: 0.52))
        obs.append(observation("blurry", y: 0.7, confidence: 0.2))

        let page = analyzer.analyze(pageIndex: 0, observations: obs)
        let kinds = page.blocks.map(\.kind)
        XCTAssertEqual(kinds.first, .lessonTitle)
        XCTAssertTrue(kinds.contains(.vocabularyList))
        XCTAssertTrue(kinds.contains(.grammarBox))
        XCTAssertTrue(kinds.contains(.exercise))
        let vocab = page.blocks.first { $0.kind == .vocabularyList }!
        XCTAssertEqual(vocab.rows.first, ["abandon", "رها کردن"])
        XCTAssertFalse(page.lowConfidenceBlockIDs.isEmpty)
    }

    func testSplitVocabularyPair() {
        XCTAssertEqual(LayoutAnalyzer.splitVocabularyPair("abandon – to leave behind"), ["abandon", "to leave behind"])
        XCTAssertNil(LayoutAnalyzer.splitVocabularyPair("A sentence without a separator."))
    }

    func testOutlineFromPlainText() {
        let analyzer = LayoutAnalyzer()
        let page1 = analyzer.analyze(pageIndex: 0, plainText: """
        Unit 1
        Lesson 1A Mood food
        Vocabulary
        abandon - رها کردن
        commute - رفت و آمد
        resilient - مقاوم
        Grammar
        Present simple vs continuous. We use the present simple for habits.
        """)
        let page2 = analyzer.analyze(pageIndex: 1, plainText: """
        Lesson 1B Family life
        Reading
        Tom lives with his grandparents in a small village near the coast.
        Unit 2
        Lesson 2A Spend or save?
        Vocabulary
        budget - بودجه
        loan - وام
        income - درآمد
        """)
        let outline = LessonStructureDetector().detect(pages: [page1, page2])
        XCTAssertEqual(outline.units.count, 2)
        XCTAssertEqual(outline.units[0].lessons.map(\.title), ["Lesson 1A – Mood food", "Lesson 1B – Family life"])
        XCTAssertEqual(outline.units[1].lessons.first?.title, "Lesson 2A – Spend or save?")
        let lesson1A = outline.units[0].lessons[0]
        XCTAssertEqual(lesson1A.sections.map(\.kind), [.vocabulary, .grammar])
        XCTAssertTrue(outline.units[0].lessons[1].sections.contains { $0.kind == .reading })
        XCTAssertEqual(outline.units[0].lessons[1].pageRange, 1...1)
    }

    func testFallbackWithoutLessonHeadings() {
        let analyzer = LayoutAnalyzer()
        let pages = (0..<6).map { analyzer.analyze(pageIndex: $0, plainText: "Some text on page \($0). It talks about climate.") }
        let outline = LessonStructureDetector().detect(pages: pages)
        XCTAssertEqual(outline.lessonCount, 2)
        XCTAssertEqual(outline.units.first?.lessons.first?.pageRange, 0...3)
    }

    func testOCRLanguagePlanForPersian() {
        let plan = OCRLanguagePlan(languages: [.persian, .english], supportedByDevice: ["en-US", "ar-SA", "fr-FR"])
        XCTAssertEqual(plan.recognitionLanguages, ["en-US", "ar-SA"])
        XCTAssertTrue(plan.normalizeToPersian)
        XCTAssertEqual(plan.postProcess("كتاب"), "کتاب")
        XCTAssertEqual(plan.adjustedConfidence(1.0, text: "کتاب"), 0.85)
        XCTAssertEqual(plan.adjustedConfidence(1.0, text: "book"), 1.0)
        XCTAssertTrue(plan.unsupported.isEmpty)
    }
}

final class FeatureGateTests: XCTestCase {
    func testFreeLimits() {
        let gate = FeatureGate(tier: .free)
        XCTAssertEqual(gate.canAddBook(currentBookCount: 2), .allowed)
        XCTAssertEqual(gate.canAddBook(currentBookCount: 3), .requiresPremium(.unlimitedBooks))
        XCTAssertEqual(gate.canAddCards(currentCardCount: 480, adding: 50), .partiallyAllowed(remaining: 20))
        XCTAssertEqual(gate.canAddCards(currentCardCount: 500, adding: 1), .requiresPremium(.unlimitedCards))
        XCTAssertEqual(gate.check(.ankiExport), .requiresPremium(.ankiExport))
        XCTAssertEqual(gate.ocrMode, .basic)
    }

    func testPremiumIsUnlimited() {
        let gate = FeatureGate(tier: .premium)
        XCTAssertEqual(gate.canAddBook(currentBookCount: 1_000), .allowed)
        XCTAssertEqual(gate.canAddCards(currentCardCount: 100_000, adding: 500), .allowed)
        XCTAssertEqual(gate.check(.cloudSync), .allowed)
        XCTAssertEqual(gate.ocrMode, .advanced)
    }
}

final class DocumentExtractorTests: XCTestCase {
    func testDOCXHeadingsTablesAndPageBreaks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Lesson 1A</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>abandon</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>رها کردن</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:r><w:br w:type="page"/></w:r></w:p>
        <w:p><w:r><w:t>Second page</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let docx = ZipArchive.create(entries: [.init(path: "word/document.xml", data: Data(xml.utf8))], compress: false)
        let document = try DOCXTextExtractor().extract(from: docx)
        XCTAssertEqual(document.pages.count, 2)
        XCTAssertEqual(document.pages[0].text, "Lesson 1A\nHello world\nabandon\tرها کردن")
        XCTAssertEqual(document.pages[0].headingLines, [0])
        XCTAssertEqual(document.pages[1].text, "Second page")
    }

    func testEPUBSpineOrderAndMetadata() throws {
        let container = """
        <?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        let opf = """
        <package><metadata><dc:title>Grammar in Use</dc:title><dc:creator>R. Murphy</dc:creator></metadata>
        <manifest><item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>
        """
        let ch1 = "<html><body><h1>Unit 1</h1><p>Present continuous.</p></body></html>"
        let ch2 = "<html><body><h2>Unit 2</h2><p>Present simple.</p></body></html>"
        let epub = ZipArchive.create(entries: [
            .init(path: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(path: "META-INF/container.xml", data: Data(container.utf8)),
            .init(path: "OEBPS/content.opf", data: Data(opf.utf8)),
            .init(path: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            .init(path: "OEBPS/ch2.xhtml", data: Data(ch2.utf8))
        ], compress: false)
        let document = try EPUBTextExtractor().extract(from: epub)
        XCTAssertEqual(document.title, "Grammar in Use")
        XCTAssertEqual(document.author, "R. Murphy")
        XCTAssertEqual(document.pages.map(\.text), ["Unit 1\nPresent continuous.", "Unit 2\nPresent simple."])
        XCTAssertEqual(document.pages[0].headingLines, [0])
    }

    func testPlainTextPaging() throws {
        let text = (1...130).map { "line \($0)" }.joined(separator: "\n")
        let document = try PlainTextExtractor().extract(from: Data(text.utf8))
        XCTAssertEqual(document.pages.count, 3)
        XCTAssertThrowsError(try PlainTextExtractor().extract(from: Data("   \n ".utf8)))
    }
}
