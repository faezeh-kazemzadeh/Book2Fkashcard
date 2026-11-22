import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import B2FCore

/// Content of one page before OCR/analysis.
enum PageContent: @unchecked Sendable {
    /// Text that already exists digitally (PDF text layer, EPUB, DOCX, TXT).
    case text(String, headingLines: Set<Int>)
    /// An image that needs OCR. `scanned` marks VisionKit-captured pages.
    case image(CGImage, orientation: CGImagePropertyOrientation, scanned: Bool)
}

/// Lazily provides pages so large PDFs never have to be rendered all at once.
protocol PageSource: Sendable {
    var pageCount: Int { get }
    func page(at index: Int) async throws -> PageContent
    func thumbnail() -> Data?
}

struct ImportedDocument: Sendable {
    var title: String
    var author: String
    var kind: BookSourceKind
    var source: any PageSource
    var originalData: Data?
    var fileExtension: String
}

enum ImportError: Error, LocalizedError {
    case unsupportedType(String)
    case accessDenied
    case passwordProtected

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let type): return "Files of type “\(type)” are not supported yet."
        case .accessDenied: return "Book2Flashcards could not access this file. Try moving it to On My iPhone or iCloud Drive."
        case .passwordProtected: return "This PDF is password-protected. Remove the password and try again."
        }
    }
}

/// Opens files from the Files app and every File Provider (iCloud Drive,
/// OneDrive, Dropbox, Google Drive) — they all arrive as security-scoped URLs
/// through `fileImporter`.
struct DocumentImporter {
    static let supportedTypes: [UTType] = [
        .pdf, .epub, .plainText, .utf8PlainText, .image, .jpeg, .png, .heic,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType(filenameExtension: "apkg") ?? .data,
        UTType(filenameExtension: "colpkg") ?? .data,
        .commaSeparatedText, .tabSeparatedText
    ]

    func open(url: URL) throws -> ImportedDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Coordinate the read so File Provider extensions download the file first.
        var coordinatedData: Data?
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
            do { coordinatedData = try Data(contentsOf: readURL, options: .mappedIfSafe) } catch { readError = error }
        }
        if let error = coordinationError ?? readError { throw error }
        guard let data = coordinatedData else { throw ImportError.accessDenied }

        let ext = url.pathExtension.lowercased()
        let baseTitle = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: ext)

        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(data: data) else { throw DocumentImportError.unreadable("PDF") }
            if document.isLocked { throw ImportError.passwordProtected }
            let source = PDFPageSource(document: document)
            let attributes = document.documentAttributes ?? [:]
            return ImportedDocument(title: (attributes[PDFDocumentAttribute.titleAttribute] as? String).nonEmpty ?? baseTitle,
                                    author: attributes[PDFDocumentAttribute.authorAttribute] as? String ?? "",
                                    kind: source.isScanned ? .scannedPDF : .pdf, source: source,
                                    originalData: data, fileExtension: "pdf")
        }
        if ext == "epub" {
            let extracted = try EPUBTextExtractor().extract(from: data)
            return ImportedDocument(title: extracted.title.nonEmpty ?? baseTitle, author: extracted.author ?? "",
                                    kind: .epub, source: TextPageSource(pages: extracted.pages),
                                    originalData: data, fileExtension: ext)
        }
        if ext == "docx" {
            let extracted = try DOCXTextExtractor().extract(from: data)
            return ImportedDocument(title: extracted.title.nonEmpty ?? baseTitle, author: "",
                                    kind: .docx, source: TextPageSource(pages: extracted.pages),
                                    originalData: data, fileExtension: ext)
        }
        if type?.conforms(to: .image) == true {
            guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                throw DocumentImportError.unreadable("image")
            }
            return ImportedDocument(title: baseTitle, author: "", kind: .images,
                                    source: ImagePageSource(images: [(cgImage, image.imageOrientation.cgOrientation)], scanned: false),
                                    originalData: data, fileExtension: ext)
        }
        if type?.conforms(to: .plainText) == true || ext == "txt" || ext == "md" {
            let extracted = try PlainTextExtractor().extract(from: data)
            return ImportedDocument(title: baseTitle, author: "", kind: .txt, source: TextPageSource(pages: extracted.pages),
                                    originalData: data, fileExtension: ext)
        }
        throw ImportError.unsupportedType(ext.isEmpty ? "unknown" : ext)
    }

    func open(images: [UIImage], title: String, scanned: Bool) -> ImportedDocument {
        let pages = images.compactMap { image in image.cgImage.map { ($0, image.imageOrientation.cgOrientation) } }
        return ImportedDocument(title: title, author: "", kind: scanned ? .camera : .images,
                                source: ImagePageSource(images: pages, scanned: scanned),
                                originalData: nil, fileExtension: "jpg")
    }

    static func isAnkiFile(_ url: URL) -> Bool {
        ["apkg", "colpkg", "csv", "tsv"].contains(url.pathExtension.lowercased())
    }
}

// MARK: - Sources

/// PDF pages: uses the text layer when it contains real text, otherwise renders
/// the page at OCR resolution (scanned PDFs).
final class PDFPageSource: PageSource, @unchecked Sendable {
    private let document: PDFDocument
    private let lock = NSLock()
    let isScanned: Bool

    init(document: PDFDocument) {
        self.document = document
        // Sample a few pages: if they have no meaningful text layer, treat the PDF as scanned.
        let samples = stride(from: 0, to: document.pageCount, by: max(1, document.pageCount / 5)).prefix(5)
        let textual = samples.filter { index in
            (document.page(at: index)?.string ?? "").filter(\.isLetter).count > 80
        }.count
        isScanned = textual * 2 < max(samples.count, 1)
    }

    var pageCount: Int { document.pageCount }

    func page(at index: Int) async throws -> PageContent {
        lock.lock()
        defer { lock.unlock() }
        guard let page = document.page(at: index) else { throw DocumentImportError.unreadable("PDF page") }
        if !isScanned, let text = page.string, text.filter(\.isLetter).count > 40, !Self.looksGarbled(text) {
            return .text(text, headingLines: [])
        }
        return .image(render(page, targetLongEdge: 2_800), orientation: .up, scanned: false)
    }

    func thumbnail() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return document.page(at: 0)?.thumbnail(of: CGSize(width: 300, height: 420), for: .mediaBox).jpegData(compressionQuality: 0.7)
    }

    private func render(_ page: PDFPage, targetLongEdge: CGFloat) -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = targetLongEdge / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage!
    }

    /// Text layers from broken PDF encoders come out as private-use or replacement characters.
    static func looksGarbled(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let bad = scalars.filter { $0.value == 0xFFFD || (0xE000...0xF8FF).contains($0.value) }.count
        return Double(bad) / Double(max(scalars.count, 1)) > 0.05
    }
}

struct TextPageSource: PageSource {
    let pages: [ExtractedDocument.Page]
    var pageCount: Int { pages.count }
    func page(at index: Int) async throws -> PageContent {
        .text(pages[index].text, headingLines: pages[index].headingLines)
    }
    func thumbnail() -> Data? { nil }
}

struct ImagePageSource: PageSource, @unchecked Sendable {
    let images: [(CGImage, CGImagePropertyOrientation)]
    let scanned: Bool
    var pageCount: Int { images.count }
    func page(at index: Int) async throws -> PageContent {
        .image(images[index].0, orientation: images[index].1, scanned: scanned)
    }
    func thumbnail() -> Data? {
        guard let first = images.first else { return nil }
        let image = UIImage(cgImage: first.0, scale: 1, orientation: first.1.uiOrientation)
        return image.preparingThumbnail(of: CGSize(width: 300, height: 420))?.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Helpers

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

extension CGImagePropertyOrientation {
    var uiOrientation: UIImage.Orientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        }
    }
}
