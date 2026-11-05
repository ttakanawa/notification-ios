import AlarmKit
import Foundation
import Testing

@testable import NotificationManager

@Suite("AlarmKit trial")
@MainActor
struct AlarmKitTrialModelTests {
    @Test func openingTheTrialNeverRequestsPermissionAndRestoresItsTrackedAlarm() throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        let alarmID = UUID()
        context.defaults.set(alarmID.uuidString, forKey: AlarmKitTrialModel.alarmIDKey)

        let restored = AlarmKitTrialModel(
            title: "Restored", client: context.client, defaults: context.defaults)

        #expect(context.client.authorizationRequests == 0)
        #expect(context.client.requests.isEmpty)
        #expect(restored.activeAlarmID == alarmID)
        #expect(restored.status == .scheduled)
    }

    @Test(arguments: [10, 30, 60, 180])
    func explicitStartRequestsPermissionAndSchedulesTheSelectedTrial(duration: Int) async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.model.title = "  Custom reminder  "
        context.model.durationSeconds = duration

        await context.model.start()

        let request = try #require(context.client.requests.first)
        #expect(context.client.authorizationRequests == 1)
        #expect(request.title == "Custom reminder")
        #expect(request.durationSeconds == duration)
        #expect(context.model.activeAlarmID == request.id)
        #expect(
            context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == request.id.uuidString)
        #expect(context.model.status == .scheduled)
        #expect(!context.model.isWorking)
    }

    @Test func deniedAuthorizationDoesNotCreateAnAlarmOrPromptAgain() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.authorizationState = .denied

        await context.model.start()

        #expect(context.client.authorizationRequests == 0)
        #expect(context.client.requests.isEmpty)
        #expect(context.model.status == .authorizationDenied)
        #expect(context.model.activeAlarmID == nil)
    }

    @Test func denyingThePermissionPromptLeavesNoTrial() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.authorizationResult = .denied

        await context.model.start()

        #expect(context.client.authorizationRequests == 1)
        #expect(context.client.requests.isEmpty)
        #expect(context.model.status == .authorizationDenied)
    }

    @Test func invalidInputDoesNotPromptOrSchedule() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.model.title = " \n "
        await context.model.start()
        #expect(context.model.status == .invalidInput)
        context.model.title = "Trial"
        context.model.durationSeconds = 0
        await context.model.start()

        #expect(context.client.authorizationRequests == 0)
        #expect(context.client.requests.isEmpty)
        #expect(context.model.status == .invalidInput)
    }

    @Test func replacementAndCancellationOnlyTouchThePersistedTrial() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.authorizationState = .authorized
        let previousTrial = UUID()
        let unrelatedAlarm = UUID()
        context.client.scheduledIDs = [previousTrial, unrelatedAlarm]
        context.defaults.set(previousTrial.uuidString, forKey: AlarmKitTrialModel.alarmIDKey)
        let restored = AlarmKitTrialModel(
            title: "Replacement", client: context.client, defaults: context.defaults)

        await restored.start()
        let replacement = try #require(restored.activeAlarmID)
        #expect(context.client.cancelledIDs == [previousTrial])
        #expect(context.client.scheduledIDs == [replacement, unrelatedAlarm])
        await restored.cancel()

        #expect(context.client.cancelledIDs == [previousTrial, replacement])
        #expect(context.client.scheduledIDs == [unrelatedAlarm])
        #expect(context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == nil)
        #expect(restored.activeAlarmID == nil)
        #expect(restored.status == .cancelled)
    }

    @Test func failedCancellationRetainsTheTrialForARetry() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        await context.model.start()
        let alarmID = try #require(context.model.activeAlarmID)
        context.client.cancellationFails = true

        await context.model.cancel()

        #expect(context.model.status == .failed)
        #expect(context.model.activeAlarmID == alarmID)
        #expect(
            context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == alarmID.uuidString)
        context.client.cancellationFails = false
        await context.model.cancel()
        #expect(context.model.activeAlarmID == nil)
        #expect(context.model.status == .cancelled)
    }

    @Test func permissionAndSchedulingErrorsHaveStableFailureStates() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.authorizationFails = true
        await context.model.start()
        #expect(context.model.status == .failed)
        #expect(context.client.requests.isEmpty)
        context.client.authorizationFails = false
        context.client.schedulingFails = true
        await context.model.start()

        #expect(context.model.status == .failed)
        #expect(context.model.activeAlarmID == nil)
        #expect(context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == nil)
        #expect(!context.model.isWorking)
    }

    @Test func trialAttributesUseTheCustomTitleWithoutSnoozeOrPauseControls() throws {
        guard #available(iOS 26.0, *) else { return }
        let title = "Custom trial reminder"

        let attributes = SystemAlarmKitTrialClient.attributes(title: title)
        let countdown = try #require(attributes.presentation.countdown)

        #expect(attributes.metadata?.title == title)
        #expect(String(localized: attributes.presentation.alert.title) == title)
        #expect(String(localized: countdown.title) == title)
        #expect(attributes.presentation.alert.secondaryButton == nil)
        #expect(attributes.presentation.alert.secondaryButtonBehavior == nil)
        #expect(countdown.pauseButton == nil)
        #expect(attributes.presentation.paused == nil)
    }

    @Test(arguments: [
        AlarmKitTrialPhase.scheduled, .countdown, .paused, .alerting
    ])
    func refreshReadsTheTrackedNativePhaseWithoutRequestingPermission(
        phase: AlarmKitTrialPhase
    ) async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        let alarmID = UUID()
        context.client.authorizationState = .authorized
        context.client.scheduledIDs = [alarmID, UUID()]
        context.client.currentPhase = phase
        context.defaults.set(alarmID.uuidString, forKey: AlarmKitTrialModel.alarmIDKey)
        let restored = AlarmKitTrialModel(
            title: "Restored", client: context.client, defaults: context.defaults)

        await restored.refresh()

        #expect(restored.nativePhase == phase)
        #expect(restored.status == .scheduled)
        #expect(restored.activeAlarmID == alarmID)
        #expect(context.client.phaseQueries == [alarmID])
        #expect(context.client.authorizationRequests == 0)
    }

    @Test func refreshClearsAnAlarmThatWasStoppedOutsideTheApp() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        await context.model.start()
        context.client.scheduledIDs.removeAll()

        await context.model.refresh()

        #expect(context.model.activeAlarmID == nil)
        #expect(context.model.nativePhase == nil)
        #expect(context.model.status == .cancelled)
        #expect(context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == nil)
    }

    @Test func refreshRetainsTheTrackedAlarmWhenAuthorizationOrTheQueryFails() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        await context.model.start()
        let alarmID = try #require(context.model.activeAlarmID)
        let requestsBeforeRefresh = context.client.authorizationRequests
        context.client.authorizationState = .denied

        await context.model.refresh()
        #expect(context.model.status == .authorizationDenied)
        #expect(context.model.activeAlarmID == alarmID)
        #expect(context.model.nativePhase == nil)
        #expect(context.client.authorizationRequests == requestsBeforeRefresh)

        context.client.authorizationState = .authorized
        context.client.phaseQueryFails = true
        await context.model.refresh()
        #expect(context.model.status == .failed)
        #expect(context.model.activeAlarmID == alarmID)
        #expect(
            context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == alarmID.uuidString)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentStartsAreIgnoredAndThePermissionWaitKeepsTheOriginalInputs() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.suspendsAuthorization = true
        let start = Task { await context.model.start() }
        while context.client.authorizationRequests == 0 { await Task.yield() }
        context.model.title = "Changed while waiting"
        context.model.durationSeconds = 180

        await context.model.start()
        #expect(context.model.isWorking)
        #expect(context.client.authorizationRequests == 1)
        context.client.resumeAuthorization()
        await start.value

        #expect(context.client.requests.count == 1)
        #expect(context.client.requests.first?.title == "Trial")
        #expect(context.client.requests.first?.durationSeconds == 30)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationWhilePermissionIsPendingNeverCreatesAnAlarm() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.suspendsAuthorization = true
        let start = Task { await context.model.start() }
        while context.client.authorizationRequests == 0 { await Task.yield() }

        await context.model.cancel()
        context.client.resumeAuthorization()
        await start.value

        #expect(context.client.requests.isEmpty)
        #expect(context.model.status == .cancelled)
        #expect(!context.model.isWorking)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationWhileSchedulingRemovesTheLateSystemResult() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.suspendsScheduling = true
        let start = Task { await context.model.start() }
        while context.client.requests.isEmpty { await Task.yield() }
        let pendingID = try #require(context.client.requests.first?.id)
        #expect(
            context.defaults.string(forKey: AlarmKitTrialModel.alarmIDKey) == pendingID.uuidString)

        await context.model.refresh()
        #expect(context.client.phaseQueries.isEmpty)
        #expect(context.model.activeAlarmID == pendingID)

        await context.model.cancel()
        context.client.resumeScheduling()
        await start.value

        #expect(context.client.cancelledIDs == [pendingID])
        #expect(context.client.scheduledIDs.isEmpty)
        #expect(context.model.activeAlarmID == nil)
        #expect(context.model.status == .cancelled)
        #expect(!context.model.isWorking)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheCallingTaskAlsoRemovesItsLateAlarm() async throws {
        guard #available(iOS 26.0, *) else { return }
        let context = try makeContext()
        context.client.suspendsScheduling = true
        let start = Task { await context.model.start() }
        while context.client.requests.isEmpty { await Task.yield() }

        start.cancel()
        context.client.resumeScheduling()
        await start.value

        #expect(context.client.cancelledIDs.count == 1)
        #expect(context.client.scheduledIDs.isEmpty)
        #expect(context.model.activeAlarmID == nil)
        #expect(context.model.status == .cancelled)
    }

    @available(iOS 26.0, *)
    private func makeContext() throws -> AlarmKitTrialTestContext {
        let defaults = try #require(
            UserDefaults(suiteName: "alarmkit-trial-tests.\(UUID().uuidString)"))
        let client = RecordingAlarmKitTrialClient()
        return AlarmKitTrialTestContext(
            defaults: defaults, client: client,
            model: AlarmKitTrialModel(title: "Trial", client: client, defaults: defaults))
    }
}

@available(iOS 26.0, *)
@MainActor
private struct AlarmKitTrialTestContext {
    let defaults: UserDefaults
    let client: RecordingAlarmKitTrialClient
    let model: AlarmKitTrialModel
}

@available(iOS 26.0, *)
@MainActor
private final class RecordingAlarmKitTrialClient: AlarmKitTrialClient {
    var authorizationState: AlarmKitTrialAuthorization = .notDetermined
    var authorizationResult: AlarmKitTrialAuthorization = .authorized
    var authorizationFails = false
    var schedulingFails = false
    var cancellationFails = false
    var phaseQueryFails = false
    var currentPhase: AlarmKitTrialPhase = .countdown
    var suspendsAuthorization = false
    var suspendsScheduling = false
    var scheduledIDs: Set<UUID> = []
    private(set) var authorizationRequests = 0
    private(set) var requests: [TrialRequest] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var phaseQueries: [UUID] = []
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var schedulingContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> AlarmKitTrialAuthorization {
        authorizationRequests += 1
        if suspendsAuthorization {
            await withCheckedContinuation { authorizationContinuation = $0 }
        }
        if authorizationFails { throw TrialError.failed }
        authorizationState = authorizationResult
        return authorizationResult
    }

    func schedule(id: UUID, title: String, durationSeconds: Int) async throws {
        requests.append(TrialRequest(id: id, title: title, durationSeconds: durationSeconds))
        if suspendsScheduling {
            await withCheckedContinuation { schedulingContinuation = $0 }
        }
        if schedulingFails { throw TrialError.failed }
        scheduledIDs.insert(id)
    }

    func cancel(id: UUID) throws {
        cancelledIDs.append(id)
        if cancellationFails { throw TrialError.failed }
        scheduledIDs.remove(id)
    }

    func phase(for id: UUID) throws -> AlarmKitTrialPhase? {
        phaseQueries.append(id)
        if phaseQueryFails { throw TrialError.failed }
        return scheduledIDs.contains(id) ? currentPhase : nil
    }

    func resumeAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func resumeScheduling() {
        schedulingContinuation?.resume()
        schedulingContinuation = nil
    }

    struct TrialRequest {
        let id: UUID
        let title: String
        let durationSeconds: Int
    }

    private enum TrialError: Error { case failed }
}
