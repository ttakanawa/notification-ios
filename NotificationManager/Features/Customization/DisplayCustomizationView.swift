import NotificationManagerWidgetSupport
import SwiftUI

struct DisplayCustomizationView: View {
    @Bindable var purchase: DisplayCustomizationPurchaseModel
    @State var editor: DisplayCustomizationEditorModel
    var isGlobal = true
    @State private var confirmsReplacement = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            purchaseSection
            if editor.isLoading {
                ProgressView()
            } else if editor.isUnsupported {
                Section {
                    Text(resource("customization.unsupported"))
                    Button(resource("customization.replace"), role: .destructive) {
                        confirmsReplacement = true
                    }
                    .disabled(!purchase.isPurchased)
                }
            } else {
                templateSection(
                    name: "customization.notification", enabled: $editor.notificationEnabled,
                    title: $editor.notificationTitle, body: $editor.notificationBody,
                    allowsTimers: false)
                templateSection(
                    name: "customization.live-activity", enabled: $editor.liveActivityEnabled,
                    title: $editor.liveActivityTitle, body: $editor.liveActivityBody,
                    allowsTimers: true)
            }
            if let key = editor.errorKey {
                Section { Text(resource(key)).foregroundStyle(.red) }
            }
            Section {
                Text(
                    resource(isGlobal ? "customization.global-help" : "customization.reminder-help")
                )
                Text(resource("customization.privacy"))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle(Text(resource("customization.title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(resource("customization.save")) { Task { await editor.save() } }
                    .disabled(
                        !purchase.isPurchased || editor.isLoading || editor.isSaving
                            || editor.isUnsupported)
            }
        }
        .task {
            await editor.load()
            await purchase.load()
        }
        .onChange(of: editor.didSave) { _, saved in if saved { dismiss() } }
        .confirmationDialog(
            Text(resource("customization.replace-confirm")), isPresented: $confirmsReplacement
        ) {
            Button(resource("customization.replace"), role: .destructive) {
                editor.replaceUnsupported()
            }
        }
    }

    private var purchaseSection: some View {
        Section {
            if purchase.isChecking {
                ProgressView()
            } else if purchase.isPurchased {
                Label(resource("customization.purchased"), systemImage: "checkmark.seal")
            } else {
                Text(resource("customization.purchase-help"))
                if let product = purchase.product {
                    Button {
                        Task { await purchase.purchase() }
                    } label: {
                        HStack {
                            Text(verbatim: product.displayName)
                            Spacer()
                            Text(verbatim: product.displayPrice)
                        }
                    }
                } else {
                    Button(resource("customization.retry")) { Task { await purchase.load() } }
                }
            }
            Button(resource("customization.restore")) { Task { await purchase.restore() } }
            if purchase.isPending { Text(resource("customization.pending")) }
            if let issue = purchase.issue {
                Text(
                    resource(
                        issue == .unavailable
                            ? "customization.product-unavailable" : "customization.purchase-error")
                )
                .foregroundStyle(.red)
            }
        }
        .disabled(purchase.isWorking)
    }

    private func templateSection(
        name: String, enabled: Binding<Bool>, title: Binding<String>, body: Binding<String>,
        allowsTimers: Bool
    ) -> some View {
        Section {
            Toggle(resource("customization.use-template"), isOn: enabled)
            if enabled.wrappedValue {
                TextField(resource("customization.template-title"), text: title, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                fieldMenu(target: title, allowsTimers: allowsTimers)
                TextField(resource("customization.template-body"), text: body, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                fieldMenu(target: body, allowsTimers: allowsTimers)
                Menu {
                    Button(resource("customization.preset-title")) {
                        title.wrappedValue = "{title}"
                        body.wrappedValue = ""
                    }
                    Button(resource("customization.preset-details")) {
                        title.wrappedValue = "{title}"
                        body.wrappedValue = "{notes}\n{notificationTime} {timeZone}"
                    }
                } label: {
                    Label(resource("customization.presets"), systemImage: "list.bullet")
                }
                preview(
                    title: title.wrappedValue, body: body.wrappedValue, allowsTimers: allowsTimers)
            }
        } header: {
            Text(resource(name))
        }
        .disabled(!purchase.isPurchased || editor.isLoading || editor.isSaving)
    }

    private func fieldMenu(target: Binding<String>, allowsTimers: Bool) -> some View {
        Menu {
            ForEach(
                DisplayTemplateRenderer.fields
                    + (allowsTimers ? DisplayTemplateRenderer.timerFields : []), id: \.self
            ) { field in
                Button(fieldResource(field)) {
                    target.wrappedValue += "{\(field)}"
                }
            }
        } label: {
            Label(resource("customization.insert-field"), systemImage: "plus.circle")
        }
    }

    private func preview(title: String, body: String, allowsTimers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resource("customization.preview")).font(.caption).foregroundStyle(.secondary)
            if let title = try? DisplayTemplateRenderer.render(
                title, values: .preview, allowsTimers: allowsTimers),
                let body = try? DisplayTemplateRenderer.render(
                    body, values: .preview, allowsTimers: allowsTimers)
            {
                previewText(title).font(.headline)
                previewText(body).font(.subheadline)
            } else {
                Text(resource("customization.error.template")).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func previewText(_ segments: [DisplayTextSegment]) -> Text {
        Text(
            verbatim: segments.map { segment in
                switch segment.kind {
                case .text: segment.text
                case .remaining: "05:00"
                case .elapsed: "00:00"
                }
            }.joined())
    }

    private func fieldResource(_ field: String) -> LocalizedStringResource {
        switch field {
        case "notificationTime": resource("customization.field.notification-time")
        case "timeZone": resource("customization.field.time-zone")
        case "title": resource("customization.field.title")
        case "notes": resource("customization.field.notes")
        case "remaining": resource("customization.field.remaining")
        default: resource("customization.field.elapsed")
        }
    }

    private func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), table: "Customization")
    }
}

extension DisplayTemplateValues {
    fileprivate static var preview: Self { DisplayCustomizationEditorModel.previewValues }
}
