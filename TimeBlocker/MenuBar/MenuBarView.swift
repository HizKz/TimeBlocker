import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(statusTitle)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(statusTitle)
    }

    private var statusTitle: String {
        guard let event = model.nextEvent else {
            return model.hasCalendarAccess ? "予定なし" : "カレンダー未接続"
        }

        let time = event.startAt.formatted(date: .omitted, time: .shortened)
        let title = String(event.title.prefix(24))
        return "\(time)  \(title)"
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var isAddingEvent = false

    private var todayEvents: [CalendarEvent] {
        model.upcomingEvents.filter { Calendar.current.isDateInToday($0.startAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("予定")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAddingEvent.toggle()
                    }
                } label: {
                    Label(isAddingEvent ? "閉じる" : "予定を追加", systemImage: isAddingEvent ? "xmark" : "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isAddingEvent {
                QuickAddEventForm(model: model, isPresented: $isAddingEvent)
                Divider()
            }

            if let event = model.nextEvent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("次の予定").font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.headline).lineLimit(2)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(calendarHex: event.calendarColorHex))
                            .frame(width: 7, height: 7)
                        Text(event.timeRange).font(.subheadline.monospacedDigit())
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = max(0, Int(event.startAt.timeIntervalSince(timeline.date)))
                        Text("あと \(remaining / 3600)時間 \((remaining % 3600) / 60)分")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(model.hasCalendarAccess ? "今後の予定はありません" : model.permissionMessage)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.hasCalendarAccess {
                    Button("カレンダーへのアクセスを許可") {
                        Task { await model.requestCalendarAccess() }
                    }
                    .buttonStyle(.link)
                }
            }

            Divider()
            Text("今日の予定").font(.caption).foregroundStyle(.secondary)
            if todayEvents.isEmpty {
                Text("予定はありません").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(5)) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Circle()
                            .fill(Color(calendarHex: event.calendarColorHex))
                            .frame(width: 7, height: 7)
                        Text(event.timeRange.components(separatedBy: " – ").first ?? "")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(event.title).font(.caption).lineLimit(1)
                    }
                }
            }

            Divider()
            SettingsLink { Label("設定…", systemImage: "gearshape") }
            Button("10秒後に通知をテスト") { model.scheduleTestNotification() }
            Button("TimeBlockerを終了") { model.quit() }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

private struct QuickAddEventForm: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var location = ""
    @State private var urlText = ""
    @State private var startAt = Self.defaultStartTime()
    @State private var durationMinutes = 30
    @State private var calendarIdentifier = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var titleIsFocused: Bool

    private let durations = [15, 30, 45, 60, 90, 120]

    private var writableCalendars: [CalendarChoice] {
        model.writableCalendars
    }

    private var selectedCalendar: CalendarChoice? {
        writableCalendars.first(where: { $0.id == calendarIdentifier })
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
            && !writableCalendars.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField("予定名", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onSubmit(save)

            TextField("場所（任意）", text: $location)
                .textFieldStyle(.roundedBorder)

            TextField("URL / 会議リンク（任意）", text: $urlText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("開始")
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker(
                    "開始",
                    selection: $startAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.field)
            }

            HStack {
                Text("所要時間")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("所要時間", selection: $durationMinutes) {
                    ForEach(durations, id: \.self) { minutes in
                        Text("\(minutes)分").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if !writableCalendars.isEmpty {
                HStack {
                    Text("保存先")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(selection: $calendarIdentifier) {
                        ForEach(writableCalendars) { calendar in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Color(calendarHex: calendar.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(calendar.title)
                            }
                            .tag(calendar.id)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(calendarHex: selectedCalendar?.colorHex))
                                .frame(width: 8, height: 8)
                            Text(selectedCalendar?.title ?? "カレンダーを選択")
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else if model.hasCalendarAccess {
                Text("書き込み可能なカレンダーがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !model.hasCalendarAccess {
                    Button("アクセスを許可") {
                        Task { await model.requestCalendarAccess() }
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button("追加") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.vertical, 3)
        .onAppear {
            chooseDefaultCalendar()
            titleIsFocused = true
        }
        .onChange(of: model.calendars) { _, _ in chooseDefaultCalendar() }
    }

    private func chooseDefaultCalendar() {
        guard calendarIdentifier.isEmpty else { return }
        durationMinutes = model.quickAddDefaultDurationMinutes
        calendarIdentifier = writableCalendars.first(where: { $0.id == model.quickAddCalendarIdentifier })?.id
            ?? writableCalendars.first(where: { $0.id == model.defaultCalendarIdentifier })?.id
            ?? writableCalendars.first?.id
            ?? ""
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSaving else { return }

        let cleanURLText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventURL: URL?
        if cleanURLText.isEmpty {
            eventURL = nil
        } else {
            let candidate = cleanURLText.contains("://") ? cleanURLText : "https://\(cleanURLText)"
            guard let components = URLComponents(string: candidate),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https", "zoommtg"].contains(scheme),
                  scheme == "zoommtg" || components.host?.contains(".") == true,
                  let parsedURL = components.url else {
                errorMessage = "URLを確認してください。例：https://meet.google.com/..."
                return
            }
            eventURL = parsedURL
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await model.createEvent(
                    title: cleanTitle,
                    location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: eventURL,
                    startAt: startAt,
                    durationMinutes: durationMinutes,
                    calendarIdentifier: calendarIdentifier.isEmpty ? nil : calendarIdentifier
                )
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private static func defaultStartTime() -> Date {
        let interval = 5 * 60.0
        let roundedTime = ceil(Date.now.timeIntervalSince1970 / interval) * interval
        return Date(timeIntervalSince1970: roundedTime)
    }
}
