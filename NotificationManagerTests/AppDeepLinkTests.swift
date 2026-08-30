import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import NotificationManagerWidgetSupport
import Testing

@testable import NotificationManager

@Suite("App Deep Link routing")
struct AppDeepLinkTests {
    @MainActor
    @Test func showListClearsEveryNavigationDestinationAndSelection() {
        let environment = AppEnvironment()
        let router = environment.router
        router.compactPath = [.settings]
        router.regularDestination = .notificationUnavailable
        router.selectedReminderID = Self.reminderID

        router.showList()

        #expect(router.compactPath.isEmpty)
        #expect(router.regularDestination == nil)
        #expect(router.selectedReminderID == nil)
    }

    @MainActor
    @Test func listDeepLinkReturnsToListWithoutPreparingAReminder() async {
        let preparation = DeepLinkReminderPreparationStub(result: nil)
        let environment = AppEnvironment(
            deepLinkReminderPreparation: { reminderID in
                await preparation.prepare(reminderID)
            }
        )
        environment.router.compactPath = [.settings]

        await environment.openDeepLink(.list)

        #expect(environment.router.compactPath.isEmpty)
        #expect(preparation.requestedIDs.isEmpty)
    }

    @MainActor
    @Test func existingReminderIsPreparedBeforeOpeningItsDetail() async {
        let preparation = DeepLinkReminderPreparationStub(
            result: Self.snapshot(title: "Fresh reminder")
        )
        let environment = AppEnvironment(
            deepLinkReminderPreparation: { reminderID in
                await preparation.prepare(reminderID)
            }
        )

        await environment.openDeepLink(.reminder(Self.reminderID))

        #expect(preparation.requestedIDs == [Self.reminderID])
        #expect(environment.router.compactPath == [.reminderEdit(Self.reminderID)])
        #expect(environment.router.selectedReminderID == Self.reminderID)
        #expect(environment.router.formModel(for: Self.reminderID)?.title == "Fresh reminder")
    }

    @MainActor
    @Test func missingReminderUsesUnavailableDestination() async {
        let preparation = DeepLinkReminderPreparationStub(result: nil)
        let environment = AppEnvironment(
            deepLinkReminderPreparation: { reminderID in
                await preparation.prepare(reminderID)
            }
        )

        await environment.openDeepLink(.reminder(Self.reminderID))

        #expect(preparation.requestedIDs == [Self.reminderID])
        #expect(environment.router.compactPath.last == .notificationUnavailable)
        #expect(environment.router.selectedReminderID == nil)
    }

    @MainActor
    @Test func warmLinkReplacesACleanCachedFormWithTheFreshSnapshot() async {
        let environment = AppEnvironment(
            deepLinkReminderPreparation: { _ in
                Self.snapshot(title: "Fresh reminder")
            }
        )
        let staleForm = Self.form(snapshot: Self.snapshot(title: "Stale reminder"))
        environment.router.register(form: staleForm)

        await environment.openDeepLink(.reminder(Self.reminderID))

        let openedForm = environment.router.formModel(for: Self.reminderID)
        #expect(openedForm !== staleForm)
        #expect(openedForm?.title == "Fresh reminder")
        #expect(environment.router.compactPath == [.reminderEdit(Self.reminderID)])
    }

    @MainActor
    @Test func warmLinkPreservesADirtyCachedFormWhileOpeningItsDetail() async {
        let environment = AppEnvironment(
            deepLinkReminderPreparation: { _ in
                Self.snapshot(title: "Fresh reminder")
            }
        )
        let editingForm = Self.form(snapshot: Self.snapshot(title: "Stale reminder"))
        editingForm.title = "Unsaved draft"
        environment.router.register(form: editingForm)

        await environment.openDeepLink(.reminder(Self.reminderID))

        #expect(environment.router.formModel(for: Self.reminderID) === editingForm)
        #expect(environment.router.formModel(for: Self.reminderID)?.title == "Unsaved draft")
        #expect(environment.router.compactPath == [.reminderEdit(Self.reminderID)])
    }

    private static let reminderID = UUID(
        uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    )!

    private static func snapshot(title: String) -> ReminderSnapshot {
        ReminderSnapshot(
            id: reminderID,
            title: title,
            notes: nil,
            urlString: nil,
            enabled: true,
            schedule: .corrupt(originalData: Data([0xff])),
            tagIDs: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }

    @MainActor
    private static func form(snapshot: ReminderSnapshot) -> ReminderFormModel {
        ReminderFormModel(
            snapshot: snapshot,
            savedRepeatPresentation: nil,
            now: Date(timeIntervalSince1970: 3),
            actions: ReminderFormActions(
                save: { draft, _, _ in .saved(draft.id) },
                delete: { _ in }
            )
        )
    }
}

@MainActor
private final class DeepLinkReminderPreparationStub {
    private(set) var requestedIDs: [UUID] = []

    private let result: ReminderSnapshot?

    init(result: ReminderSnapshot?) {
        self.result = result
    }

    func prepare(_ reminderID: UUID) async -> ReminderSnapshot? {
        requestedIDs.append(reminderID)
        return result
    }
}
