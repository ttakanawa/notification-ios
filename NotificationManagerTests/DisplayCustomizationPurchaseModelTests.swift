import Testing

@testable import NotificationManager

@MainActor
struct DisplayCustomizationPurchaseModelTests {
    @Test func anOlderEntitlementQueryCannotOverwriteANewerStoreUpdate() async {
        let service = FakeDisplayCustomizationPurchases()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var calls = 0
        service.entitlement = {
            calls += 1
            if calls == 1 {
                didStart.yield(())
                var iterator = release.makeAsyncIterator()
                _ = await iterator.next()
                return false
            }
            return true
        }
        let model = DisplayCustomizationPurchaseModel(service: service)
        let old = Task { await model.refreshEntitlement() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        await model.refreshEntitlement()
        resume.yield(())
        await old.value
        #expect(model.isPurchased)
        didStart.finish()
        resume.finish()
    }

    @Test func loadingUsesVerifiedStoreEntitlementAndLocalizedPrice() async {
        let service = FakeDisplayCustomizationPurchases()
        service.purchased = true
        let model = DisplayCustomizationPurchaseModel(service: service)

        await model.load()

        #expect(model.isPurchased)
        #expect(!model.isChecking)
        #expect(model.product?.displayPrice == "¥600")
    }

    @Test func pendingPurchaseDoesNotUnlockCustomization() async {
        let service = FakeDisplayCustomizationPurchases()
        service.outcome = .pending
        let model = DisplayCustomizationPurchaseModel(service: service)
        await model.load()

        await model.purchase()

        #expect(model.isPending)
        #expect(!model.isPurchased)
        #expect(!model.isWorking)
    }

    @Test func cancellationIsNotAnErrorOrAnEntitlement() async {
        let service = FakeDisplayCustomizationPurchases()
        service.outcome = .cancelled
        let model = DisplayCustomizationPurchaseModel(service: service)
        await model.load()

        await model.purchase()

        #expect(!model.isPurchased)
        #expect(model.issue == nil)
    }

    @Test func purchaseAndRevocationRefreshPresentationWithoutDeletingPreferences() async {
        let service = FakeDisplayCustomizationPurchases()
        var changes = 0
        let model = DisplayCustomizationPurchaseModel(
            service: service, entitlementChanged: { changes += 1 })
        await model.load()
        await model.purchase()
        #expect(model.isPurchased)

        service.purchased = false
        await model.refreshEntitlement()

        #expect(!model.isPurchased)
        #expect(changes == 3)
    }

    @Test func restoreRunsOnlyWhenRequested() async {
        let service = FakeDisplayCustomizationPurchases()
        let model = DisplayCustomizationPurchaseModel(service: service)
        await model.load()
        #expect(service.restoreCalls == 0)

        await model.restore()

        #expect(service.restoreCalls == 1)
        #expect(model.isPurchased)
    }
}

@MainActor
private final class FakeDisplayCustomizationPurchases: DisplayCustomizationPurchasing {
    let updates = AsyncStream<Void> { _ in }
    var purchased = false
    var outcome = DisplayCustomizationPurchaseOutcome.purchased
    private(set) var restoreCalls = 0
    var entitlement: (@MainActor () async -> Bool)?

    func product() -> DisplayCustomizationProduct {
        DisplayCustomizationProduct(displayName: "Display customization", displayPrice: "¥600")
    }

    func isPurchased() async -> Bool {
        if let entitlement { return await entitlement() }
        return purchased
    }

    func purchase() -> DisplayCustomizationPurchaseOutcome {
        if case .purchased = outcome { purchased = true }
        return outcome
    }

    func restore() {
        restoreCalls += 1
        purchased = true
    }
}
