import Foundation
import Observation
import StoreKit

struct DisplayCustomizationProduct: Sendable, Equatable {
    let displayName: String
    let displayPrice: String
}

enum DisplayCustomizationPurchaseOutcome: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
}

enum DisplayCustomizationPurchaseIssue: Sendable, Equatable {
    case unavailable
    case purchaseFailed
    case restoreFailed
}

@MainActor
protocol DisplayCustomizationPurchasing {
    var updates: AsyncStream<Void> { get }
    func product() async throws -> DisplayCustomizationProduct
    func isPurchased() async -> Bool
    func purchase() async throws -> DisplayCustomizationPurchaseOutcome
    func restore() async throws
}

@MainActor
@Observable
final class DisplayCustomizationPurchaseModel {
    private(set) var isPurchased = false
    private(set) var isChecking = true
    private(set) var isWorking = false
    private(set) var isPending = false
    private(set) var product: DisplayCustomizationProduct?
    private(set) var issue: DisplayCustomizationPurchaseIssue?

    @ObservationIgnored private let service: any DisplayCustomizationPurchasing
    @ObservationIgnored private let entitlementChanged: @MainActor @Sendable () async -> Void
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var entitlementRevision: UInt64 = 0

    init(
        service: any DisplayCustomizationPurchasing = StoreKitDisplayCustomizationPurchases(),
        entitlementChanged: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.service = service
        self.entitlementChanged = entitlementChanged
    }

    deinit { observer?.cancel() }

    func start() {
        guard observer == nil else { return }
        let updates = service.updates
        observer = Task { [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await self?.refreshEntitlement()
            }
        }
    }

    func load() async {
        start()
        await refreshEntitlement()
        do {
            product = try await service.product()
            issue = nil
        } catch {
            product = nil
            issue = .unavailable
        }
    }

    func refreshEntitlement() async {
        entitlementRevision &+= 1
        let revision = entitlementRevision
        let purchased = await service.isPurchased()
        guard revision == entitlementRevision else { return }
        let changed = purchased != isPurchased || isChecking
        isPurchased = purchased
        isChecking = false
        if purchased { isPending = false }
        if changed { await entitlementChanged() }
    }

    func purchase() async {
        guard !isWorking, product != nil else { return }
        isWorking = true
        issue = nil
        defer { isWorking = false }
        do {
            switch try await service.purchase() {
            case .purchased:
                await refreshEntitlement()
            case .pending:
                isPending = true
            case .cancelled:
                break
            }
        } catch {
            issue = .purchaseFailed
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        issue = nil
        defer { isWorking = false }
        do {
            try await service.restore()
            await refreshEntitlement()
        } catch {
            issue = .restoreFailed
        }
    }
}

@MainActor
final class StoreKitDisplayCustomizationPurchases: DisplayCustomizationPurchasing {
    static let productID = "org.tknw.punctual.display_customization"

    let updates: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var transactionObserver: Task<Void, Never>?
    private var storeProduct: Product?

    init() {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        let continuation = continuation
        transactionObserver = Task {
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = verification,
                    transaction.productID == Self.productID
                else { continue }
                await transaction.finish()
                continuation.yield(())
            }
        }
    }

    deinit {
        transactionObserver?.cancel()
        continuation.finish()
    }

    func product() async throws -> DisplayCustomizationProduct {
        let product = try await resolveProduct()
        return DisplayCustomizationProduct(
            displayName: product.displayName, displayPrice: product.displayPrice)
    }

    func isPurchased() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                transaction.productID == Self.productID,
                transaction.productType == .nonConsumable,
                transaction.revocationDate == nil
            else { continue }
            return true
        }
        return false
    }

    func purchase() async throws -> DisplayCustomizationPurchaseOutcome {
        switch try await resolveProduct().purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result,
                transaction.productID == Self.productID,
                transaction.productType == .nonConsumable,
                transaction.revocationDate == nil
            else { throw StoreKitPurchaseError.unverified }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw StoreKitPurchaseError.unavailable
        }
    }

    func restore() async throws {
        // Only run in response to the user's explicit Restore action.
        try await AppStore.sync()
    }

    private func resolveProduct() async throws -> Product {
        if let storeProduct { return storeProduct }
        guard let product = try await Product.products(for: [Self.productID]).first,
            product.type == .nonConsumable
        else { throw StoreKitPurchaseError.unavailable }
        storeProduct = product
        return product
    }
}

private enum StoreKitPurchaseError: Error {
    case unavailable
    case unverified
}
