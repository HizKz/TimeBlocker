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

    var body: some View {
        Text(statusTitle)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(statusTitle)
    }

    private var statusTitle: String {
        let eventSummary: String
        if let event = model.nextEvent {
            let time = event.startAt.formatted(date: .omitted, time: .shortened)
            let title = String(event.title.prefix(16))
            eventSummary = "\(time) \(title)"
        } else {
            eventSummary = model.hasCalendarAccess ? "予定なし" : "カレンダー未接続"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.orange.opacity(0.85), .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日の作戦")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(Date.now.formatted(date: .complete, time: .omitted) + " · いい一日にしよっ♪")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(.yellow)
                    .padding(.trailing, 4)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isAddingEvent.toggle()
                    }
                } label: {
                    Label(isAddingEvent ? "閉じる" : "予定を追加", systemImage: isAddingEvent ? "xmark" : "plus")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(isAddingEvent ? .gray : .orange)
                .controlSize(.regular)
            }
            .padding(13)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.orange.opacity(0.10), Color.pink.opacity(0.07), Color.purple.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            if isAddingEvent {
                QuickAddEventForm(model: model, isPresented: $isAddingEvent)
                    .padding(13)
                    .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                    .foregroundStyle(.orange)
                Text("予定")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                countBadge(todayEvents.count, tint: .orange)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let event = model.nextEvent {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label("NEXT UP", systemImage: "sparkle")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .tracking(0.7)
                                    .foregroundStyle(.orange)
                                Spacer()
                                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                    let remaining = max(0, Int(event.startAt.timeIntervalSince(timeline.date)))
                                    Text(remaining < 60 ? "まもなく！" : "あと \(remaining / 3600)時間 \((remaining % 3600) / 60)分")
                                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(event.title)
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .lineLimit(2)
                            Label(event.timeRange, systemImage: "clock")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(calendarHex: event.calendarColorHex)).frame(width: 4).padding(.vertical, 9)
                        }
                    } else {
                        emptyState(icon: "cup.and.saucer.fill", title: model.hasCalendarAccess ? "今日は余白たっぷり" : "カレンダーをつなごう", subtitle: model.hasCalendarAccess ? "新しい予定を入れてみる？" : model.permissionMessage, tint: .orange)
                        if !model.hasCalendarAccess {
                            Button("アクセスを許可") { Task { await model.requestCalendarAccess() } }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }

                    if !todayEvents.isEmpty {
                        Text("TODAY'S LINEUP")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(todayEvents) { event in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(calendarHex: event.calendarColorHex))
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.timeRange.components(separatedBy: " – ").first ?? "")
                                        .font(.system(.caption2, design: .rounded, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(event.title).font(.caption).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
            }
            .frame(height: 300)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.orange.opacity(0.12), lineWidth: 1))
    }

    private var notionPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                Text("今日のタスク").font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                countBadge(todayNotionTasks.count, tint: .mint)
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { isAddingNotionTask.toggle() } } label: {
                    Image(systemName: isAddingNotionTask ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.mint.opacity(0.14), in: Circle())
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
                Circle().fill(model.notionStatus.hasPrefix("Notionと同期済み") ? Color.mint : Color.orange).frame(width: 6, height: 6)
                Text(model.notionStatus).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if todayNotionTasks.isEmpty {
                        emptyState(icon: "checkmark.seal.fill", title: model.notionTasks.isEmpty ? "ミッション待ち！" : "今日の期限はなし", subtitle: model.notionTasks.isEmpty ? emptyNotionMessage : "ほかのタスクは下にあるよ", tint: .mint)
                    } else {
                        ForEach(todayNotionTasks) { task in NotionTaskRow(task: task, model: model) }
                    }
                    if !otherNotionTasks.isEmpty {
                        HStack(spacing: 6) {
                            Text("ほかのタスク")
                            Capsule().fill(.quaternary).frame(height: 1)
                        }
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, todayNotionTasks.isEmpty ? 0 : 5)
                        ForEach(otherNotionTasks) { task in NotionTaskRow(task: task, model: model) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
            }
            .frame(height: 300)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.075), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.mint.opacity(0.14), lineWidth: 1))
    }

    private func countBadge(_ count: Int, tint: Color) -> some View {
        Text("\(count)")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.13), in: Capsule())
    }

    private func emptyState(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundStyle(tint.opacity(0.8))
            Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
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
