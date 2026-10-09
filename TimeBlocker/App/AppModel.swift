import AppKit
import Combine
import EventKit
import Foundation

struct CalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let isWritable: Bool
    let colorHex: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var activeEvents: [CalendarEvent] = []
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var hasCalendarAccess = false
    @Published private(set) var permissionMessage = "カレンダーへのアクセスを確認しています…"
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var notionTasks: [NotionTask] = []
    @Published private(set) var notionStatus = "Notion未設定"
    @Published private(set) var notionSchemas: [NotionPropertySchema] = []
    @Published private(set) var notionPropertyNames: [String] = []
    @Published private(set) var notionToken = ""
    @Published private(set) var activeNotionTasks: [NotionTask] = []
    @Published private(set) var notionActionError: String?
    @Published var notionConfiguration = NotionConfiguration() {
        didSet {
            if let data = try? JSONEncoder().encode(notionConfiguration) {
                UserDefaults.standard.set(data, forKey: Self.notionConfigurationKey)
            }
            scheduleNotionSync()
        }
    }
    @Published var notificationGraceMinutes = 5 {
        didSet { UserDefaults.standard.set(notificationGraceMinutes, forKey: Self.notificationGraceKey) }
    }
    @Published var overlayDisplayMode: OverlayDisplayMode = .allDisplays {
        didSet { UserDefaults.standard.set(overlayDisplayMode.rawValue, forKey: Self.overlayDisplayKey) }
    }
    @Published var quickAddDefaultDurationMinutes = 30 {
        didSet { UserDefaults.standard.set(quickAddDefaultDurationMinutes, forKey: Self.quickAddDurationKey) }
    }
    @Published var quickAddCalendarIdentifier = "" {
        didSet { UserDefaults.standard.set(quickAddCalendarIdentifier, forKey: Self.quickAddCalendarKey) }
    }
    @Published var selectedCalendarIdentifiers: Set<String> = [] {
        didSet {
            guard !isLoadingSelection else { return }
            UserDefaults.standard.set(Array(selectedCalendarIdentifiers), forKey: Self.selectionKey)
            provider.selectedCalendarIdentifiers = selectedCalendarIdentifiers
            Task { await refresh() }
        }
    }

    private static let selectionKey = "selectedCalendarIdentifiers"
    private static let notificationGraceKey = "notificationGraceMinutes"
    private static let overlayDisplayKey = "overlayDisplayMode"
    private static let quickAddDurationKey = "quickAddDefaultDurationMinutes"
    private static let quickAddCalendarKey = "quickAddCalendarIdentifier"
    private static let notionConfigurationKey = "notionConfiguration"
    private static let notionHandledKey = "notionHandledTaskIDs"
    private let provider = EventKitProvider()
    private let notionProvider = NotionTaskProvider()
    private let history = NotificationHistory()
    private let snoozeStore = SnoozeStore()
    private let overlayManager = OverlayManager()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timerTask: Task<Void, Never>?
    private var isLoadingSelection = false
    private var snoozedBatches: [SnoozedBatch] = []
    private var queuedBatches: [PendingNotificationBatch] = []
    private var queuedSnoozeIDs: Set<String> = []
    private var lastNotionAttempt: Date?
    private var notionSyncTask: Task<Void, Never>?
    private var notionSnoozes: [(ids: Set<String>, fireAt: Date)] = []
    private var handledNotionIDs: Set<String> = []

    private struct PendingNotificationBatch {
        let events: [CalendarEvent]
        let snoozeID: String?
    }

    init() {
        let defaults = UserDefaults.standard
        snoozedBatches = snoozeStore.load()
        if defaults.object(forKey: Self.notificationGraceKey) != nil {
            notificationGraceMinutes = defaults.integer(forKey: Self.notificationGraceKey)
        }
        if defaults.object(forKey: Self.overlayDisplayKey) != nil,
           let storedMode = OverlayDisplayMode(rawValue: defaults.string(forKey: Self.overlayDisplayKey) ?? "") {
            overlayDisplayMode = storedMode
        }
        if defaults.object(forKey: Self.quickAddDurationKey) != nil {
            quickAddDefaultDurationMinutes = defaults.integer(forKey: Self.quickAddDurationKey)
        }
        quickAddCalendarIdentifier = defaults.string(forKey: Self.quickAddCalendarKey) ?? ""
        if let data = defaults.data(forKey: Self.notionConfigurationKey),
           let configuration = try? JSONDecoder().decode(NotionConfiguration.self, from: data) {
            notionConfiguration = configuration
        }
        notionToken = notionProvider.loadToken()
        handledNotionIDs = Set(defaults.stringArray(forKey: Self.notionHandledKey) ?? [])
        installObservers()
        Task {
            await syncNotion()
            if provider.authorizationStatus == .notDetermined {
                await requestCalendarAccess()
            } else {
                await refresh()
            }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.hasCalendarAccess, self.lastUpdated.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true {
                    await self.refresh()
                } else {
                    await self.tick()
                }
                if !self.notionToken.isEmpty,
                   self.lastNotionAttempt.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true {
                    await self.syncNotion()
                }
            }
        }
    }

    deinit {
        timerTask?.cancel()
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    var nextEvent: CalendarEvent? {
        upcomingEvents.first(where: { $0.startAt > .now })
    }

    var writableCalendars: [CalendarChoice] {
        calendars.filter(\.isWritable)
    }

    var defaultCalendarIdentifier: String? {
        provider.defaultCalendarIdentifier
    }

    func requestCalendarAccess() async {
        do {
            let granted = try await provider.requestAccess()
            hasCalendarAccess = granted
            permissionMessage = granted ? "カレンダーに接続しました" : "カレンダーへのアクセスが許可されていません"
            if granted { await refresh() }
        } catch {
            permissionMessage = "カレンダーへのアクセスに失敗しました: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        await syncNotion()
        let status = provider.authorizationStatus
        guard status == .fullAccess else {
            hasCalendarAccess = false
            permissionMessage = status == .denied || status == .restricted
                ? "カレンダーへのアクセスが許可されていません"
                : "カレンダーへのアクセスが必要です"
            upcomingEvents = []
            return
        }
        hasCalendarAccess = true
        permissionMessage = "カレンダーに接続しました"
        refreshCalendarChoices()
        provider.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        do {
            let now = Date.now
            let defaultLookback = now.addingTimeInterval(-TimeInterval(notificationGraceMinutes * 60))
            let snoozeLookback = snoozedBatches.flatMap(\.events).map(\.startAt).min()
            let fetchStart = min(defaultLookback, snoozeLookback ?? defaultLookback)
            let fetched = try await provider.fetchEvents(from: fetchStart, to: now.addingTimeInterval(24 * 60 * 60))
            let validEvents = fetched
                .filter { !$0.isAllDay && !$0.title.isEmpty }
                .sorted { $0.startAt < $1.startAt }
            reconcileSnoozedBatches(with: validEvents, now: now)
            upcomingEvents = validEvents
            lastUpdated = .now
            await tick()
        } catch {
            permissionMessage = "カレンダーの予定を取得できませんでした: \(error.localizedDescription)"
        }
    }

    func openSystemCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func openEventURL(_ url: URL) {
        NSWorkspace.shared.open(url)
        finishActiveBatch()
    }

    func createEvent(
        title: String,
        location: String?,
        url: URL?,
        startAt: Date,
        durationMinutes: Int,
        calendarIdentifier: String?
    ) async throws {
        let endAt = startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        try provider.createEvent(
            title: title,
            location: location,
            url: url,
            startAt: startAt,
            endAt: endAt,
            calendarIdentifier: calendarIdentifier
        )
        await refresh()
    }

    func dismissOverlay() {
        if !activeNotionTasks.isEmpty { dismissActiveNotionBatch() }
        else { skipActiveBatch() }
    }

    func snoozeActiveBatch(for minutes: Int) {
        guard [5, 10, 15].contains(minutes) else { return }
        if !activeNotionTasks.isEmpty {
            notionSnoozes.append((Set(activeNotionTasks.map(\.id)), .now.addingTimeInterval(TimeInterval(minutes * 60))))
            finishActiveNotionBatch()
            return
        }
        guard !activeEvents.isEmpty else { return }
        snoozedBatches.append(SnoozedBatch(
            id: UUID().uuidString,
            events: activeEvents,
            fireAt: .now.addingTimeInterval(TimeInterval(minutes * 60))
        ))
        persistSnoozedBatches()
        finishActiveBatch()
    }

    func skipActiveBatch() {
        guard !activeEvents.isEmpty else {
            finishActiveBatch()
            return
        }
        history.markHandled(activeEvents)
        finishActiveBatch()
    }

    func setNotionToken(_ token: String) throws {
        try notionProvider.saveToken(token)
        notionToken = notionProvider.loadToken()
        Task { await syncNotion(force: true) }
    }

    private func scheduleNotionSync() {
        notionSyncTask?.cancel()
        notionSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.syncNotion(force: true)
        }
    }

    func refreshNotionSchema() async {
        do {
            notionSchemas = try await notionProvider.fetchSchema(configuration: notionConfiguration)
            notionPropertyNames = try await notionProvider.fetchPropertyNames(configuration: notionConfiguration)
            notionStatus = "Notionのスキーマを取得しました"
        } catch { notionStatus = error.localizedDescription }
    }

    func syncNotion(force: Bool = false) async {
        guard !notionToken.isEmpty else { notionStatus = "Notion未設定"; return }
        if !force, let lastNotionAttempt, Date.now.timeIntervalSince(lastNotionAttempt) < 60 { return }
        lastNotionAttempt = .now
        do {
            notionTasks = try await notionProvider.fetchTasks(configuration: notionConfiguration)
            notionStatus = "Notionと同期済み（\(notionTasks.count)件）"
            await tickNotion()
        } catch {
            notionStatus = error.localizedDescription
        }
    }

    func addNotionTask(title: String, dueAt: Date?, isDateOnly: Bool) async throws {
        try await notionProvider.createTask(title: title, dueAt: dueAt, isDateOnly: isDateOnly, configuration: notionConfiguration)
        notionStatus = "Notionにタスクを追加しました"
        await syncNotion(force: true)
    }

    func openNotionTask(_ task: NotionTask) { NSWorkspace.shared.open(task.url) }

    func completeNotionTask(_ id: String) {
        guard let task = notionTasks.first(where: { $0.id == id }) else { return }
        Task {
            do {
                try await notionProvider.markComplete(pageID: id, configuration: notionConfiguration)
                notionActionError = nil
                notionTasks.removeAll { $0.id == id }
                activeNotionTasks.removeAll { $0.id == id }
                if activeNotionTasks.isEmpty { overlayManager.dismiss(); showNextNotification() }
                else { presentNotion(activeNotionTasks) }
                _ = task
                await syncNotion()
            } catch {
                notionActionError = "完了にできませんでした: \(error.localizedDescription)"
                notionStatus = notionActionError ?? "完了にできませんでした"
                presentNotion(activeNotionTasks)
            }
        }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func scheduleTestNotification() {
        let start = Date.now.addingTimeInterval(10)
        let testEvent = CalendarEvent(
            id: "timeblocker-test-\(UUID().uuidString)",
            title: "TimeBlocker テスト通知",
            startAt: start,
            endAt: start.addingTimeInterval(30 * 60),
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: false,
            calendarIdentifier: "test",
            calendarColorHex: nil
        )
        upcomingEvents.append(testEvent)
        upcomingEvents.sort { $0.startAt < $1.startAt }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func refreshCalendarChoices() {
        let choices = provider.calendars.map {
            CalendarChoice(
                id: $0.calendarIdentifier,
                title: $0.title,
                source: $0.source.title,
                isWritable: $0.allowsContentModifications,
                colorHex: provider.colorHex(for: $0)
            )
        }
        calendars = choices
        isLoadingSelection = true
        if let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) {
            let available = Set(choices.map(\.id))
            selectedCalendarIdentifiers = Set(stored).intersection(available)
        } else {
            selectedCalendarIdentifiers = Set(choices.map(\.id))
            UserDefaults.standard.set(Array(selectedCalendarIdentifiers), forKey: Self.selectionKey)
        }
        isLoadingSelection = false
    }

    private func tick() async {
        let now = Date.now
        if hasCalendarAccess {
            let readySnoozes = snoozedBatches
                .filter { $0.fireAt <= now && !queuedSnoozeIDs.contains($0.id) }
                .sorted { $0.fireAt < $1.fireAt }
            for batch in readySnoozes {
                let events = batch.events.filter { $0.endAt.map { $0 > now } ?? true }
                guard !events.isEmpty else {
                    removeSnoozedBatch(id: batch.id)
                    continue
                }
                enqueue([PendingNotificationBatch(events: events, snoozeID: batch.id)])
            }
        }

        let due = upcomingEvents.filter {
            let age = now.timeIntervalSince($0.startAt)
            return age >= 0 && age <= TimeInterval(notificationGraceMinutes * 60) && !history.hasHandled($0)
        }
        guard !due.isEmpty else { return }
        let grouped = Dictionary(grouping: due, by: \.startAt)
            .values
            .map { $0.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
            .sorted { ($0.first?.startAt ?? .distantFuture) < ($1.first?.startAt ?? .distantFuture) }
        for batch in grouped { history.markHandled(batch, now: now) }
        enqueue(grouped.map { PendingNotificationBatch(events: $0, snoozeID: nil) })
    }

    private func tickNotion() async {
        let now = Date.now
        if activeEvents.isEmpty, activeNotionTasks.isEmpty,
           let index = notionSnoozes.indices.filter({ notionSnoozes[$0].fireAt <= now }).min(by: { notionSnoozes[$0].fireAt < notionSnoozes[$1].fireAt }) {
            let snooze = notionSnoozes.remove(at: index)
            let tasks = notionTasks.filter { snooze.ids.contains($0.id) }
            if !tasks.isEmpty { presentNotion(tasks); return }
        }
        let due = notionTasks.filter { task in
            guard task.hasTimedDueDate, let dueAt = task.dueAt, dueAt <= now,
                  !handledNotionIDs.contains(task.id) else { return false }
            return true
        }
        guard activeEvents.isEmpty, activeNotionTasks.isEmpty,
              let earliestDate = due.compactMap(\.dueAt).min() else { return }
        let tasks = due.filter { $0.dueAt == earliestDate }
        handledNotionIDs.formUnion(tasks.map(\.id))
        persistHandledNotionIDs()
        notionActionError = nil
        presentNotion(tasks)
    }

    private func presentNotion(_ tasks: [NotionTask]) {
        guard !tasks.isEmpty else { return }
        activeEvents = []
        activeNotionTasks = tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        overlayManager.show(events: [], notionTasks: activeNotionTasks, notionError: notionActionError, displayMode: overlayDisplayMode,
                            onOpenURL: { url in NSWorkspace.shared.open(url) },
                            onSnooze: { [weak self] minutes in self?.snoozeActiveBatch(for: minutes) },
                            onSkip: { [weak self] in self?.dismissActiveNotionBatch() },
                            onCompleteNotionTask: { [weak self] id in self?.completeNotionTask(id) })
    }

    private func dismissActiveNotionBatch() {
        handledNotionIDs.formUnion(activeNotionTasks.map(\.id))
        persistHandledNotionIDs()
        notionActionError = nil
        finishActiveNotionBatch()
    }

    private func finishActiveNotionBatch() {
        overlayManager.dismiss()
        activeNotionTasks = []
        showNextNotification()
        Task { await tickNotion() }
    }

    private func showNextNotification() {
        if !queuedBatches.isEmpty { presentNext(queuedBatches.removeFirst()) }
        else if !activeNotionTasks.isEmpty { presentNotion(activeNotionTasks) }
    }

    private func persistHandledNotionIDs() {
        UserDefaults.standard.set(Array(handledNotionIDs), forKey: Self.notionHandledKey)
    }

    private func enqueue(_ batches: [PendingNotificationBatch]) {
        guard !batches.isEmpty else { return }
        if activeEvents.isEmpty, activeNotionTasks.isEmpty, queuedBatches.isEmpty {
            var remaining = batches
            presentNext(remaining.removeFirst())
            appendToQueue(remaining)
        } else {
            appendToQueue(batches)
        }
    }

    private func appendToQueue(_ batches: [PendingNotificationBatch]) {
        for batch in batches {
            if let snoozeID = batch.snoozeID {
                queuedSnoozeIDs.insert(snoozeID)
            }
            queuedBatches.append(batch)
        }
    }

    private func presentNext(_ batch: PendingNotificationBatch) {
        if let snoozeID = batch.snoozeID {
            queuedSnoozeIDs.remove(snoozeID)
        }
        let events = batch.events.filter { $0.endAt.map { $0 > .now } ?? true }
        guard !events.isEmpty else {
            if !queuedBatches.isEmpty {
                presentNext(queuedBatches.removeFirst())
            }
            return
        }
        if let snoozeID = batch.snoozeID {
            removeSnoozedBatch(id: snoozeID)
        }
        present(events)
    }

    private func present(_ events: [CalendarEvent]) {
        activeNotionTasks = []
        activeEvents = events
        overlayManager.show(
            events: events,
            displayMode: overlayDisplayMode,
            onOpenURL: { [weak self] url in
            self?.openEventURL(url)
            },
            onSnooze: { [weak self] minutes in
                self?.snoozeActiveBatch(for: minutes)
            },
            onSkip: { [weak self] in
                self?.skipActiveBatch()
            },
            onCompleteNotionTask: { [weak self] id in self?.completeNotionTask(id) }
        )
    }

    private func finishActiveBatch() {
        overlayManager.dismiss()
        activeEvents = []
        showNextNotification()
    }

    private func reconcileSnoozedBatches(with currentEvents: [CalendarEvent], now: Date) {
        let currentByKey = currentEvents.reduce(into: [String: CalendarEvent]()) { result, event in
            result[occurrenceKey(for: event)] = event
        }
        let reconciled = snoozedBatches.compactMap { batch -> SnoozedBatch? in
            let events = batch.events.compactMap { currentSnoozedEvent($0, currentByKey: currentByKey) }
                .filter { $0.endAt.map { $0 > now } ?? true }
            guard !events.isEmpty else { return nil }
            return SnoozedBatch(id: batch.id, events: events, fireAt: batch.fireAt)
        }
        if reconciled != snoozedBatches {
            snoozedBatches = reconciled
            persistSnoozedBatches()
        }

        queuedBatches = queuedBatches.compactMap { batch in
            guard let snoozeID = batch.snoozeID else { return batch }
            let events = batch.events.compactMap { currentSnoozedEvent($0, currentByKey: currentByKey) }
                .filter { $0.endAt.map { $0 > now } ?? true }
            guard !events.isEmpty else {
                queuedSnoozeIDs.remove(snoozeID)
                return nil
            }
            return PendingNotificationBatch(events: events, snoozeID: snoozeID)
        }
    }

    private func occurrenceKey(for event: CalendarEvent) -> String {
        let startMilliseconds = Int64((event.startAt.timeIntervalSince1970 * 1_000).rounded())
        return "\(event.id)|\(startMilliseconds)"
    }

    private func currentSnoozedEvent(
        _ event: CalendarEvent,
        currentByKey: [String: CalendarEvent]
    ) -> CalendarEvent? {
        if event.id.hasPrefix("timeblocker-test-") { return event }
        return currentByKey[occurrenceKey(for: event)]
    }

    private func removeSnoozedBatch(id: String) {
        snoozedBatches.removeAll { $0.id == id }
        persistSnoozedBatches()
    }

    private func persistSnoozedBatches() {
        snoozeStore.save(snoozedBatches)
    }

    private func installObservers() {
        observers.append((NotificationCenter.default, provider.observeChanges { [weak self] in Task { await self?.refresh() } }))
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }))
        let defaultCenter = NotificationCenter.default
        observers.append((defaultCenter, defaultCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }))
        observers.append((defaultCenter, defaultCenter.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }))
        observers.append((defaultCenter, defaultCenter.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }))
    }
}
