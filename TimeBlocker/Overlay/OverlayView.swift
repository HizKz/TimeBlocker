import SwiftUI

struct OverlayView: View {
    let events: [CalendarEvent]
    var notionTasks: [NotionTask] = []
    var notionError: String? = nil
    let onOpenURL: (URL) -> Void
    let onSnooze: (Int) -> Void
    let onSkip: () -> Void
    var onCompleteNotionTask: (String) -> Void = { _ in }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 28) {
                            Text(!notionTasks.isEmpty ? "Notionタスクの期限です" : (events.count == 1 ? "予定が始まります" : "同時刻に始まる予定です"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))

                            VStack(spacing: 0) {
                                ForEach(events) { event in
                                    EventContent(event: event, onOpenURL: onOpenURL)
                                        .padding(.vertical, 28)

                                    if event.id != events.last?.id {
                                        Divider()
                                            .overlay(.white.opacity(0.14))
                                            .frame(maxWidth: 430)
                                    }
                                }
                            }

                            if !notionTasks.isEmpty {
                                VStack(spacing: 12) {
                                    if let notionError {
                                        Text(notionError).font(.caption).foregroundStyle(.red.opacity(0.95)).frame(maxWidth: 600, alignment: .leading)
                                    }
                                    ForEach(notionTasks) { task in
                                        HStack(spacing: 12) {
                                            Button { onCompleteNotionTask(task.id) } label: {
                                                Image(systemName: "checkmark.circle")
                                                    .font(.title2)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("\(task.title)を完了")
                                            Button { onOpenURL(task.url) } label: {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text(task.title).font(.title3.weight(.medium)).multilineTextAlignment(.leading)
                                                    if let dueAt = task.dueAt { Text(dueAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.white.opacity(0.65)) }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            Image(systemName: "arrow.up.right.square").foregroundStyle(.white.opacity(0.55))
                                        }
                                        .padding(14)
                                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .frame(maxWidth: 600)
                            }

                            HStack(spacing: 12) {
                                Menu {
                                    ForEach([5, 10, 15], id: \.self) { minutes in
                                        Button("\(minutes)分後に再通知") {
                                            onSnooze(minutes)
                                        }
                                    }
                                } label: {
                                    Label("あとで通知", systemImage: "clock")
                                }
                                .menuStyle(.borderlessButton)
                                .buttonStyle(.bordered)
                                .controlSize(.large)

                                Button("通知を閉じる", action: onSkip)
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .keyboardShortcut(.escape, modifiers: [])
                                    .accessibilityLabel("通知を閉じる")
                            }
                        }
                        .frame(maxWidth: 660)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 48)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventContent: View {
    let event: CalendarEvent
    let onOpenURL: (URL) -> Void

    private var links: [EventLinkAction] {
        EventLinkResolver.actions(for: event)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(calendarHex: event.calendarColorHex))
                    .frame(width: 8, height: 8)
                Text(event.isAllDay ? "終日" : event.timeRange)
                    .font(.system(size: 17, weight: .medium, design: .default).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
            }

            Text(event.title)
                .font(.system(size: 42, weight: .semibold, design: .default))
                .tracking(-1.1)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !links.isEmpty {
                VStack(spacing: 10) {
                    ForEach(links) { link in
                        Button {
                            onOpenURL(link.url)
                        } label: {
                            Label(link.title, systemImage: link.symbol)
                                .frame(maxWidth: 320)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel(link.title)
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
