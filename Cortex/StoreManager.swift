import Foundation
import RevenueCat

/// A simplified, view-friendly subscription plan derived from a RevenueCat package.
struct ProPlan: Identifiable {
    let id: String            // RevenueCat package identifier
    let title: String
    let priceString: String   // e.g. "$4.99"
    let periodLabel: String   // e.g. "$4.99 / month"
    let isAnnual: Bool
    let trialLabel: String?   // e.g. "7-day free trial" if this plan has an intro offer
    let package: Package      // underlying RevenueCat package for purchase
}

/// Subscription manager backed by **RevenueCat**. Loads the current offering's
/// packages, runs purchases/restores through RevenueCat, and exposes the live
/// "pro" entitlement as `isPro`.
///
/// Requires `RevenueCatConfig.apiKey` set, products in App Store Connect, and a
/// RevenueCat dashboard configured with an offering + the `pro` entitlement.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var plans: [ProPlan] = []
    @Published private(set) var isPro = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var loadFailed = false

    private static var didConfigure = false

    init() {
        configureIfNeeded()
        listenForCustomerInfo()
        Task {
            await refreshEntitlement()
            await loadOfferings()
        }
    }

    /// Configure the RevenueCat SDK once, before any other Purchases call.
    private func configureIfNeeded() {
        guard !Self.didConfigure, RevenueCatConfig.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Self.didConfigure = true
    }

    // MARK: Loading

    func loadOfferings() async {
        guard RevenueCatConfig.isConfigured else { loadFailed = true; return }
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            plans = packages
                .map { ProPlan(package: $0) }
                .sorted { $0.package.storeProduct.price < $1.package.storeProduct.price }
            loadFailed = plans.isEmpty
        } catch {
            plans = []
            loadFailed = true
        }
    }

    // MARK: Purchase / restore

    enum PurchaseOutcome { case success, cancelled, pending }

    @discardableResult
    func purchase(_ plan: ProPlan) async throws -> PurchaseOutcome {
        guard RevenueCatConfig.isConfigured else { return .cancelled }
        purchasingID = plan.id
        defer { purchasingID = nil }
        let result = try await Purchases.shared.purchase(package: plan.package)
        if result.userCancelled { return .cancelled }
        apply(result.customerInfo)
        return .success
    }

    func restore() async {
        guard RevenueCatConfig.isConfigured else { return }
        if let info = try? await Purchases.shared.restorePurchases() {
            apply(info)
        }
    }

    func refreshEntitlement() async {
        guard RevenueCatConfig.isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo() {
            apply(info)
        }
    }

    /// Present Apple's offer-code redemption sheet (for the codes you generate in
    /// App Store Connect, e.g. a code that grants the free trial). After the user
    /// redeems, the entitlement updates automatically via `customerInfoStream`.
    func redeemCode() {
        guard RevenueCatConfig.isConfigured else { return }
        Purchases.shared.presentCodeRedemptionSheet()
    }

    // MARK: Helpers

    private func apply(_ info: CustomerInfo) {
        isPro = info.entitlements[RevenueCatConfig.entitlementID]?.isActive == true
    }

    /// React to entitlement changes (renewals, expirations, cross-device restores).
    private func listenForCustomerInfo() {
        guard RevenueCatConfig.isConfigured else { return }
        Task {
            for await info in Purchases.shared.customerInfoStream {
                apply(info)
            }
        }
    }
}

private extension ProPlan {
    init(package: Package) {
        let product = package.storeProduct
        self.id = package.identifier
        self.title = product.localizedTitle.isEmpty ? package.identifier.capitalized : product.localizedTitle
        self.priceString = product.localizedPriceString
        self.isAnnual = package.packageType == .annual
        if let period = product.subscriptionPeriod {
            let unit: String
            switch period.unit {
            case .day:   unit = period.value == 1 ? "day" : "\(period.value) days"
            case .week:  unit = period.value == 1 ? "week" : "\(period.value) weeks"
            case .month: unit = period.value == 1 ? "month" : "\(period.value) months"
            case .year:  unit = period.value == 1 ? "year" : "\(period.value) years"
            @unknown default: unit = "period"
            }
            self.periodLabel = "\(product.localizedPriceString) / \(unit)"
        } else {
            self.periodLabel = product.localizedPriceString
        }
        // Free-trial intro offer, if eligible.
        if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
            let p = intro.subscriptionPeriod
            let unit: String
            switch p.unit {
            case .day:   unit = p.value == 1 ? "day" : "day"
            case .week:  unit = "week"
            case .month: unit = p.value == 1 ? "month" : "month"
            case .year:  unit = "year"
            @unknown default: unit = "day"
            }
            // e.g. "7-day free trial" / "1-week free trial"
            self.trialLabel = "\(p.value)-\(unit) free trial"
        } else {
            self.trialLabel = nil
        }
        self.package = package
    }
}
