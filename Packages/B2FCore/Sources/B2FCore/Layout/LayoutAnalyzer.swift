import Foundation

/// Turns raw OCR observations into semantic blocks: lesson titles, headings,
/// paragraphs, tables, vocabulary lists, grammar boxes and exercises.
///
/// Geometry-based and language-aware, with no ML model, so it runs offline and is
/// deterministic. Optional `boxes` (e.g. from Vision rectangle detection)
/// let framed grammar boxes be recognised even without a keyword.
public struct LayoutAnalyzer: Sendable {

    public struct Configuration: Sendable {
        /// Line height ratio above the page median that marks a heading.
        public var headingHeightRatio: Double = 1.35
        /// Observations below this confidence are flagged for user review.
        public var lowConfidenceThreshold: Double = 0.5
        /// Vertical gap (in median line heights) that starts a new block.
        /// Textbooks commonly use generous leading (~1× line height between lines).
        public var paragraphGapRatio: Double = 1.2
        public init() {}
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Patterns

    static let lessonTitlePatterns: [String] = [
        "^(unit|lesson|chapter|module|part)\\s+[0-9IVXLC]+[A-Za-z]?\\b",
        "^(lektion|kapitel|einheit)\\s+[0-9]+",
        "^(leçon|lecon|unité|unite|chapitre)\\s+[0-9]+",
        "^(lección|leccion|unidad|capítulo|capitulo|tema)\\s+[0-9]+",
        "^(درس|فصل|بخش)\\s*[0-9۰-۹]+",
        "^(الدرس|الوحدة|الفصل)\\s*[0-9٠-٩]+",
        "^[0-9]{1,2}[A-D]\\s+\\S"   // "1A Mood food" (English File style)
    ]

    static let grammarKeywords = ["grammar", "grammatik", "grammaire", "gramática", "gramatica",
                                  "دستور", "قواعد", "language focus", "structure"]
    static let vocabularyKeywords = ["vocabulary", "wortschatz", "vocabulaire", "vocabulario", "word list",
                                     "key words", "واژگان", "لغات", "المفردات", "words and phrases"]
    static let exerciseKeywords = ["exercise", "practice", "übung", "aufgabe", "exercice", "ejercicio",
                                   "تمرین", "تمرين", "activity"]

    static let exercisePattern = "^\\s*([0-9]{1,2}|[a-h])\\s*[\\.)]\\s+\\S"
    static let vocabularyPairPattern = "^\\s*([^\\-–—:=]{2,40})\\s+[\\-–—:=]\\s+(.{1,80})$"

    // MARK: Analysis

    /// - Parameter bodyLineHeight: known body-text line height; estimated from the page when nil.
    public func analyze(pageIndex: Int, observations: [OCRTextObservation],
                        boxes: [NormalizedRect] = [], bodyLineHeight: Double? = nil) -> AnalyzedPage {
        let cleaned = observations.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cleaned.isEmpty else {
            return AnalyzedPage(pageIndex: pageIndex, blocks: [], averageConfidence: 0, lowConfidenceBlockIDs: [])
        }
        let medianHeight = bodyLineHeight ?? median(cleaned.map(\.boundingBox.height))
        let rows = groupIntoRows(cleaned, medianHeight: medianHeight)

        var blocks: [LayoutBlock] = []
        var pending: [Row] = []

        func flushParagraph() {
            guard !pending.isEmpty else { return }
            blocks.append(makeBlock(from: pending, kind: classify(pending, boxes: boxes), pageIndex: pageIndex))
            pending.removeAll()
        }

        var index = 0
        while index < rows.count {
            let row = rows[index]

            // Headings: tall, short rows.
            if isHeading(row, medianHeight: medianHeight) {
                flushParagraph()
                let kind: LayoutBlockKind = Self.matchesLessonTitle(row.text) ? .lessonTitle : .heading
                blocks.append(makeBlock(from: [row], kind: kind, pageIndex: pageIndex))
                index += 1
                continue
            }
            if Self.matchesLessonTitle(row.text, allowCompactCodes: false) && row.text.count < 60 {
                flushParagraph()
                blocks.append(makeBlock(from: [row], kind: .lessonTitle, pageIndex: pageIndex))
                index += 1
                continue
            }

            // Tables: ≥ 3 consecutive multi-cell rows with aligned columns.
            if row.cells.count >= 2 {
                var end = index
                while end + 1 < rows.count, rows[end + 1].cells.count >= 2,
                      columnsAlign(rows[end], rows[end + 1]) {
                    end += 1
                }
                if end - index + 1 >= 3 {
                    flushParagraph()
                    let tableRows = Array(rows[index...end])
                    let kind: LayoutBlockKind = looksLikeVocabularyTable(tableRows) ? .vocabularyList : .table
                    blocks.append(makeBlock(from: tableRows, kind: kind, pageIndex: pageIndex))
                    index = end + 1
                    continue
                }
            }

            // Vocabulary lists: ≥ 2 consecutive "term – meaning" lines, whatever the spacing.
            if row.cells.count == 1, Self.splitVocabularyPair(row.text) != nil {
                var end = index
                while end + 1 < rows.count, rows[end + 1].cells.count == 1,
                      Self.splitVocabularyPair(rows[end + 1].text) != nil {
                    end += 1
                }
                if end > index {
                    flushParagraph()
                    blocks.append(makeBlock(from: Array(rows[index...end]), kind: .vocabularyList, pageIndex: pageIndex))
                    index = end + 1
                    continue
                }
            }

            // A line led by a section keyword ("Grammar:", "Exercise 2") starts a new block.
            if Self.startsSection(row.text) { flushParagraph() }

            // Paragraph grouping by vertical gap.
            if let last = pending.last, row.frame.minY - last.frame.maxY > medianHeight * configuration.paragraphGapRatio {
                flushParagraph()
            }
            pending.append(row)
            index += 1
        }
        flushParagraph()

        let merged = mergeAdjacent(blocks)
        let average = cleaned.map(\.confidence).reduce(0, +) / Double(cleaned.count)
        let lowIDs = merged.filter { $0.isLowConfidence(threshold: configuration.lowConfidenceThreshold) }.map(\.id)
        return AnalyzedPage(pageIndex: pageIndex, blocks: merged, averageConfidence: average, lowConfidenceBlockIDs: lowIDs)
    }

    /// Analysis for text that has no geometry (TXT, DOCX, EPUB, PDF text layer).
    /// `headingHints` marks line indices known to be headings (e.g. DOCX Heading styles).
    public func analyze(pageIndex: Int, plainText: String, headingHints: Set<Int> = []) -> AnalyzedPage {
        let lines = plainText.components(separatedBy: .newlines)
        var observations: [OCRTextObservation] = []
        var y = 0.0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { y += 0.02; continue }
            let isHeading = headingHints.contains(i) || looksLikeHeadingText(trimmed)
            let height = isHeading ? 0.03 : 0.015
            // Tab-separated columns become separate cells.
            let cells = trimmed.components(separatedBy: "\t").filter { !$0.isEmpty }
            if cells.count > 1 {
                for (c, cell) in cells.enumerated() {
                    observations.append(OCRTextObservation(
                        text: cell, boundingBox: NormalizedRect(x: Double(c) * 0.3, y: y, width: 0.28, height: height),
                        confidence: 1))
                }
            } else {
                observations.append(OCRTextObservation(
                    text: trimmed, boundingBox: NormalizedRect(x: 0.05, y: y, width: 0.9, height: height), confidence: 1))
            }
            y += height + 0.005
        }
        return analyze(pageIndex: pageIndex, observations: observations, bodyLineHeight: 0.015)
    }

    // MARK: Rows

    struct Row {
        var cells: [OCRTextObservation]
        var frame: NormalizedRect
        var text: String { cells.map(\.text).joined(separator: " ") }
        var confidence: Double { cells.map(\.confidence).reduce(0, +) / Double(max(cells.count, 1)) }
        var height: Double { cells.map(\.boundingBox.height).max() ?? 0 }
    }

    func groupIntoRows(_ observations: [OCRTextObservation], medianHeight: Double) -> [Row] {
        let sorted = observations.sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        var rows: [Row] = []
        for observation in sorted {
            if var last = rows.last, abs(last.frame.midY - observation.boundingBox.midY) < medianHeight * 0.5 {
                last.cells.append(observation)
                last.cells.sort { $0.boundingBox.minX < $1.boundingBox.minX }
                last.frame = last.frame.union(observation.boundingBox)
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(cells: [observation], frame: observation.boundingBox))
            }
        }
        return rows
    }

    func isHeading(_ row: Row, medianHeight: Double) -> Bool {
        row.height > medianHeight * configuration.headingHeightRatio && row.text.count <= 80 && row.cells.count <= 2
    }

    func columnsAlign(_ a: Row, _ b: Row) -> Bool {
        guard a.cells.count == b.cells.count else { return false }
        return zip(a.cells, b.cells).allSatisfy { abs($0.boundingBox.minX - $1.boundingBox.minX) < 0.06 }
    }

    func looksLikeVocabularyTable(_ rows: [Row]) -> Bool {
        // Two or three columns, first column short (single word/phrase).
        guard let columns = rows.first?.cells.count, (2...3).contains(columns) else { return false }
        let shortFirst = rows.filter { ($0.cells.first?.text.split(separator: " ").count ?? 99) <= 4 }.count
        return Double(shortFirst) / Double(rows.count) >= 0.7
    }

    // MARK: Classification

    func classify(_ rows: [Row], boxes: [NormalizedRect]) -> LayoutBlockKind {
        let first = rows.first?.text.lowercased() ?? ""
        let frame = rows.dropFirst().reduce(rows[0].frame) { $0.union($1.frame) }
        if Self.grammarKeywords.contains(where: { first.hasPrefix($0) }) { return .grammarBox }
        if boxes.contains(where: { $0.contains(frame) }) && rows.count >= 2 { return .grammarBox }
        if Self.vocabularyKeywords.contains(where: { first.hasPrefix($0) }) { return .vocabularyList }
        let pairCount = rows.filter { $0.text.range(of: Self.vocabularyPairPattern, options: .regularExpression) != nil }.count
        if rows.count >= 3 && Double(pairCount) / Double(rows.count) >= 0.6 { return .vocabularyList }
        if Self.exerciseKeywords.contains(where: { first.hasPrefix($0) }) { return .exercise }
        let numbered = rows.filter { $0.text.range(of: Self.exercisePattern, options: .regularExpression) != nil }.count
        if numbered >= 2 && Double(numbered) / Double(rows.count) >= 0.4 { return .exercise }
        return .paragraph
    }

    /// `allowCompactCodes` enables "1A Title" style codes, which are only trusted
    /// when the line is typographically a heading (they collide with exercise labels).
    static func matchesLessonTitle(_ text: String, allowCompactCodes: Bool = true) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let patterns = allowCompactCodes ? lessonTitlePatterns : Array(lessonTitlePatterns.dropLast())
        return patterns.contains {
            trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    func looksLikeHeadingText(_ text: String) -> Bool {
        if Self.matchesLessonTitle(text) { return true }
        let lower = text.lowercased()
        let keywords = Self.grammarKeywords + Self.vocabularyKeywords + Self.exerciseKeywords
            + ["reading", "listening", "speaking", "writing", "lesen", "hören", "lecture", "lectura"]
        return text.count < 40 && keywords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") })
    }

    // MARK: Block construction

    func makeBlock(from rows: [Row], kind: LayoutBlockKind, pageIndex: Int) -> LayoutBlock {
        let frame = rows.dropFirst().reduce(rows[0].frame) { $0.union($1.frame) }
        let confidence = rows.map(\.confidence).reduce(0, +) / Double(rows.count)
        var tableRows: [[String]] = []
        switch kind {
        case .table:
            tableRows = rows.map { $0.cells.map(\.text) }
        case .vocabularyList:
            tableRows = rows.compactMap { row in
                if row.cells.count >= 2 { return row.cells.map(\.text) }
                return Self.splitVocabularyPair(row.text)
            }
        default:
            break
        }
        return LayoutBlock(kind: kind, pageIndex: pageIndex, lines: rows.map(\.text), rows: tableRows,
                           boundingBox: frame, confidence: confidence)
    }

    static func startsSection(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return (grammarKeywords + vocabularyKeywords + exerciseKeywords).contains { lower.hasPrefix($0) }
    }

    /// "abandon – رها کردن" → ["abandon", "رها کردن"]
    public static func splitVocabularyPair(_ line: String) -> [String]? {
        let ns = line as NSString
        guard let regex = try? NSRegularExpression(pattern: vocabularyPairPattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let term = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let meaning = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return [term, meaning]
    }

    /// Merges consecutive blocks of the same list-like kind split by small gaps.
    func mergeAdjacent(_ blocks: [LayoutBlock]) -> [LayoutBlock] {
        var result: [LayoutBlock] = []
        for block in blocks {
            if var last = result.last, last.kind == block.kind,
               [.vocabularyList, .exercise].contains(block.kind) {
                last.lines += block.lines
                last.rows += block.rows
                last.boundingBox = last.boundingBox.union(block.boundingBox)
                last.confidence = (last.confidence + block.confidence) / 2
                result[result.count - 1] = last
            } else {
                result.append(block)
            }
        }
        return result
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0.015 }
        return sorted[sorted.count / 2]
    }
}
