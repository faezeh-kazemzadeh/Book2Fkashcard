import Foundation

/// Builds the Book → Unit → Lesson → Section outline from analysed pages.
///
/// Works offline from layout cues. When an AI provider is configured, the
/// `AILessonRefiner` may rename or regroup lessons afterwards, but this
/// deterministic pass always produces a usable outline first.
public struct LessonStructureDetector: Sendable {

    public struct Configuration: Sendable {
        /// When no lesson headings exist, split the book into lessons of this many pages.
        public var fallbackPagesPerLesson: Int = 4
        public init() {}
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    private static let unitPattern = "^(unit|module|chapter|part|einheit|kapitel|unité|unite|chapitre|unidad|capítulo|capitulo|فصل|بخش|الوحدة|الفصل)\\s+([0-9IVXLC۰-۹٠-٩]+)\\b"
    private static let lessonPattern = "^(lesson|lektion|leçon|lecon|lección|leccion|tema|درس|الدرس)\\s+([0-9۰-۹٠-٩]+[A-Za-z]?)\\b"
    private static let compactLessonPattern = "^([0-9]{1,2})([A-D])\\b"

    public func detect(pages: [AnalyzedPage]) -> BookOutline {
        var units: [UnitNode] = []
        var currentUnit: UnitNode?
        var currentLesson: LessonNode?
        var currentSection: LessonSection?
        var foundExplicitLesson = false
        var currentUnitNumber: Int?

        func closeSection() {
            guard let section = currentSection, !section.blocks.isEmpty else { currentSection = nil; return }
            currentLesson?.sections.append(section)
            currentSection = nil
        }
        func closeLesson() {
            closeSection()
            guard let lesson = currentLesson, !lesson.sections.isEmpty else { currentLesson = nil; return }
            if currentUnit == nil { currentUnit = UnitNode(title: "Unit 1") }
            currentUnit?.lessons.append(lesson)
            currentLesson = nil
        }
        func closeUnit() {
            closeLesson()
            if let unit = currentUnit, !unit.lessons.isEmpty { units.append(unit) }
            currentUnit = nil
        }
        func ensureLesson(page: Int) {
            if currentLesson == nil {
                let number = (currentUnit?.lessons.count ?? 0) + 1
                currentLesson = LessonNode(title: "Lesson \(number)", pageRange: page...page)
            }
        }

        for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            for block in page.blocks {
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let isTitleLike = block.kind == .lessonTitle || block.kind == .heading

                if isTitleLike, let unitTitle = match(text, Self.unitPattern) {
                    closeUnit()
                    currentUnit = UnitNode(title: unitTitle)
                    currentUnitNumber = leadingNumber(in: text)
                    // "Unit 3 Lesson 3B" on one line also opens a lesson.
                    if let lessonTitle = firstLessonReference(in: text) {
                        foundExplicitLesson = true
                        currentLesson = LessonNode(title: lessonTitle, pageRange: page.pageIndex...page.pageIndex)
                    }
                    continue
                }
                if isTitleLike, let lessonTitle = firstLessonReference(in: text) {
                    foundExplicitLesson = true
                    closeLesson()
                    if let code = compactCode(text), code.unit != currentUnitNumber {
                        closeUnit()
                        currentUnit = UnitNode(title: "Unit \(code.unit)")
                        currentUnitNumber = code.unit
                    }
                    currentLesson = LessonNode(title: lessonTitle, pageRange: page.pageIndex...page.pageIndex)
                    continue
                }

                ensureLesson(page: page.pageIndex)
                if let range = currentLesson?.pageRange {
                    currentLesson?.pageRange = range.lowerBound...max(range.upperBound, page.pageIndex)
                }

                if block.kind == .heading {
                    closeSection()
                    currentSection = LessonSection(kind: sectionKind(forHeading: text), title: text)
                    continue
                }

                let blockSectionKind = sectionKind(forBlock: block)
                if currentSection == nil {
                    currentSection = LessonSection(kind: blockSectionKind, title: blockSectionKind.displayName)
                } else if let section = currentSection, section.kind == .general, blockSectionKind != .general,
                          blockSectionKind != .reading {
                    // A typed block (e.g. grammar box) inside untyped content gets its own section.
                    closeSection()
                    currentSection = LessonSection(kind: blockSectionKind, title: blockSectionKind.displayName)
                }
                currentSection?.blocks.append(block)
            }
        }
        closeUnit()

        if !foundExplicitLesson {
            return fallbackOutline(pages: pages, headingDriven: units)
        }
        return BookOutline(units: mergeDuplicateSections(units))
    }

    // MARK: Helpers

    private func match(_ text: String, _ pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let head = String(text[range])
        let rest = text[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :.-–—\t"))
        let firstLine = rest.split(separator: "\n").first.map(String.init) ?? ""
        let subtitle = firstLine.count <= 50 ? firstLine : ""
        return subtitle.isEmpty ? capitalizeFirst(head) : "\(capitalizeFirst(head)) – \(subtitle)"
    }

    private func firstLessonReference(in text: String) -> String? {
        if let explicit = match(text, Self.lessonPattern) { return explicit }
        if let range = text.range(of: "\\b(lesson|lektion|leçon|lección|درس)\\s*[0-9]+[A-Za-z]?", options: [.regularExpression, .caseInsensitive]) {
            return capitalizeFirst(String(text[range]))
        }
        if let code = compactCode(text) {
            let rest = text.dropFirst(code.raw.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty || rest.count > 50 ? "Lesson \(code.raw)" : "Lesson \(code.raw) – \(rest)"
        }
        return nil
    }

    private func compactCode(_ text: String) -> (raw: String, unit: Int)? {
        guard let range = text.range(of: Self.compactLessonPattern, options: .regularExpression) else { return nil }
        let raw = String(text[range])
        guard let unit = Int(raw.dropLast()) else { return nil }
        return (raw.uppercased(), unit)
    }

    private func leadingNumber(in text: String) -> Int? {
        guard let range = text.range(of: "[0-9]+", options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    private func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    func sectionKind(forHeading text: String) -> LessonSectionKind {
        let lower = text.lowercased()
        let table: [(LessonSectionKind, [String])] = [
            (.vocabulary, LayoutAnalyzer.vocabularyKeywords),
            (.grammar, LayoutAnalyzer.grammarKeywords),
            (.reading, ["reading", "read", "lesen", "lecture", "lectura", "خواندن", "درک مطلب", "القراءة", "text"]),
            (.listening, ["listening", "listen", "hören", "écoute", "comprensión auditiva", "شنیدن", "الاستماع"]),
            (.speaking, ["speaking", "speak", "sprechen", "expression orale", "conversación", "صحبت", "مکالمه", "المحادثة"]),
            (.writing, ["writing", "write", "schreiben", "écriture", "escritura", "نوشتن", "الكتابة"]),
            (.exercises, LayoutAnalyzer.exerciseKeywords)
        ]
        for (kind, keywords) in table where keywords.contains(where: { lower.contains($0) }) {
            return kind
        }
        return .general
    }

    func sectionKind(forBlock block: LayoutBlock) -> LessonSectionKind {
        switch block.kind {
        case .vocabularyList: return .vocabulary
        case .grammarBox: return .grammar
        case .exercise: return .exercises
        case .paragraph: return .reading
        default: return .general
        }
    }

    /// No lesson headings anywhere: use heading-driven sections if present,
    /// otherwise fixed page windows, so every book yields lessons.
    private func fallbackOutline(pages: [AnalyzedPage], headingDriven: [UnitNode]) -> BookOutline {
        let lessons = headingDriven.flatMap(\.lessons)
        if lessons.count == 1, lessons[0].sections.count > 1, pages.count > configuration.fallbackPagesPerLesson {
            // One huge lesson: split by page windows instead.
        } else if !lessons.isEmpty && pages.count <= configuration.fallbackPagesPerLesson {
            return BookOutline(units: headingDriven)
        }
        let sorted = pages.sorted { $0.pageIndex < $1.pageIndex }
        var unit = UnitNode(title: "Unit 1")
        var start = 0
        while start < sorted.count {
            let window = Array(sorted[start..<min(start + configuration.fallbackPagesPerLesson, sorted.count)])
            let blocks = window.flatMap(\.blocks)
            var sections: [LessonSection] = []
            for block in blocks {
                let kind = block.kind == .heading ? sectionKind(forHeading: block.text) : sectionKind(forBlock: block)
                if let last = sections.last, last.kind == kind {
                    sections[sections.count - 1].blocks.append(block)
                } else {
                    sections.append(LessonSection(kind: kind, title: kind.displayName, blocks: [block]))
                }
            }
            if !sections.isEmpty, let first = window.first, let last = window.last {
                unit.lessons.append(LessonNode(title: "Lesson \(unit.lessons.count + 1)", sections: sections,
                                               pageRange: first.pageIndex...last.pageIndex))
            }
            start += configuration.fallbackPagesPerLesson
        }
        return BookOutline(units: unit.lessons.isEmpty ? [] : [unit])
    }

    private func mergeDuplicateSections(_ units: [UnitNode]) -> [UnitNode] {
        units.map { unit in
            var unit = unit
            unit.lessons = unit.lessons.map { lesson in
                var lesson = lesson
                var merged: [LessonSection] = []
                for section in lesson.sections {
                    if let last = merged.last, last.kind == section.kind, section.kind != .general,
                       last.title == section.title || section.title == section.kind.displayName {
                        merged[merged.count - 1].blocks += section.blocks
                    } else {
                        merged.append(section)
                    }
                }
                lesson.sections = merged
                return lesson
            }
            return unit
        }
    }
}
