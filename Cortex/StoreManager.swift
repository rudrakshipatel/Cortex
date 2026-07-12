import Foundation
import RevenueCat

/// A simplified, view-friendly plan derived from a RevenueCat package.
struct ProPlan: Identifiable {
    let id: String            // RevenueCat package identifier
    let title: String
    let priceString: String   // e.g. "$4.99"
    let periodLabel: String   // e.g. "$4.99 / month"
    let isAnnual: Bool
    let trialLabel: String?   // e.g. "3-day free trial" if this plan has an intro offer
    /// A struck-through "original" price for the promo, from RevenueCat offering
    /// metadata (nil = show no strikethrough).
    let originalPrice: String?
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
    /// Whether the active subscription will auto-renew. False once the user has
    /// cancelled (they keep Pro until `proExpiration`).
    @Published private(set) var proWillRenew = false
    /// When the current Pro period ends.
    @Published private(set) var proExpiration: Date?
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
            let current = offerings.current
            let packages = current?.availablePackages ?? []
            // Promo "original" prices come from the offering's metadata, so they
            // can be changed in the RevenueCat dashboard without an app update.
            // Keys: "original_price_monthly", "original_price_annual".
            let meta = current?.metadata ?? [:]
            plans = packages
                .map { ProPlan(package: $0,
                               originalPrice: Self.originalPrice(for: $0, metadata: meta)) }
                .sorted { $0.package.storeProduct.price < $1.package.storeProduct.price }
            loadFailed = plans.isEmpty
        } catch {
            plans = []
            loadFailed = true
        }
    }

    /// The struck-through original price for a package, pulled from offering
    /// metadata by period (monthly / annual). Lifetime shows no strikethrough.
    private static func originalPrice(for package: Package, metadata: [String: Any]) -> String? {
        let key: String
        switch package.packageType {
        case .annual:  key = "original_price_annual"
        case .monthly: key = "original_price_monthly"
        default:       return nil
        }
        let value = metadata[key] as? String
        return (value?.isEmpty ?? true) ? nil : value
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

    /// Tie the RevenueCat identity to the signed-in Supabase user, so a
    /// server-side promotional grant (the referral reward) reaches the right
    /// account. Pass the Supabase uid on sign-in, or nil on sign-out.
    func identify(_ appUserID: String?) async {
        guard RevenueCatConfig.isConfigured else { return }
        do {
            if let id = appUserID, !id.isEmpty {
                let (info, _) = try await Purchases.shared.logIn(id)
                apply(info)
            } else if !Purchases.shared.isAnonymous {
                let info = try await Purchases.shared.logOut()
                apply(info)
            }
        } catch {
            // Non-fatal: entitlement still refreshes via customerInfoStream.
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
        let ent = info.entitlements[RevenueCatConfig.entitlementID]
        isPro = ent?.isActive == true
        proWillRenew = ent?.willRenew ?? false
        proExpiration = ent?.expirationDate
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
    init(package: Package, originalPrice: String?) {
        let product = package.storeProduct
        self.id = package.identifier
        self.isAnnual = package.packageType == .annual
        self.priceString = product.localizedPriceString
        self.originalPrice = originalPrice
        self.title = product.localizedTitle.isEmpty ? package.identifier.capitalized : product.localizedTitle
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
            case .day:   unit = "day"
            case .week:  unit = "week"
            case .month: unit = "month"
            case .year:  unit = "year"
            @unknown default: unit = "day"
            }
            // e.g. "3-day free trial" / "1-week free trial"
            self.trialLabel = "\(p.value)-\(unit) free trial"
        } else {
            self.trialLabel = nil
        }
        self.package = package
    }
}
