import Foundation

/// Languages the app supports for OCR, card generation and UI direction.
public enum StudyLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case persian = "fa"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case arabic = "ar"

    public var id: String { rawValue }

    /// English display name. The app layer localizes this with `Locale`.
    public var englishName: String {
        switch self {
        case .english: return "English"
        case .persian: return "Persian"
        case .german: return "German"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .arabic: return "Arabic"
        }
    }

    /// Right-to-left scripts need mirrored layouts and RTL text alignment.
    public var isRightToLeft: Bool { self == .persian || self == .arabic }

    /// BCP-47 identifiers handed to Vision's `recognitionLanguages`.
    /// Persian is recognised with the Arabic-script model and then normalised,
    /// because Vision does not ship a dedicated Persian model (see `OCRLanguagePlan`).
    public var visionLanguageCodes: [String] {
        switch self {
        case .english: return ["en-US", "en-GB"]
        case .persian: return ["fa-IR", "ar-SA"]
        case .german: return ["de-DE"]
        case .french: return ["fr-FR"]
        case .spanish: return ["es-ES"]
        case .arabic: return ["ar-SA"]
        }
    }

    /// Voice identifiers for `AVSpeechSynthesisVoice(language:)`.
    public var speechLanguageCode: String {
        switch self {
        case .english: return "en-US"
        case .persian: return "fa-IR"
        case .german: return "de-DE"
        case .french: return "fr-FR"
        case .spanish: return "es-ES"
        case .arabic: return "ar-SA"
        }
    }

    /// Best-effort detection of the dominant script of a string.
    public static func detectScript(of text: String) -> StudyLanguage? {
        var arabicScript = 0
        var persianSpecific = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x067E, 0x0686, 0x0698, 0x06AF, 0x06CC, 0x06A9: // پ چ ژ گ ی ک
                persianSpecific += 1
                arabicScript += 1
            case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                arabicScript += 1
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                latin += 1
            default:
                break
            }
        }
        if arabicScript == 0 && latin == 0 { return nil }
        if arabicScript > latin {
            return persianSpecific > 0 ? .persian : .arabic
        }
        return .english
    }
}

/// English accent used for pronunciation audio and IPA.
public enum EnglishAccent: String, Codable, CaseIterable, Sendable {
    case british = "en-GB"
    case american = "en-US"

    public var displayName: String { self == .british ? "British English" : "American English" }
}

/// Audio playback speeds supported by the player.
public enum PlaybackSpeed: Double, Codable, CaseIterable, Sendable, Identifiable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5

    public var id: Double { rawValue }
    public var label: String {
        switch self {
        case .half: return "0.5×"
        case .threeQuarters: return "0.75×"
        case .normal: return "1.0×"
        case .oneAndQuarter: return "1.25×"
        case .oneAndHalf: return "1.5×"
        }
    }
}
