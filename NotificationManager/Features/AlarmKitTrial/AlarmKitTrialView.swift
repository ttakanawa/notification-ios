import SwiftUI

@available(iOS 26.0, *)
struct AlarmKitTrialView: View {
    @State private var model: AlarmKitTrialModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _model = State(initialValue: .live)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    AppSymbolTile(systemName: "alarm.fill", color: .orange)
                    Text(
                        LocalizedStringResource(
                            "settings.alarmkit-trial.description", table: "Settings")
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } footer: {
                Text(
                    LocalizedStringResource("settings.alarmkit-trial.sound-note", table: "Settings")
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                TextField(
                    LocalizedStringResource("settings.alarmkit-trial.message", table: "Settings"),
                    text: $model.title
                )
                .accessibilityIdentifier("alarmkit-trial.message")
                Picker(
                    LocalizedStringResource("settings.alarmkit-trial.duration", table: "Settings"),
                    selection: $model.durationSeconds
                ) {
                    ForEach(AlarmKitTrialModel.durationOptions, id: \.self) { seconds in
                        Text(
                            Duration.seconds(seconds),
                            format: .units(allowed: [.seconds], width: .wide)
                        )
                        .tag(seconds)
                    }
                }
                .accessibilityIdentifier("alarmkit-trial.duration")
            }
            .disabled(model.isWorking)

            Section {
                Button {
                    Task { await model.start() }
                } label: {
                    AppRowLabel(
                        title: LocalizedStringResource(
                            "settings.alarmkit-trial.start", table: "Settings"),
                        systemImage: "timer", color: .blue)
                }
                .disabled(
                    model.isWorking
                        || model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("alarmkit-trial.start")

                Button(role: .destructive) {
                    Task { await model.cancel() }
                } label: {
                    AppRowLabel(
                        title: LocalizedStringResource(
                            "settings.alarmkit-trial.cancel", table: "Settings"),
                        systemImage: "stop.fill", color: .red)
                }
                .disabled(!model.isWorking && model.activeAlarmID == nil)
                .accessibilityIdentifier("alarmkit-trial.cancel")
            }

            Section {
                HStack {
                    if model.isWorking { ProgressView() }
                    Text(statusResource)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("alarmkit-trial.status")
                }
                if let phaseResource {
                    Text(phaseResource)
                        .accessibilityIdentifier("alarmkit-trial.native-phase")
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Text(
                        LocalizedStringResource(
                            "settings.alarmkit-trial.refresh-state", table: "Settings"))
                }
                .disabled(model.isWorking || model.activeAlarmID == nil)
                .accessibilityIdentifier("alarmkit-trial.refresh")
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(
            LocalizedStringResource("settings.alarmkit-trial.title", table: "Settings")
        )
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("alarmkit-trial.root")
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private var phaseResource: LocalizedStringResource? {
        switch model.nativePhase {
        case .scheduled:
            LocalizedStringResource("settings.alarmkit-trial.phase.scheduled", table: "Settings")
        case .countdown:
            LocalizedStringResource("settings.alarmkit-trial.phase.countdown", table: "Settings")
        case .paused:
            LocalizedStringResource("settings.alarmkit-trial.phase.paused", table: "Settings")
        case .alerting:
            LocalizedStringResource("settings.alarmkit-trial.phase.alerting", table: "Settings")
        case nil:
            nil
        }
    }

    private var statusResource: LocalizedStringResource {
        switch model.status {
        case .idle:
            LocalizedStringResource("settings.alarmkit-trial.status.idle", table: "Settings")
        case .scheduled:
            LocalizedStringResource("settings.alarmkit-trial.status.scheduled", table: "Settings")
        case .cancelled:
            LocalizedStringResource("settings.alarmkit-trial.status.cancelled", table: "Settings")
        case .authorizationDenied:
            LocalizedStringResource("settings.alarmkit-trial.status.denied", table: "Settings")
        case .invalidInput:
            LocalizedStringResource(
                "settings.alarmkit-trial.status.invalid-input", table: "Settings")
        case .failed:
            LocalizedStringResource("settings.alarmkit-trial.status.failed", table: "Settings")
        }
    }
}
