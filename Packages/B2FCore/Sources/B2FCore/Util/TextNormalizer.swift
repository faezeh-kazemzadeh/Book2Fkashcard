import Foundation

/// Text normalisation shared by search, deduplication, OCR post-processing and
/// answer checking. Handles Latin diacritics and Persian/Arabic orthographic variants.
public enum TextNormalizer {

    /// Normalises Arabic-script text to standard Persian orthography.
    /// Vision's Arabic model emits Arabic Yeh/Kaf; Persian text needs ی and ک.
    public static func persianOrthography(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064A, 0x0649: scalars.append(Unicode.Scalar(0x06CC)!) // ي ى -> ی
            case 0x0643: scalars.append(Unicode.Scalar(0x06A9)!)         // ك -> ک
            case 0x0660...0x0669: // Arabic-Indic digits -> Persian digits
                scalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x06F0)!)
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Aggressive key for search and duplicate detection:
    /// case/diacritic folding, Arabic-script unification, digit folding,
    /// removal of tatweel, harakat and zero-width joiners, whitespace collapse.
    public static func searchKey(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640: continue           // harakat, superscript alef, tatweel
            case 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF: continue   // ZWNJ, ZWJ, LRM, RLM, BOM
            case 0x064A, 0x0649: scalars.append(Unicode.Scalar(0x06CC)!)
            case 0x0643: scalars.append(Unicode.Scalar(0x06A9)!)
            case 0x0622, 0x0623, 0x0625: scalars.append(Unicode.Scalar(0x0627)!) // آ أ إ -> ا
            case 0x0629: scalars.append(Unicode.Scalar(0x0647)!)                 // ة -> ه
            case 0x06F0...0x06F9: scalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x0660...0x0669: scalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            default: scalars.append(scalar)
            }
        }
        let folded = String(scalars)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return collapseWhitespace(folded)
    }

    public static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Splits text into word tokens (letters, digits, apostrophes and hyphens inside words).
    public static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "\u{200C}" {
                current.append(character)
            } else if (character == "'" || character == "’" || character == "-") && !current.isEmpty {
                current.append(character)
            } else {
                if !current.isEmpty { result.append(trimJoiners(current)) }
                current = ""
            }
        }
        if !current.isEmpty { result.append(trimJoiners(current)) }
        return result.filter { !$0.isEmpty }
    }

    private static func trimJoiners(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "'’-\u{200C}"))
    }

    /// Removes HTML tags and decodes the handful of entities Anki and EPUB content use.
    public static func stripHTML(_ html: String) -> String {
        var text = html
        let blockBreaks = ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</tr>"]
        for tag in blockBreaks {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text
            .components(separatedBy: "\n")
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func decodeEntities(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                         ("&apos;", "'"), ("&#39;", "'"), ("&mdash;", "—"), ("&ndash;", "–"),
                                         ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
                                         ("&ldquo;", "“"), ("&rdquo;", "”")]
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        // Numeric entities: &#1234; and &#x4D2;
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            let ns = result as NSString
            var output = ""
            var last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = ns.substring(with: match.range(at: 1)) == "x"
                let digits = ns.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    output.unicodeScalars.append(scalar)
                }
                last = match.range.location + match.range.length
            }
            output += ns.substring(from: last)
            result = output
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Escapes text for inclusion in HTML (Anki fields are HTML).
    public static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Levenshtein distance over Characters (grapheme clusters).
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let lhs = Array(a), rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
