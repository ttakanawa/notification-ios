import SwiftUI

struct LiveActivityDurationPickerRow: View {
    let title: LocalizedStringResource
    let minutes: Int
    let valueText: String
    let accessibilityIdentifier: String
    let onSelect: (Int) -> Void

    @State private var isPresented = false
    @State private var draftHours = 0
    @State private var draftMinutes = 0

    var body: some View {
        Button {
            let value = min(max(minutes, 0), 480)
            draftHours = value / 60
            draftMinutes = value % 60
            isPresented = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(verbatim: valueText)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .layoutPriority(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(Text(minutes, format: .number))
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                HStack(spacing: 0) {
                    durationWheel(
                        title: LocalizedStringResource(
                            "reminder.form.duration.hours", table: "ReminderForm"),
                        selection: $draftHours,
                        values: 0...8,
                        identifier: "reminder-form.live-activity-duration.hours")
                    durationWheel(
                        title: LocalizedStringResource(
                            "reminder.form.duration.minutes", table: "ReminderForm"),
                        selection: $draftMinutes,
                        values: 0...(draftHours == 8 ? 0 : 59),
                        identifier: "reminder-form.live-activity-duration.minutes")
                }
                .onChange(of: draftHours) { _, hours in
                    if hours == 8 { draftMinutes = 0 }
                }
                .padding(.horizontal)
                .navigationTitle(Text(title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            isPresented = false
                        } label: {
                            Text(
                                LocalizedStringResource("reminder.action.cancel", table: "Reminder")
                            )
                        }
                        .accessibilityIdentifier("reminder-form.live-activity-duration.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSelect(min(draftHours * 60 + draftMinutes, 480))
                            isPresented = false
                        } label: {
                            Text(LocalizedStringResource("reminder.action.done", table: "Reminder"))
                        }
                        .accessibilityIdentifier("reminder-form.live-activity-duration.done")
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func durationWheel(
        title: LocalizedStringResource, selection: Binding<Int>, values: ClosedRange<Int>,
        identifier: String
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker(selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(value, format: .number).tag(value)
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
    }
}
