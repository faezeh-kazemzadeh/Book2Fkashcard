import Foundation

/// Imports Anki "Notes in Plain Text" exports and generic CSV/TSV word lists.
///
/// Understands Anki's file headers (Anki 2.1.55+):
/// `#separator:tab`, `#html:true`, `#tags column:3`, `#deck column:4`, `#notetype column:5`, `#guid column:1`.
/// Without headers the delimiter is detected (tab, semicolon, comma, pipe) and a
/// header row like "front,back,tags" is recognised.
public struct AnkiTextImporter {

    public struct Options: Sendable {
        public var defaultDeck: String
        public var delimiter: Character?
        public init(defaultDeck: String = "Imported", delimiter: Character? = nil) {
            self.defaultDeck = defaultDeck
            self.delimiter = delimiter
        }
    }

    public init() {}

    public func parse(_ text: String, options: Options = Options()) throws -> [ImportedAnkiNote] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if lines.hasPrefix("\u{feff}") { lines.removeFirst() }

        var delimiter = options.delimiter
        var isHTML = false
        var tagsColumn: Int?
        var deckColumn: Int?
        var guidColumn: Int?
        var notetypeColumn: Int?
        var bodyLines: [Substring] = []

        for line in lines.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#"), let colon = line.firstIndex(of: ":") {
                let key = line[line.index(after: line.startIndex)..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "separator": delimiter = Self.separator(named: value)
                case "html": isHTML = value.lowercased() == "true"
                case "tags column": tagsColumn = Int(value).map { $0 - 1 }
                case "deck column": deckColumn = Int(value).map { $0 - 1 }
                case "guid column": guidColumn = Int(value).map { $0 - 1 }
                case "notetype column": notetypeColumn = Int(value).map { $0 - 1 }
                default: break
                }
                continue
            }
            bodyLines.append(line)
        }

        let body = bodyLines.joined(separator: "\n")
        let resolvedDelimiter = delimiter ?? detectDelimiter(body)
        var rows = parseRows(body, delimiter: resolvedDelimiter).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { throw AnkiError.invalidCSV("no rows found") }

        var fieldNames: [String] = []
        if let header = rows.first, isHeaderRow(header) {
            fieldNames = header.map { $0.trimmingCharacters(in: .whitespaces) }
            rows.removeFirst()
            let lower = fieldNames.map { $0.lowercased() }
            tagsColumn = tagsColumn ?? lower.firstIndex(of: "tags")
            deckColumn = deckColumn ?? lower.firstIndex(of: "deck")
        }

        let metaColumns = Set([tagsColumn, deckColumn, guidColumn, notetypeColumn].compactMap { $0 })
        return rows.enumerated().map { index, row -> ImportedAnkiNote in
            var values: [String] = []
            var names: [String] = []
            for (column, value) in row.enumerated() where !metaColumns.contains(column) {
                values.append(isHTML ? value : TextNormalizer.escapeHTML(value))
                names.append(column < fieldNames.count ? fieldNames[column] : (values.count == 1 ? "Front" : values.count == 2 ? "Back" : "Field \(values.count)"))
            }
            func cell(_ column: Int?) -> String? {
                guard let column, column < row.count else { return nil }
                let value = row[column].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return ImportedAnkiNote(
                guid: cell(guidColumn) ?? "csv-\(index)-\(SHA1.hexDigest(row.joined(separator: "|")).prefix(10))",
                noteTypeName: cell(notetypeColumn) ?? "Basic",
                fieldNames: names,
                fieldValues: values,
                tags: cell(tagsColumn)?.split(separator: " ").map(String.init) ?? [],
                deckPath: (cell(deckColumn) ?? options.defaultDeck).components(separatedBy: "::"),
                scheduling: nil,
                isSuspended: false
            )
        }
    }

    // MARK: CSV parsing (RFC 4180 quoting)

    func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text)
        iterator.append("\n")
        var i = 0
        while i < iterator.count {
            let c = iterator[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < iterator.count && iterator[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    func detectDelimiter(_ text: String) -> Character {
        let sample = text.split(separator: "\n").prefix(20)
        let candidates: [Character] = ["\t", ";", ",", "|"]
        var best: Character = "\t"
        var bestScore = -1
        for candidate in candidates {
            let counts = sample.map { line in line.filter { $0 == candidate }.count }
            guard let first = counts.first, first > 0 else { continue }
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * 10 + first
            if score > bestScore { bestScore = score; best = candidate }
        }
        return best
    }

    private func isHeaderRow(_ row: [String]) -> Bool {
        let known: Set<String> = ["front", "back", "word", "term", "translation", "meaning", "definition",
                                  "example", "tags", "deck", "question", "answer", "ipa"]
        let lower = row.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return lower.filter { known.contains($0) }.count >= 2
    }

    static func separator(named value: String) -> Character {
        switch value.lowercased() {
        case "tab": return "\t"
        case "comma": return ","
        case "semicolon": return ";"
        case "pipe": return "|"
        case "space": return " "
        case "colon": return ":"
        default: return value.first ?? "\t"
        }
    }
}
