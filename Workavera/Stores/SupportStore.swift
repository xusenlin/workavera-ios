import Foundation
import Observation
import StoreKit

enum SupportProductID: String, CaseIterable, Identifiable, Sendable {
    case coffeeTip = "com.xusenlin.workavera.ios.tip.coffee"
    case generousTip = "com.xusenlin.workavera.ios.tip.generous"
    case sponsorTip = "com.xusenlin.workavera.ios.tip.sponsor"
    case lifetimeSupporter = "com.xusenlin.workavera.ios.supporter.lifetime"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coffeeTip:
            "Coffee"
        case .generousTip:
            "Generous Tip"
        case .sponsorTip:
            "Project Sponsor"
        case .lifetimeSupporter:
            "Lifetime Supporter"
        }
    }

    var systemImage: String {
        switch self {
        case .coffeeTip:
            "cup.and.saucer.fill"
        case .generousTip:
            "heart.fill"
        case .sponsorTip:
            "sparkles"
        case .lifetimeSupporter:
            "heart.circle.fill"
        }
    }

    static let tips: [SupportProductID] = [
        .coffeeTip,
        .generousTip,
        .sponsorTip,
    ]
}

enum SupportPurchaseOutcome: Equatable {
    case purchased(SupportProductID)
    case pending
    case cancelled
}

enum SupportPurchaseError: LocalizedError {
    case productUnavailable
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "This support option is not available from the App Store right now."
        case .verificationFailed:
            "The App Store purchase could not be verified."
        }
    }
}

/// App Store-backed supporter state. It intentionally has no dependency on a
/// Workavera server so the entitlement follows the purchaser's Apple Account.
@MainActor
@Observable
final class SupportStore {
    private(set) var isLifetimeSupporter = false
    private(set) var isLoadingProducts = false
    private(set) var purchasingProductID: SupportProductID?
    private(set) var products: [String: Product] = [:]

    private var hasStarted = false
    private var transactionUpdatesTask: Task<Void, Never>?

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        observeTransactionUpdates()

        async let productsTask: Void = loadProducts()
        async let entitlementsTask: Void = refreshEntitlements()
        _ = await (productsTask, entitlementsTask)
    }

    func product(for id: SupportProductID) -> Product? {
        products[id.rawValue]
    }

    func purchase(_ id: SupportProductID) async throws -> SupportPurchaseOutcome {
        guard let product = product(for: id) else {
            throw SupportPurchaseError.productUnavailable
        }

        purchasingProductID = id
        defer { purchasingProductID = nil }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SupportPurchaseError.verificationFailed
            }

            if id == .lifetimeSupporter {
                isLifetimeSupporter = true
            }
            await transaction.finish()
            return .purchased(id)

        case .pending:
            return .pending

        case .userCancelled:
            return .cancelled

        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: SupportProductID.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        } catch {
            // Product availability can be retried the next time this store starts.
            products = [:]
        }
    }

    private func refreshEntitlements() async {
        var hasLifetimeEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == SupportProductID.lifetimeSupporter.rawValue,
               transaction.revocationDate == nil {
                hasLifetimeEntitlement = true
            }
        }

        isLifetimeSupporter = hasLifetimeEntitlement
    }

    private func observeTransactionUpdates() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled,
                      case .verified(let transaction) = result,
                      SupportProductID(rawValue: transaction.productID) != nil
                else {
                    continue
                }

                if transaction.productID == SupportProductID.lifetimeSupporter.rawValue {
                    await self?.refreshEntitlements()
                }
                await transaction.finish()
            }
        }
    }
}
