import SwiftUI

struct OverlayView: View {
    let events: [CalendarEvent]
    let onOpenURL: (URL) -> Void
    let onSnooze: (Int) -> Void
    let onSkip: () -> Void

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
                            Text(events.count == 1 ? "予定が始まります" : "同時刻に始まる予定です")
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

                                Button("スキップ", action: onSkip)
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .keyboardShortcut(.escape, modifiers: [])
                                    .accessibilityLabel("この予定をスキップ")
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
