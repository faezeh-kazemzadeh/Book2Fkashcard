import Foundation

public enum PlanTier: String, Codable, Sendable {
    case free
    case premium
}

public enum PremiumFeature: String, CaseIterable, Sendable, Identifiable {
    case unlimitedBooks
    case unlimitedCards
    case advancedOCR
    case aiExplanations
    case ankiExport
    case cloudSync

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .unlimitedBooks: return "Unlimited books"
        case .unlimitedCards: return "Unlimited flashcards"
        case .advancedOCR: return "Advanced OCR"
        case .aiExplanations: return "AI explanations"
        case .ankiExport: return "Anki export"
        case .cloudSync: return "iCloud sync"
        }
    }
    public var systemImage: String {
        switch self {
        case .unlimitedBooks: return "books.vertical"
        case .unlimitedCards: return "rectangle.stack"
        case .advancedOCR: return "doc.text.viewfinder"
        case .aiExplanations: return "sparkles"
        case .ankiExport: return "square.and.arrow.up"
        case .cloudSync: return "icloud"
        }
    }
}

public enum GateDecision: Equatable, Sendable {
    case allowed
    /// Allowed, but only `remaining` more items fit in the free plan.
    case partiallyAllowed(remaining: Int)
    case requiresPremium(PremiumFeature)
}

/// Single source of truth for plan limits. The UI asks the gate before acting
/// and shows the paywall on `.requiresPremium`.
public struct FeatureGate: Sendable {
    public static let freeBookLimit = 3
    public static let freeCardLimit = 500

    public var tier: PlanTier

    public init(tier: PlanTier) {
        self.tier = tier
    }

    public func canAddBook(currentBookCount: Int) -> GateDecision {
        guard tier == .free else { return .allowed }
        return currentBookCount < Self.freeBookLimit ? .allowed : .requiresPremium(.unlimitedBooks)
    }

    public func canAddCards(currentCardCount: Int, adding: Int) -> GateDecision {
        guard tier == .free else { return .allowed }
        let remaining = Self.freeCardLimit - currentCardCount
        if remaining <= 0 { return .requiresPremium(.unlimitedCards) }
        return adding <= remaining ? .allowed : .partiallyAllowed(remaining: remaining)
    }

    public func check(_ feature: PremiumFeature) -> GateDecision {
        tier == .premium ? .allowed : .requiresPremium(feature)
    }

    /// OCR mode available for the plan. Basic = Vision fast path without
    /// perspective/shadow preprocessing or AI-assisted correction.
    public var ocrMode: OCRMode { tier == .premium ? .advanced : .basic }
}

public enum OCRMode: String, Codable, Sendable {
    case basic
    case advanced
}
