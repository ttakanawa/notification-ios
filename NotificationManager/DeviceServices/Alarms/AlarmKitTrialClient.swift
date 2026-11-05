import ActivityKit
@preconcurrency import AlarmKit
import Foundation
import NotificationManagerWidgetSupport
import SwiftUI

enum AlarmKitTrialAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

enum AlarmKitTrialPhase: Sendable, Equatable {
    case scheduled
    case countdown
    case paused
    case alerting
}

@available(iOS 26.0, *)
@MainActor
protocol AlarmKitTrialClient {
    var authorizationState: AlarmKitTrialAuthorization { get }
    func requestAuthorization() async throws -> AlarmKitTrialAuthorization
    func schedule(id: UUID, title: String, durationSeconds: Int) async throws
    func cancel(id: UUID) throws
    func phase(for id: UUID) throws -> AlarmKitTrialPhase?
}

@available(iOS 26.0, *)
@MainActor
struct SystemAlarmKitTrialClient: AlarmKitTrialClient {
    var authorizationState: AlarmKitTrialAuthorization {
        Self.authorization(AlarmManager.shared.authorizationState)
    }

    func requestAuthorization() async throws -> AlarmKitTrialAuthorization {
        Self.authorization(try await AlarmManager.shared.requestAuthorization())
    }

    func schedule(id: UUID, title: String, durationSeconds: Int) async throws {
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: TimeInterval(durationSeconds), attributes: Self.attributes(title: title),
            // No secondary button or intent: the trial cannot snooze or repeat.
            // This selects valid silent audio, not a system-supported mute mode.
            sound: .named(SystemReminderLiveActivityClient.scheduledStartSoundName))
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func attributes(title: String) -> AlarmAttributes<AlarmKitTrialMetadata> {
        let titleResource = LocalizedStringResource(stringLiteral: title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: titleResource)
        } else {
            alert = AlarmPresentation.Alert(
                title: titleResource,
                stopButton: AlarmButton(
                    text: LocalizedStringResource(
                        "settings.alarmkit-trial.stop", defaultValue: "Stop", table: "Settings"),
                    textColor: .white, systemImageName: "stop.fill"))
        }
        return AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(title: titleResource)),
            metadata: AlarmKitTrialMetadata(title: title),
            tintColor: .orange)
    }

    func cancel(id: UUID) throws {
        // A trial may already have been stopped in system UI. Never touch another
        // alarm and treat an absent trial as an already-completed cancellation.
        if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
            try AlarmManager.shared.cancel(id: id)
        }
    }

    func phase(for id: UUID) throws -> AlarmKitTrialPhase? {
        guard let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }) else {
            return nil
        }
        switch alarm.state {
        case .scheduled: return .scheduled
        case .countdown: return .countdown
        case .paused: return .paused
        case .alerting: return .alerting
        @unknown default: return .scheduled
        }
    }

    private static func authorization(
        _ value: AlarmManager.AuthorizationState
    ) -> AlarmKitTrialAuthorization {
        switch value {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}
