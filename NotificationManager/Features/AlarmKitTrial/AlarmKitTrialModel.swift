import Foundation
import Observation

enum AlarmKitTrialStatus: Sendable, Equatable {
    case idle
    case scheduled
    case cancelled
    case authorizationDenied
    case invalidInput
    case failed
}

@available(iOS 26.0, *)
@MainActor
@Observable
final class AlarmKitTrialModel {
    static let live = AlarmKitTrialModel(
        title: String(localized: "settings.alarmkit-trial.default-message", table: "Settings"))

    nonisolated static let alarmIDKey = "alarmkit-trial.alarm-id"
    nonisolated static let durationOptions = [10, 30, 60, 180]

    var title: String
    var durationSeconds = 30
    private(set) var isWorking = false
    private(set) var activeAlarmID: UUID?
    private(set) var nativePhase: AlarmKitTrialPhase?
    private(set) var status: AlarmKitTrialStatus = .idle

    @ObservationIgnored private let client: any AlarmKitTrialClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var schedulingAlarmID: UUID?

    init(
        title: String = "",
        client: any AlarmKitTrialClient = SystemAlarmKitTrialClient(),
        defaults: UserDefaults = .standard
    ) {
        self.title = title
        self.client = client
        self.defaults = defaults
        activeAlarmID = defaults.string(forKey: Self.alarmIDKey).flatMap(UUID.init(uuidString:))
        if activeAlarmID != nil { status = .scheduled }
    }

    func start() async {
        guard !isWorking else { return }
        let selectedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedDuration = durationSeconds
        guard !selectedTitle.isEmpty, Self.durationOptions.contains(selectedDuration) else {
            status = .invalidInput
            return
        }
        isWorking = true
        revision &+= 1
        let currentRevision = revision
        defer { isWorking = false }

        do {
            let authorization: AlarmKitTrialAuthorization
            if client.authorizationState == .notDetermined {
                authorization = try await client.requestAuthorization()
            } else {
                authorization = client.authorizationState
            }
            guard revision == currentRevision else { return }
            guard !Task.isCancelled else {
                status = .cancelled
                return
            }
            guard authorization == .authorized else {
                status = .authorizationDenied
                return
            }
            if let existingID = activeAlarmID {
                try cancelTrackedAlarm(existingID)
            }

            let alarmID = UUID()
            // Persist before awaiting the system so even an interrupted start can
            // later cancel its own trial without enumerating or cancelling others.
            setActiveAlarmID(alarmID)
            schedulingAlarmID = alarmID
            do {
                try await client.schedule(
                    id: alarmID, title: selectedTitle, durationSeconds: selectedDuration)
            } catch {
                schedulingAlarmID = nil
                do {
                    try cancelTrackedAlarm(alarmID)
                } catch {
                    // Retain the ID if cleanup fails so the Cancel action can retry.
                    status = .failed
                    return
                }
                if revision == currentRevision { status = .failed }
                return
            }
            schedulingAlarmID = nil
            guard revision == currentRevision, !Task.isCancelled else {
                try cancelTrackedAlarm(alarmID)
                if revision == currentRevision { status = .cancelled }
                return
            }
            nativePhase = try? client.phase(for: alarmID)
            status = .scheduled
        } catch {
            if revision == currentRevision || activeAlarmID != nil { status = .failed }
        }
    }

    func cancel() async {
        revision &+= 1
        // A pending schedule can finish after a cancellation. Let start() cancel
        // its result once the system has actually registered the new trial.
        if schedulingAlarmID != nil {
            status = .cancelled
            return
        }
        do {
            if let alarmID = activeAlarmID {
                try cancelTrackedAlarm(alarmID)
            }
            status = .cancelled
        } catch {
            status = .failed
        }
    }

    func refresh() async {
        guard !isWorking else { return }
        guard let alarmID = activeAlarmID else {
            nativePhase = nil
            return
        }
        guard client.authorizationState == .authorized else {
            nativePhase = nil
            status = .authorizationDenied
            return
        }
        do {
            if let phase = try client.phase(for: alarmID) {
                nativePhase = phase
                status = .scheduled
            } else {
                setActiveAlarmID(nil)
                status = .cancelled
            }
        } catch {
            nativePhase = nil
            status = .failed
        }
    }

    private func cancelTrackedAlarm(_ id: UUID) throws {
        try client.cancel(id: id)
        if activeAlarmID == id { setActiveAlarmID(nil) }
    }

    private func setActiveAlarmID(_ id: UUID?) {
        activeAlarmID = id
        nativePhase = nil
        if let id {
            defaults.set(id.uuidString, forKey: Self.alarmIDKey)
        } else {
            defaults.removeObject(forKey: Self.alarmIDKey)
        }
    }
}
