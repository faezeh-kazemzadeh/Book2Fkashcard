import Foundation

/// Decides which recognition languages to request and how to post-process,
/// given what the device's Vision version actually supports.
///
/// Vision has no Persian model. For Persian books the plan uses the Arabic
/// model (same script) and then normalises to Persian orthography; pages with
/// Persian text get a lower confidence ceiling so they are offered for
/// AI-assisted correction in advanced mode.
public struct OCRLanguagePlan: Sendable, Equatable {
    public var recognitionLanguages: [String]
    public var normalizeToPersian: Bool
    public var confidenceCeiling: Double
    public var unsupported: [StudyLanguage]

    public init(languages: [StudyLanguage], supportedByDevice: [String]) {
        let supported = Set(supportedByDevice.map { $0.lowercased() })
        var codes: [String] = []
        var unsupported: [StudyLanguage] = []
        for language in languages {
            // Exact identifiers only: Vision rejects requests naming unsupported languages.
            let usable = language.visionLanguageCodes.filter { supported.contains($0.lowercased()) }
            if usable.isEmpty { unsupported.append(language) }
            for code in usable where !codes.contains(code) { codes.append(code) }
        }
        if codes.isEmpty { codes = ["en-US"] }
        // Vision gives priority to earlier languages; Latin-script languages first
        // keeps mixed textbooks (e.g. English with Persian glosses) accurate.
        let isArabicScript = { (code: String) in code.hasPrefix("ar") || code.hasPrefix("fa") }
        codes = codes.filter { !isArabicScript($0) } + codes.filter(isArabicScript)
        self.recognitionLanguages = codes
        self.normalizeToPersian = languages.contains(.persian)
        self.confidenceCeiling = languages.contains(.persian) && !supported.contains("fa-ir") ? 0.85 : 1.0
        self.unsupported = unsupported
    }

    /// Applies language-specific clean-up to a recognised line.
    public func postProcess(_ text: String) -> String {
        var result = text
        if normalizeToPersian, StudyLanguage.detectScript(of: text) == .persian || StudyLanguage.detectScript(of: text) == .arabic {
            result = TextNormalizer.persianOrthography(result)
        }
        // Common OCR ligature/quote artefacts.
        result = result.replacingOccurrences(of: "ﬁ", with: "fi").replacingOccurrences(of: "ﬂ", with: "fl")
            .replacingOccurrences(of: "\u{00AD}", with: "")
        return result
    }

    public func adjustedConfidence(_ confidence: Double, text: String) -> Double {
        let script = StudyLanguage.detectScript(of: text)
        if script == .persian || script == .arabic { return min(confidence, confidenceCeiling) }
        return confidence
    }
}
