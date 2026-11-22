import SwiftUI
import StoreKit
import B2FCore

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    var highlightedFeature: PremiumFeature?
    @State private var purchasing: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill").font(.system(size: 48)).foregroundStyle(.yellow.gradient)
                            .accessibilityHidden(true)
                        Text("Book2Flashcards Premium").font(.title.bold()).multilineTextAlignment(.center)
                        if let highlightedFeature {
                            Text("\(highlightedFeature.title) is a Premium feature.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(PremiumFeature.allCases) { feature in
                            Label(feature.title, systemImage: feature.systemImage)
                                .font(feature == highlightedFeature ? .body.bold() : .body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                    if store.products.isEmpty {
                        ProgressView().task { await store.loadProducts() }
                    }
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            buy(product)
                        } label: {
                            VStack(spacing: 2) {
                                Text(product.displayName).font(.headline)
                                Text(priceLine(product)).font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(product.id == StoreManager.ProductID.yearly.rawValue ? .accentColor : .gray)
                        .disabled(purchasing != nil)
                        .overlay { if purchasing == product.id { ProgressView() } }
                    }

                    Button("Restore Purchases") { Task { await store.restore(); if store.tier == .premium { dismiss() } } }
                        .font(.footnote)

                    Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account settings.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Link("Terms of Use", destination: AppConstants.termsURL)
                        Text("·")
                        Link("Privacy Policy", destination: AppConstants.privacyPolicyURL)
                    }
                    .font(.caption)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
            .alert("Purchase failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func priceLine(_ product: Product) -> String {
        guard let subscription = product.subscription else {
            return String(localized: "\(product.displayPrice) once")
        }
        let period: String
        switch subscription.subscriptionPeriod.unit {
        case .month: period = String(localized: "month")
        case .year: period = String(localized: "year")
        case .week: period = String(localized: "week")
        default: period = String(localized: "day")
        }
        if let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial {
            return String(localized: "\(offer.period.value)-\(offer.period.unit == .day ? "day" : "week") free trial, then \(product.displayPrice)/\(period)")
        }
        return "\(product.displayPrice)/\(period)"
    }

    private func buy(_ product: Product) {
        purchasing = product.id
        Task {
            defer { purchasing = nil }
            do {
                if try await store.purchase(product) == .success { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
