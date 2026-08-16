import Foundation
import SwiftUI

struct ScheduleDatePickerRow: View {
    let title: LocalizedStringResource
    let selection: Date?
    let fallbackSelection: Date
    let displayedComponents: DatePickerComponents
    let timeZone: TimeZone
    let accessibilityIdentifier: String
    let accessibilityValue: String?
    let onSelect: (Date) -> Void

    @State private var isPickerPresented = false
    @State private var draftSelection: Date

    init(
        title: LocalizedStringResource,
        selection: Date?,
        fallbackSelection: Date,
        displayedComponents: DatePickerComponents,
        timeZone: TimeZone,
        accessibilityIdentifier: String,
        accessibilityValue: String? = nil,
        onSelect: @escaping (Date) -> Void
    ) {
        self.title = title
        self.selection = selection
        self.fallbackSelection = fallbackSelection
        self.displayedComponents = displayedComponents
        self.timeZone = timeZone
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityValue = accessibilityValue
        self.onSelect = onSelect
        _draftSelection = State(initialValue: fallbackSelection)
    }

    var body: some View {
        Group {
            if let selection {
                DatePicker(
                    selection: Binding(
                        get: { selection },
                        set: { value in onSelect(value) }
                    ),
                    displayedComponents: displayedComponents
                ) {
                    Text(title)
                }
                .datePickerStyle(.compact)
                .environment(\.timeZone, timeZone)
                .background {
                    AccessibilityIdentifierContainer(
                        identifier: accessibilityIdentifier,
                        value: accessibilityValue
                    )
                }
            } else {
                LabeledContent {
                    Button {
                        draftSelection = fallbackSelection
                        isPickerPresented = true
                    } label: {
                        Text(
                            LocalizedStringResource(
                                "reminder.form.value.select",
                                table: "ReminderForm"
                            ))
                    }
                    .accessibilityIdentifier(accessibilityIdentifier)
                } label: {
                    Text(title)
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                DatePicker(
                    selection: $draftSelection,
                    displayedComponents: displayedComponents
                ) {
                    Text(title)
                }
                .environment(\.timeZone, timeZone)
                .padding()
                .navigationTitle(Text(title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            isPickerPresented = false
                        } label: {
                            Text(
                                LocalizedStringResource(
                                    "reminder.action.cancel",
                                    table: "Reminder"
                                ))
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            let selectedValue = draftSelection
                            isPickerPresented = false
                            onSelect(selectedValue)
                        } label: {
                            Text(
                                LocalizedStringResource(
                                    "reminder.action.done",
                                    table: "Reminder"
                                ))
                        }
                    }
                }
            }
        }
    }
}
