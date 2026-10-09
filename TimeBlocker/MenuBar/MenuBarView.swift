import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel

    private var todayNotionTasks: [NotionTask] {
        model.notionTasks.filter { task in
            guard let dueAt = task.dueAt else { return false }
            return Calendar.current.isDateInToday(dueAt)
        }
    }

    private var taskForStatus: NotionTask? {
        todayNotionTasks.first
            ?? model.notionTasks.first(where: { $0.dueAt == nil })
            ?? model.notionTasks.first
    }

    private let countdownWindow: TimeInterval = 6 * 60 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let title = statusTitle(at: timeline.date)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title)
        }
    }

    private func statusTitle(at date: Date) -> String {
        let eventSummary: String
        if let event = model.nextEvent {
            let secondsUntil = event.startAt.timeIntervalSince(date)
            let eventTime: String
            if secondsUntil <= countdownWindow {
                let minutesUntil = max(1, Int(ceil(secondsUntil / 60)))
                if secondsUntil < 60 {
                    eventTime = "まもなく"
                } else if minutesUntil < 60 {
                    eventTime = "あと\(minutesUntil)分"
                } else {
                    let hours = minutesUntil / 60
                    let minutes = minutesUntil % 60
                    eventTime = minutes == 0 ? "あと\(hours)時間" : "あと\(hours)時間\(minutes)分"
                }
            } else {
                let day = Calendar.current.isDateInToday(event.startAt) ? "" : "明日 "
                eventTime = day + event.startAt.formatted(date: .omitted, time: .shortened)
            }
            let title = String(event.title.prefix(13))
            eventSummary = "\(eventTime) \(title)"
        } else {
            eventSummary = model.hasCalendarAccess ? "予定なし" : "カレンダー未接続"
        }

        if model.nextEvent != nil {
            return eventSummary
        }
        guard let task = taskForStatus else {
            if !model.notionToken.isEmpty,
               !model.notionStatus.hasPrefix("Notionと同期済み"),
               model.notionStatus != "Notion未設定" {
                return "\(eventSummary) · Notion同期を確認"
            }
            return eventSummary
        }
        let taskTitle = String(task.title.prefix(14))
        let dateLabel: String
        if let dueAt = task.dueAt, Calendar.current.isDateInToday(dueAt) {
            dateLabel = "今日: "
        } else if task.dueAt == nil {
            dateLabel = "期限なし: "
        } else {
            dateLabel = "タスク: "
        }
        let remainingCount = model.notionTasks.count - 1
        let countSuffix = remainingCount > 0 ? " +\(remainingCount)件" : ""
        let taskSummary = "\(dateLabel)\(taskTitle)\(countSuffix)"
        return "\(eventSummary) · \(taskSummary)"
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var isAddingEvent = false
    @State private var isAddingNotionTask = false

    private var todayEvents: [CalendarEvent] {
        model.upcomingEvents.filter { Calendar.current.isDateInToday($0.startAt) }
    }

    private var todayNotionTasks: [NotionTask] {
        model.notionTasks
            .filter { task in
                guard let dueAt = task.dueAt else { return false }
                return Calendar.current.isDateInToday(dueAt)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var otherNotionTasks: [NotionTask] {
        let todayTaskIDs = Set(todayNotionTasks.map(\.id))
        return model.notionTasks.filter { !todayTaskIDs.contains($0.id) }
    }

    private var scheduleScrollHeight: CGFloat {
        guard model.nextEvent != nil || !todayEvents.isEmpty else { return 82 }
        let eventListHeight = todayEvents.isEmpty ? 0 : CGFloat(28 + todayEvents.count * 50)
        return min(320, 92 + eventListHeight)
    }

    private var notionScrollHeight: CGFloat {
        guard !model.notionTasks.isEmpty else { return 82 }
        let sectionHeight = todayNotionTasks.isEmpty || otherNotionTasks.isEmpty ? 0 : 28
        return min(320, CGFloat(model.notionTasks.count * 64 + sectionHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TimeBlocker")
                        .font(.headline)
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                schedulePanel
                notionPanel
            }

            HStack(spacing: 9) {
                SettingsLink { Label("設定", systemImage: "gearshape") }
                    .buttonStyle(.borderless)
                Spacer()
                Button { model.scheduleTestNotification() } label: { Label("通知テスト", systemImage: "bell.badge") }
                    .buttonStyle(.borderless)
                Button { model.quit() } label: { Label("終了", systemImage: "power") }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 720, alignment: .leading)
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text("予定")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                countBadge(todayEvents.count)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAddingEvent.toggle()
                    }
                } label: {
                    Image(systemName: isAddingEvent ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .help("予定を追加")
            }

            if isAddingEvent {
                QuickAddEventForm(model: model, isPresented: $isAddingEvent)
                    .padding(10)
                    .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let event = model.nextEvent {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("次の予定")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                    let remaining = max(0, Int(event.startAt.timeIntervalSince(timeline.date)))
                                    Text(remaining < 60 ? "まもなく！" : "あと \(remaining / 3600)時間 \((remaining % 3600) / 60)分")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(event.title)
                                .font(.headline)
                                .lineLimit(2)
                            Label(event.timeRange, systemImage: "clock")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(calendarHex: event.calendarColorHex)).frame(width: 4).padding(.vertical, 9)
                        }
                    } else {
                        emptyState(icon: "calendar", title: model.hasCalendarAccess ? "今日の予定はありません" : "カレンダーに接続されていません", subtitle: model.hasCalendarAccess ? "予定を追加できます" : model.permissionMessage)
                        if !model.hasCalendarAccess {
                            Button("アクセスを許可") { Task { await model.requestCalendarAccess() } }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }

                    if !todayEvents.isEmpty {
                        Text("今日の予定")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(todayEvents) { event in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(calendarHex: event.calendarColorHex))
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.timeRange.components(separatedBy: " – ").first ?? "")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(event.title).font(.caption).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
            }
            .frame(height: scheduleScrollHeight)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var notionPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
                Text("今日のタスク").font(.headline)
                Spacer()
                countBadge(todayNotionTasks.count)
                Button { withAnimation(.easeInOut(duration: 0.18)) { isAddingNotionTask.toggle() } } label: {
                    Image(systemName: isAddingNotionTask ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain).help("Notionタスクを追加")
                Button { Task { await model.syncNotion(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain).help("Notionと同期")
            }
            if isAddingNotionTask {
                NotionQuickAddTaskForm(model: model, isPresented: $isAddingNotionTask)
                    .padding(10)
                    .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(spacing: 5) {
                Circle().fill(model.notionStatus.hasPrefix("Notionと同期済み") ? Color.accentColor : Color.secondary).frame(width: 6, height: 6)
                Text(model.notionStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if todayNotionTasks.isEmpty {
                        emptyState(icon: "checkmark.circle", title: model.notionTasks.isEmpty ? "タスクはありません" : "今日が期限のタスクはありません", subtitle: model.notionTasks.isEmpty ? emptyNotionMessage : "ほかのタスクは下に表示されます")
                    } else {
                        ForEach(todayNotionTasks) { task in NotionTaskRow(task: task, model: model) }
                    }
                    if !otherNotionTasks.isEmpty {
                        HStack(spacing: 6) {
                            Text("ほかのタスク")
                            Capsule().fill(.quaternary).frame(height: 1)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, todayNotionTasks.isEmpty ? 0 : 5)
                        ForEach(otherNotionTasks) { task in NotionTaskRow(task: task, model: model) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
            }
            .frame(height: notionScrollHeight)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular)).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.medium))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var emptyNotionMessage: String {
        if model.notionToken.isEmpty { return "設定からNotionを接続できます" }
        if model.notionStatus.hasPrefix("Notionと同期済み") { return "未完了タスクはありません" }
        return model.notionStatus
    }
}

private struct NotionTaskRow: View {
    let task: NotionTask
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { model.completeNotionTask(task.id) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.mint)
                    .frame(width: 23, height: 25)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("完了にする")
            VStack(alignment: .leading, spacing: 3) {
                Button(task.title) { model.openNotionTask(task) }
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .buttonStyle(.plain).lineLimit(2).multilineTextAlignment(.leading)
                if let dueAt = task.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: task.isDateOnly ? .omitted : .shortened), systemImage: task.isDateOnly ? "calendar" : "clock")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(dueAt < .now ? .orange : .secondary)
                }
            }
            Spacer(minLength: 0)
            Button { model.openNotionTask(task) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 21, height: 21)
                    .background(.quaternary.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain).help("Notionで開く")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.mint.opacity(0.09), lineWidth: 1))
    }
}

private struct NotionQuickAddTaskForm: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var isDateOnly = false
    @State private var dueAt = Date.now.addingTimeInterval(60 * 60)
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var titleIsFocused: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("タスク名", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onSubmit(save)
            Toggle("期限を設定", isOn: $hasDueDate)
                .toggleStyle(.checkbox)
            if hasDueDate {
                Toggle("日付のみ（時刻を指定しない）", isOn: $isDateOnly)
                    .toggleStyle(.checkbox)
                DatePicker("期限", selection: $dueAt, displayedComponents: isDateOnly ? [.date] : [.date, .hourAndMinute])
                    .datePickerStyle(.field)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("追加") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.vertical, 2)
        .onAppear { titleIsFocused = true }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.addNotionTask(title: cleanTitle, dueAt: hasDueDate ? dueAt : nil, isDateOnly: isDateOnly)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
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
