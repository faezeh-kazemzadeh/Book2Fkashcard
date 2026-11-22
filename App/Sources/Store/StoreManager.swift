import Foundation
import StoreKit
import Observation
import B2FCore

/// StoreKit 2 subscriptions: monthly, yearly (with free trial) and lifetime.
///
/// Entitlements come from `Transaction.currentEntitlements`, which StoreKit
/// syncs across the user's devices via their Apple Account, so the premium
/// state "syncs" without any custom server. All transactions are verified
/// (JWS) before granting access.
@MainActor
@Observable
final class StoreManager {
    enum ProductID: String, CaseIterable {
        case monthly = "com.book2flashcards.pro.premium.monthly"
        case yearly = "com.book2flashcards.pro.premium.yearly"
        case lifetime = "com.book2flashcards.pro.premium.lifetime"
    }

    enum PurchaseResult: Equatable { case success, pending, cancelled }

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Debug/UI-test override (launch argument `-PremiumOverride`).
    @ObservationIgnored private let forcePremium = ProcessInfo.processInfo.arguments.contains("-PremiumOverride")

    var tier: PlanTier { (forcePremium || !purchasedProductIDs.isEmpty) ? .premium : .free }
    var gate: FeatureGate { FeatureGate(tier: tier) }

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func start() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            let order = ProductID.allCases.map(\.rawValue)
            products = loaded.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async throws -> PurchaseResult {
        let result = try await product.purchase(options: [.appAccountToken(Self.appAccountToken)])
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// "Restore Purchases" (App Review requirement).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? verified(entitlement), transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            active.insert(transaction.productID)
        }
        purchasedProductIDs = active
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? verified(update) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }

    func product(_ id: ProductID) -> Product? { products.first { $0.id == id.rawValue } }

    /// Stable per-install token linking App Store transactions to this user for server-side validation.
    static var appAccountToken: UUID {
        let key = "b2f.appAccountToken"
        if let string = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: string) { return uuid }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }
}
