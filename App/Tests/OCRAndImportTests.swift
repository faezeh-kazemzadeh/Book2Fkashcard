import XCTest
import UIKit
import PDFKit
import B2FCore
@testable import Book2Flashcards

/// OCR tests run real Vision recognition on images rendered at test time,
/// so no binary fixtures are needed and results are deterministic per OS.
final class OCRTests: XCTestCase {

    /// Renders lines of text like a textbook page (headline + body + vocabulary list).
    func renderPage(_ lines: [(String, CGFloat)], size: CGSize = CGSize(width: 1240, height: 1754), rotate: Bool = false) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 120
            for (text, fontSize) in lines {
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.black]
                (text as NSString).draw(at: CGPoint(x: 100, y: y), withAttributes: attributes)
                y += fontSize * 1.8
            }
        }
        return image.cgImage!
    }

    func testRecognisesEnglishPageAndStructure() async throws {
        let page = renderPage([
            ("Lesson 1A Mood food", 64),
            ("Vocabulary", 44),
            ("resilient - able to recover quickly", 32),
            ("nutritious - good for your health", 32),
            ("commute - journey to work", 32),
            ("Grammar: present simple and continuous", 32),
            ("We use the present simple for habits.", 32)
        ])
        let result = try await OCREngine().recognize(image: page, pageIndex: 0, languages: [.english], mode: .basic)
        let text = result.plainText.lowercased()
        let layout = result.analyzed.blocks.map { "\($0.kind.rawValue): \($0.lines)" }.joined(separator: " | ")
        let raw = result.observations.map { "\($0.text) @\(String(format: "%.3f,%.3f h%.3f", $0.boundingBox.x, $0.boundingBox.y, $0.boundingBox.height))" }
            .joined(separator: " | ")
        // Single line: CI log formatters keep only the first line of a failure message.
        let diagnostics = "Blocks: \(layout) || Observations: \(raw)"
        XCTAssertTrue(text.contains("resilient"), diagnostics)
        XCTAssertTrue(text.contains("nutritious"), diagnostics)
        XCTAssertGreaterThan(result.analyzed.averageConfidence, 0.5, diagnostics)
        XCTAssertEqual(result.analyzed.blocks.first?.kind, .lessonTitle, diagnostics)
        XCTAssertTrue(result.analyzed.blocks.contains { $0.kind == .vocabularyList }, diagnostics)
        XCTAssertNotNil(result.preprocessedJPEG)
    }

    func testAdvancedPreprocessingRunsAllSteps() {
        let page = renderPage([("The quick brown fox jumps over the lazy dog.", 40)])
        let result = ImagePreprocessor().process(page, options: .advanced)
        XCTAssertTrue(result.appliedSteps.contains("shadows"))
        XCTAssertTrue(result.appliedSteps.contains("contrast"))
        XCTAssertGreaterThan(result.image.width, 0)
    }

    func testRotatedPageIsCorrected() async throws {
        let upright = renderPage((0..<12).map { ("Sustainable development requires careful planning \($0).", 34) })
        let rotated = UIImage(cgImage: upright, scale: 1, orientation: .right)
        // Bake the rotation into pixels.
        let baked = UIGraphicsImageRenderer(size: rotated.size).image { _ in rotated.draw(at: .zero) }.cgImage!
        let result = try await OCREngine().recognize(image: baked, pageIndex: 0, languages: [.english], mode: .basic)
        XCTAssertTrue(result.plainText.lowercased().contains("sustainable"), result.plainText)
    }

    func testLanguagePlanUsesDeviceSupport() {
        let supported = VisionTextBackend.supportedLanguages()
        XCTAssertTrue(supported.contains("en-US"))
        let plan = OCRLanguagePlan(languages: [.english, .german, .french, .spanish], supportedByDevice: supported)
        XCTAssertEqual(plan.recognitionLanguages.first, "en-US")
        XCTAssertTrue(plan.unsupported.isEmpty)
    }
}

final class ImportTests: XCTestCase {
    func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
    }

    func testTextPDFUsesTextLayer() async throws {
        let url = temporaryURL("book.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for page in 1...2 {
                context.beginPage()
                let body = "Unit \(page)\nLesson \(page)A Travel\n" + String(repeating: "Travelling broadens the mind and teaches patience. ", count: 6)
                (body as NSString).draw(in: CGRect(x: 40, y: 40, width: 530, height: 700),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        let document = try DocumentImporter().open(url: url)
        XCTAssertEqual(document.kind, .pdf)
        XCTAssertEqual(document.source.pageCount, 2)
        guard case .text(let text, _) = try await document.source.page(at: 0) else { return XCTFail("expected text layer") }
        XCTAssertTrue(text.contains("Travelling"))
        XCTAssertNotNil(document.source.thumbnail())
    }

    func testImageOnlyPDFIsTreatedAsScanned() async throws {
        let url = temporaryURL("scan.pdf")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }
        let pdf = PDFDocument()
        pdf.insert(PDFPage(image: image)!, at: 0)
        pdf.write(to: url)
        let document = try DocumentImporter().open(url: url)
        XCTAssertEqual(document.kind, .scannedPDF)
        guard case .image = try await document.source.page(at: 0) else { return XCTFail("expected image page") }
    }

    func testDOCXAndTXTImport() throws {
        let xml = #"<w:document xmlns:w="w"><w:body><w:p><w:r><w:t>Lesson 1</w:t></w:r></w:p></w:body></w:document>"#
        let docxURL = temporaryURL("notes.docx")
        try ZipArchive.create(entries: [.init(path: "word/document.xml", data: Data(xml.utf8))]).write(to: docxURL)
        XCTAssertEqual(try DocumentImporter().open(url: docxURL).kind, .docx)

        let txtURL = temporaryURL("words.txt")
        try "abandon - رها کردن".write(to: txtURL, atomically: true, encoding: .utf8)
        let txt = try DocumentImporter().open(url: txtURL)
        XCTAssertEqual(txt.kind, .txt)
        XCTAssertEqual(txt.source.pageCount, 1)
    }

    func testUnsupportedTypeThrows() throws {
        let url = temporaryURL("archive.xyz")
        try Data([1, 2, 3]).write(to: url)
        XCTAssertThrowsError(try DocumentImporter().open(url: url))
    }

    func testScanPDFBuilder() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { _ in }
        let data = ScanPDFBuilder.makePDF(from: [image, image], title: "Scan")
        XCTAssertEqual(data.flatMap(PDFDocument.init(data:))?.pageCount, 2)
    }
}
