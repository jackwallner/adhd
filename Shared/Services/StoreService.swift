import Foundation
import StoreKit

@preconcurrency import RevenueCat

enum RevenueCatConfig {
    static let publicSDKKey = "appl_GtGdULXDsTwthesMxYmHZOVeGjf"
    static let proEntitlement = "pro"
}

enum NextCueProduct {
    static let monthly = "com.jackwallner.adhd.monthly"
    static let yearly = "com.jackwallner.adhd.yearly"
    static let lifetime = "com.jackwallner.adhd.lifetime"
    static let all: Set<String> = [monthly, yearly, lifetime]
}

enum PurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case failed
}

enum PlanKind: Int, Comparable {
    case yearly
    case monthly
    case lifetime

    init(_ package: Package) {
        switch package.packageType {
        case .annual: self = .yearly
        case .monthly: self = .monthly
        default: self = .lifetime
        }
    }

    static func < (lhs: PlanKind, rhs: PlanKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension Package {
    var plan: PlanKind { PlanKind(self) }

    var billedLabel: String {
        let price = storeProduct.localizedPriceString
        switch plan {
        case .yearly: return "\(price) per year"
        case .monthly: return "\(price) per month"
        case .lifetime: return "\(price) once"
        }
    }

    var trialLabel: String? {
        guard let discount = storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value)-day free trial"
        case .week: return "\(period.value * 7)-day free trial"
        case .month: return "\(period.value)-month free trial"
        case .year: return "\(period.value)-year free trial"
        @unknown default: return nil
        }
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = StoreService()

    @Published private(set) var isPro = false
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var introEligibility: [String: Bool] = [:]
    @Published private(set) var introEligibilityResolved = false

    private static let cachedProKey = "nextCueCachedPro"
    private var isConfigured = false

    private override init() {
        super.init()
        isPro = UserDefaults.standard.bool(forKey: Self.cachedProKey)
    }

    var yearly: Package? { packages.first { $0.plan == .yearly } }
    var monthly: Package? { packages.first { $0.plan == .monthly } }
    var lifetime: Package? { packages.first { $0.plan == .lifetime } }

    func isEligibleForTrial(_ package: Package) -> Bool {
        package.trialLabel != nil && introEligibilityResolved &&
            (introEligibility[package.storeProduct.productIdentifier] ?? false)
    }

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") {
            setPro(true)
        }
        #endif
        configureIfNeeded()
        #if targetEnvironment(simulator)
        Task { await loadSimulatorProducts() }
        #else
        Task {
            await refreshStatus()
            await loadOffering()
        }
        #endif
    }

    func purchase(_ package: Package) async -> PurchaseOutcome {
        #if targetEnvironment(simulator)
        return await purchaseInStoreKit(package)
        #else
        guard isConfigured else {
            errorMessage = "Purchases are unavailable right now. Please try again."
            return .failed
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            update(customerInfo: result.customerInfo)
            if isPro { return .purchased }
            errorMessage = "Apple is still confirming this purchase. Pro will unlock when it completes."
            return .pending
        } catch {
            if (error as NSError).code == ErrorCode.purchaseCancelledError.rawValue {
                return .cancelled
            }
            errorMessage = "The purchase could not be completed. Please try again."
            return .failed
        }
        #endif
    }

    func restore() async {
        #if targetEnvironment(simulator)
        await restoreStoreKit()
        #else
        guard isConfigured else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            update(customerInfo: try await Purchases.shared.restorePurchases())
            errorMessage = isPro ? nil : "No Next Cue Pro purchase was found for this Apple Account."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
        #endif
    }

    func clearError() {
        errorMessage = nil
    }

    func trackPaywallImpression(id: String) {
        guard isConfigured else { return }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    #if DEBUG
    func setLocalOverride(isPro: Bool) {
        setPro(isPro)
    }
    #endif

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.update(customerInfo: customerInfo) }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        return
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.publicSDKKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }

    private func refreshStatus() async {
        guard isConfigured else { return }
        do {
            update(customerInfo: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
        } catch {
            errorMessage = "Purchase status could not be refreshed."
        }
    }

    private func loadOffering() async {
        guard isConfigured else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: "default") ?? offerings.current
            packages = (offering?.availablePackages ?? []).sorted { $0.plan < $1.plan }
            await refreshTrialEligibility()
        } catch {
            errorMessage = "Plans could not be loaded. Please try again."
        }
    }

    private func refreshTrialEligibility() async {
        let ids = packages.filter { $0.trialLabel != nil }
            .map(\.storeProduct.productIdentifier)
        guard !ids.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: ids
        )
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
    }

    private func update(customerInfo: CustomerInfo) {
        setPro(customerInfo.entitlements.active[RevenueCatConfig.proEntitlement] != nil)
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: Self.cachedProKey)
    }

    #if targetEnvironment(simulator)
    private func loadSimulatorProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let storeKitProducts = (try? await StoreKit.Product.products(for: NextCueProduct.all)) ?? []
        let products = storeKitProducts.isEmpty
            ? Self.fixtureProducts()
            : storeKitProducts.map { StoreProduct(sk2Product: $0) }
        packages = products.compactMap { product in
            let id = product.productIdentifier
            let kind: PackageType
            let key: String
            switch id {
            case NextCueProduct.yearly: (kind, key) = (.annual, "$rc_annual")
            case NextCueProduct.monthly: (kind, key) = (.monthly, "$rc_monthly")
            case NextCueProduct.lifetime: (kind, key) = (.lifetime, "$rc_lifetime")
            default: return nil
            }
            return Package(
                identifier: key,
                packageType: kind,
                storeProduct: product,
                offeringIdentifier: "default",
                webCheckoutUrl: nil
            )
        }.sorted { $0.plan < $1.plan }
        introEligibility = Dictionary(uniqueKeysWithValues: packages
            .filter { $0.trialLabel != nil }
            .map { ($0.storeProduct.productIdentifier, true) })
        introEligibilityResolved = true
    }

    private static func fixtureProducts() -> [StoreProduct] {
        let locale = Locale(identifier: "en_US")
        let trial = TestStoreProductDiscount(
            identifier: "one_week_free",
            price: 0,
            localizedPriceString: "$0.00",
            paymentMode: .freeTrial,
            subscriptionPeriod: .init(value: 1, unit: .week),
            numberOfPeriods: 1,
            type: .introductory
        )
        return [
            TestStoreProduct(
                localizedTitle: "Next Cue Pro Yearly",
                price: 14.99,
                currencyCode: "USD",
                localizedPriceString: "$14.99",
                productIdentifier: NextCueProduct.yearly,
                productType: .autoRenewableSubscription,
                localizedDescription: "Unlimited routines with separate schedules.",
                subscriptionPeriod: .init(value: 1, unit: .year),
                introductoryDiscount: trial,
                locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Next Cue Pro Monthly",
                price: 1.99,
                currencyCode: "USD",
                localizedPriceString: "$1.99",
                productIdentifier: NextCueProduct.monthly,
                productType: .autoRenewableSubscription,
                localizedDescription: "Unlimited routines with separate schedules.",
                subscriptionPeriod: .init(value: 1, unit: .month),
                introductoryDiscount: trial,
                locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Next Cue Pro Lifetime",
                price: 29.99,
                currencyCode: "USD",
                localizedPriceString: "$29.99",
                productIdentifier: NextCueProduct.lifetime,
                productType: .nonConsumable,
                localizedDescription: "Unlimited routines forever.",
                locale: locale
            ).toStoreProduct()
        ]
    }

    private func purchaseInStoreKit(_ package: Package) async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            guard let product = try await StoreKit.Product.products(
                for: [package.storeProduct.productIdentifier]
            ).first else { return .failed }
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { return .failed }
                await transaction.finish()
                setPro(true)
                return .purchased
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .failed
            }
        } catch {
            errorMessage = "The purchase could not be completed. Please try again."
            return .failed
        }
    }

    private func restoreStoreKit() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  NextCueProduct.all.contains(transaction.productID) else { continue }
            setPro(true)
            errorMessage = nil
            return
        }
        errorMessage = "No Next Cue Pro purchase was found for this Apple Account."
    }
    #endif
}
