import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Text extracted from a non-image document, split into logical pages.
public struct ExtractedDocument: Sendable {
    public struct Page: Sendable {
        public var text: String
        /// Indices of lines (within `text`) that are headings in the source.
        public var headingLines: Set<Int>
        public init(text: String, headingLines: Set<Int> = []) {
            self.text = text
            self.headingLines = headingLines
        }
    }
    public var title: String?
    public var author: String?
    public var pages: [Page]
}

public enum DocumentImportError: Error, LocalizedError {
    case unreadable(String)
    case encrypted
    case empty

    public var errorDescription: String? {
        switch self {
        case .unreadable(let what): return "The \(what) file could not be read."
        case .encrypted: return "This file is DRM-protected and cannot be imported."
        case .empty: return "No text was found in this file."
        }
    }
}

// MARK: - DOCX

/// Extracts paragraphs from `word/document.xml`, keeping heading styles and
/// table rows (as tab-separated lines). Page breaks start new pages.
public struct DOCXTextExtractor {
    public init() {}

    public func extract(from data: Data) throws -> ExtractedDocument {
        let xml: Data
        do {
            xml = try ZipArchive.extract(path: "word/document.xml", from: data)
        } catch {
            throw DocumentImportError.unreadable("Word")
        }
        let delegate = DOCXParserDelegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { throw DocumentImportError.unreadable("Word") }
        delegate.finishPage()

        var title: String?
        if let core = try? ZipArchive.extract(path: "docProps/core.xml", from: data),
           let string = String(data: core, encoding: .utf8),
           let range = string.range(of: "<dc:title>(.*?)</dc:title>", options: .regularExpression) {
            title = TextNormalizer.stripHTML(String(string[range]))
        }
        let pages = delegate.pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pages.isEmpty else { throw DocumentImportError.empty }
        return ExtractedDocument(title: title, author: nil, pages: pages)
    }
}

private final class DOCXParserDelegate: NSObject, XMLParserDelegate {
    var pages: [ExtractedDocument.Page] = []
    private var lines: [String] = []
    private var headings: Set<Int> = []
    private var paragraph = ""
    private var isHeading = false
    private var inText = false
    private var inTable = 0
    private var rowCells: [String] = []
    private var cellText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "w:p": paragraph = ""; isHeading = false
        case "w:pStyle":
            let style = (attributes["w:val"] ?? "").lowercased()
            if style.hasPrefix("heading") || style == "title" || style.contains("berschrift") { isHeading = true }
        case "w:t": inText = true
        case "w:tab": appendText("\t")
        case "w:br":
            if attributes["w:type"] == "page" { finishParagraph(); finishPage() } else { appendText("\n") }
        case "w:tbl": inTable += 1
        case "w:tr": rowCells = []
        case "w:tc": cellText = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { appendText(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:p":
            if inTable > 0 {
                cellText += (cellText.isEmpty ? "" : " ") + paragraph.trimmingCharacters(in: .whitespaces)
                paragraph = ""
            } else {
                finishParagraph()
            }
        case "w:tc": rowCells.append(cellText)
        case "w:tr": lines.append(rowCells.joined(separator: "\t"))
        case "w:tbl": inTable -= 1
        default: break
        }
    }

    private func appendText(_ text: String) { paragraph += text }

    private func finishParagraph() {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if isHeading { headings.insert(lines.count) }
            lines.append(trimmed)
        }
        paragraph = ""
    }

    func finishPage() {
        guard !lines.isEmpty else { return }
        pages.append(ExtractedDocument.Page(text: lines.joined(separator: "\n"), headingLines: headings))
        lines = []
        headings = []
    }
}

// MARK: - EPUB

/// Reads EPUB 2/3: `META-INF/container.xml` → OPF → spine order → XHTML.
/// Each spine item becomes a page. `<h1>`–`<h3>` lines are heading hints.
public struct EPUBTextExtractor {
    public init() {}

    public func extract(from data: Data) throws -> ExtractedDocument {
        let files: [String: Data]
        do {
            files = try ZipArchive.extractAll(from: data)
        } catch {
            throw DocumentImportError.unreadable("EPUB")
        }
        if files["META-INF/encryption.xml"].map({ String(decoding: $0, as: UTF8.self).contains("EncryptedData") }) == true,
           files["META-INF/rights.xml"] != nil {
            throw DocumentImportError.encrypted
        }
        guard let container = files["META-INF/container.xml"].map({ String(decoding: $0, as: UTF8.self) }),
              let opfPath = Self.attribute("full-path", inFirst: "rootfile", of: container),
              let opfData = files[opfPath] else {
            throw DocumentImportError.unreadable("EPUB")
        }
        let opf = String(decoding: opfData, as: UTF8.self)
        let base = (opfPath as NSString).deletingLastPathComponent

        var manifest: [String: String] = [:]
        for item in Self.tags(named: "item", in: opf) {
            if let id = Self.attribute("id", in: item), let href = Self.attribute("href", in: item) {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        }
        let spine = Self.tags(named: "itemref", in: opf).compactMap { Self.attribute("idref", in: $0) }

        var pages: [ExtractedDocument.Page] = []
        for idref in spine {
            guard let href = manifest[idref] else { continue }
            let path = base.isEmpty ? href : base + "/" + href
            guard let html = files[path].map({ String(decoding: $0, as: UTF8.self) }) else { continue }
            let page = Self.page(fromXHTML: html)
            if !page.text.isEmpty { pages.append(page) }
        }
        guard !pages.isEmpty else { throw DocumentImportError.empty }

        let title = Self.element("dc:title", in: opf)
        let author = Self.element("dc:creator", in: opf)
        return ExtractedDocument(title: title, author: author, pages: pages)
    }

    static func page(fromXHTML html: String) -> ExtractedDocument.Page {
        // Mark headings before stripping tags so they can be recovered as hints.
        var marked = html.replacingOccurrences(of: "<h[1-3][^>]*>", with: "\n\u{1}", options: [.regularExpression, .caseInsensitive])
        marked = marked.replacingOccurrences(of: "</h[1-3]>", with: "\n", options: [.regularExpression, .caseInsensitive])
        marked = marked.replacingOccurrences(of: "</t[dh]>", with: "\t", options: [.regularExpression, .caseInsensitive])
        if let bodyRange = marked.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            marked = String(marked[bodyRange.upperBound...])
        }
        let text = TextNormalizer.stripHTML(marked)
        var lines: [String] = []
        var headings: Set<Int> = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("\u{1}") {
                let clean = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty else { continue }
                headings.insert(lines.count)
                lines.append(clean)
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        return ExtractedDocument.Page(text: lines.joined(separator: "\n"), headingLines: headings)
    }

    // Minimal tag helpers (OPF files are small and regular).
    static func tags(named name: String, in xml: String) -> [String] {
        let pattern = "<(?:[a-zA-Z0-9]+:)?\(name)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
        return (tag as NSString).substring(with: match.range(at: 1))
    }

    static func attribute(_ name: String, inFirst tagName: String, of xml: String) -> String? {
        tags(named: tagName, in: xml).first.flatMap { attribute(name, in: $0) }
    }

    static func element(_ name: String, in xml: String) -> String? {
        guard let range = xml.range(of: "<\(name)[^>]*>([\\s\\S]*?)</\(name)>", options: .regularExpression) else { return nil }
        let value = TextNormalizer.stripHTML(String(xml[range]))
        return value.isEmpty ? nil : value
    }
}

// MARK: - Plain text

public struct PlainTextExtractor {
    public init() {}

    /// Decodes UTF-8/UTF-16 (with BOM) or Windows-1256 (common for Persian/Arabic TXT files).
    public func extract(from data: Data, linesPerPage: Int = 60) throws -> ExtractedDocument {
        let text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16) ?? ""
        } else if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let arabic = String(data: data, encoding: String.Encoding(rawValue: 0x8000_0504)) { // windows-1256
            text = arabic
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw DocumentImportError.empty }
        var pages: [ExtractedDocument.Page] = []
        var index = 0
        while index < lines.count {
            let slice = lines[index..<min(index + linesPerPage, lines.count)]
            pages.append(ExtractedDocument.Page(text: slice.joined(separator: "\n")))
            index += linesPerPage
        }
        return ExtractedDocument(title: nil, author: nil, pages: pages)
    }
}
