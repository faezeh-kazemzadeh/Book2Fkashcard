import Foundation

/// Rectangle in normalised page coordinates (0...1), origin at the TOP-LEFT.
/// Vision uses a bottom-left origin; the OCR engine converts before handing
/// observations to the core.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midY: Double { y + height / 2 }

    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let nx = min(minX, other.minX)
        let ny = min(minY, other.minY)
        return NormalizedRect(x: nx, y: ny,
                              width: max(maxX, other.maxX) - nx,
                              height: max(maxY, other.maxY) - ny)
    }

    public func contains(_ other: NormalizedRect, tolerance: Double = 0.005) -> Bool {
        other.minX >= minX - tolerance && other.maxX <= maxX + tolerance &&
        other.minY >= minY - tolerance && other.maxY <= maxY + tolerance
    }

    public static let zero = NormalizedRect(x: 0, y: 0, width: 0, height: 0)
}

/// One recognised text run (typically one line or one table cell) from OCR.
public struct OCRTextObservation: Codable, Hashable, Sendable {
    public var text: String
    public var boundingBox: NormalizedRect
    public var confidence: Double

    public init(text: String, boundingBox: NormalizedRect, confidence: Double) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Structural role of a block on a page.
public enum LayoutBlockKind: String, Codable, CaseIterable, Sendable {
    case lessonTitle
    case heading
    case paragraph
    case table
    case vocabularyList
    case grammarBox
    case exercise
}

public struct LayoutBlock: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: LayoutBlockKind
    public var pageIndex: Int
    public var lines: [String]
    /// For tables and vocabulary lists: rows split into cells.
    public var rows: [[String]]
    public var boundingBox: NormalizedRect
    public var confidence: Double

    public init(id: UUID = UUID(), kind: LayoutBlockKind, pageIndex: Int, lines: [String],
                rows: [[String]] = [], boundingBox: NormalizedRect, confidence: Double) {
        self.id = id
        self.kind = kind
        self.pageIndex = pageIndex
        self.lines = lines
        self.rows = rows
        self.boundingBox = boundingBox
        self.confidence = confidence
    }

    public var text: String { lines.joined(separator: "\n") }
    public func isLowConfidence(threshold: Double) -> Bool { confidence < threshold }
}

/// Result of OCR + layout analysis for a single page.
public struct AnalyzedPage: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var blocks: [LayoutBlock]
    public var averageConfidence: Double
    public var lowConfidenceBlockIDs: [UUID]

    public init(pageIndex: Int, blocks: [LayoutBlock], averageConfidence: Double, lowConfidenceBlockIDs: [UUID]) {
        self.pageIndex = pageIndex
        self.blocks = blocks
        self.averageConfidence = averageConfidence
        self.lowConfidenceBlockIDs = lowConfidenceBlockIDs
    }

    public var plainText: String { blocks.map(\.text).joined(separator: "\n\n") }
}

// MARK: - Book outline

public enum LessonSectionKind: String, Codable, CaseIterable, Sendable {
    case vocabulary
    case grammar
    case reading
    case listening
    case speaking
    case writing
    case exercises
    case general

    public var displayName: String { rawValue.capitalized }
}

public struct LessonSection: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: LessonSectionKind
    public var title: String
    public var blocks: [LayoutBlock]

    public init(id: UUID = UUID(), kind: LessonSectionKind, title: String, blocks: [LayoutBlock] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.blocks = blocks
    }

    public var text: String { blocks.map(\.text).joined(separator: "\n") }
}

public struct LessonNode: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var sections: [LessonSection]
    public var pageRange: ClosedRange<Int>

    public init(id: UUID = UUID(), title: String, sections: [LessonSection] = [], pageRange: ClosedRange<Int>) {
        self.id = id
        self.title = title
        self.sections = sections
        self.pageRange = pageRange
    }

    public var fullText: String {
        sections.map { "## \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
    }

    public func section(_ kind: LessonSectionKind) -> [LessonSection] {
        sections.filter { $0.kind == kind }
    }
}

public struct UnitNode: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var lessons: [LessonNode]

    public init(id: UUID = UUID(), title: String, lessons: [LessonNode] = []) {
        self.id = id
        self.title = title
        self.lessons = lessons
    }
}

public struct BookOutline: Codable, Hashable, Sendable {
    public var units: [UnitNode]

    public init(units: [UnitNode]) {
        self.units = units
    }

    public var lessonCount: Int { units.reduce(0) { $0 + $1.lessons.count } }
}
