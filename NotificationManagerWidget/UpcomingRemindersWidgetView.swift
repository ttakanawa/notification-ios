import NotificationManagerWidgetSupport
import SwiftUI
import WidgetKit

struct UpcomingRemindersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let entry: UpcomingReminderEntry

    private let deepLinkCodec = PunctualDeepLinkCodec()

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                smallContent
                    .padding()
            }
        }
    }

    private var listURL: URL {
        deepLinkCodec.url(for: .list)
    }

    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader
            switch entry.state {
            case .events(let events):
                if let event = events.first {
                    Spacer(minLength: 0)
                    reminderContent(
                        event,
                        titleLineLimit: 3,
                        titleFont: .headline,
                        dateFont: .caption,
                        spacing: 4
                    )
                    Spacer(minLength: 0)
                } else {
                    stateContent(.noUpcoming)
                }
            case .noUpcoming:
                stateContent(.noUpcoming)
            case .refreshRequired:
                stateContent(.refreshRequired)
            case .unavailable:
                stateContent(.unavailable)
            }
        }
        .widgetURL(smallDestinationURL)
    }

    @ViewBuilder
    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            widgetHeader
            switch entry.state {
            case .events(let events):
                if events.isEmpty {
                    stateContent(.noUpcoming)
                } else {
                    ForEach(Array(events.prefix(mediumRowLimit)), id: \.self) { event in
                        if event != events.first {
                            Divider()
                        }
                        Link(destination: deepLinkCodec.url(for: .reminder(event.reminderID))) {
                            reminderContent(
                                event,
                                titleLineLimit: 1,
                                titleFont: .subheadline.weight(.semibold),
                                dateFont: .caption2,
                                spacing: 1
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            case .noUpcoming:
                stateContent(.noUpcoming)
            case .refreshRequired:
                stateContent(.refreshRequired)
            case .unavailable:
                stateContent(.unavailable)
            }
        }
        .widgetURL(listURL)
    }

    private var widgetHeader: some View {
        Label {
            Text(LocalizedStringResource("widget.header", table: "Widget"))
        } icon: {
            Image(systemName: "bell.fill")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .accessibilityElement(children: .combine)
    }

    private var smallDestinationURL: URL {
        guard case .events(let events) = entry.state, let event = events.first else {
            return listURL
        }
        return deepLinkCodec.url(for: .reminder(event.reminderID))
    }

    private var mediumRowLimit: Int {
        WidgetMediumRowLimit.maximum(for: widgetTextSizeTier)
    }

    private var widgetTextSizeTier: WidgetTextSizeTier {
        if dynamicTypeSize.isAccessibilitySize {
            .accessibility
        } else if dynamicTypeSize >= .xxLarge {
            .enlarged
        } else {
            .standard
        }
    }

    private func reminderContent(
        _ event: WidgetReminderEvent,
        titleLineLimit: Int,
        titleFont: Font,
        dateFont: Font,
        spacing: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(verbatim: event.title)
                .font(titleFont)
                .lineLimit(titleLineLimit)
                .layoutPriority(1)
            Text(
                event.fireDate,
                format: .dateTime.year().month(.abbreviated).day().hour().minute()
            )
            .font(dateFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: event.title))
        .accessibilityValue(
            Text(
                event.fireDate,
                format: .dateTime.year().month(.wide).day().weekday(.wide).hour().minute()
            )
        )
    }

    private func stateContent(_ state: UpcomingReminderWidgetState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: state.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(state.localizedMessage)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension UpcomingReminderWidgetState {
    fileprivate var localizedMessage: LocalizedStringResource {
        switch self {
        case .events:
            LocalizedStringResource("widget.state.no-upcoming", table: "Widget")
        case .noUpcoming:
            LocalizedStringResource("widget.state.no-upcoming", table: "Widget")
        case .refreshRequired:
            LocalizedStringResource("widget.state.refresh-required", table: "Widget")
        case .unavailable:
            LocalizedStringResource("widget.state.unavailable", table: "Widget")
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .events:
            "bell.slash"
        case .noUpcoming:
            "bell.slash"
        case .refreshRequired:
            "arrow.clockwise"
        case .unavailable:
            "exclamationmark.triangle"
        }
    }
}
