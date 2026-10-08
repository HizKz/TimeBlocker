import AppKit
import EventKit
import Foundation

@MainActor
final class EventKitProvider: EventProvider {
    private let store = EKEventStore()
    var selectedCalendarIdentifiers: Set<String>?

    var calendars: [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var defaultCalendarIdentifier: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        guard authorizationStatus == .fullAccess else { return [] }
        let selectedCalendars = calendars.filter { calendar in
            selectedCalendarIdentifiers?.contains(calendar.calendarIdentifier) ?? true
        }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: selectedCalendars)
        return store.events(matching: predicate).map { event in
            let eventTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (eventTitle?.isEmpty == false) ? eventTitle! : "（タイトルなし）"
            return CalendarEvent(
                id: event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)-\(event.startDate.timeIntervalSince1970)-\(title)",
                title: title,
                startAt: event.startDate,
                endAt: event.endDate,
                location: event.location,
                notes: event.notes,
                url: event.url,
                isAllDay: event.isAllDay,
                calendarIdentifier: event.calendar.calendarIdentifier,
                calendarColorHex: colorHex(for: event.calendar)
            )
        }
    }

    func createEvent(
        title: String,
        location: String?,
        url: URL?,
        startAt: Date,
        endAt: Date,
        calendarIdentifier: String?
    ) throws {
        guard authorizationStatus == .fullAccess else {
            throw EventCreationError.calendarAccessRequired
        }

        let writableCalendars = calendars.filter(\.allowsContentModifications)
        let selectedCalendar = calendarIdentifier.flatMap { identifier in
            writableCalendars.first { $0.calendarIdentifier == identifier }
        }
        let calendar = selectedCalendar
            ?? store.defaultCalendarForNewEvents.flatMap { $0.allowsContentModifications ? $0 : nil }
            ?? writableCalendars.first

        guard let calendar else { throw EventCreationError.noWritableCalendar }
        guard endAt > startAt else { throw EventCreationError.invalidTimeRange }

        let event = EKEvent(eventStore: store)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = cleanLocation?.isEmpty == false ? cleanLocation : nil
        event.url = url
        event.startDate = startAt
        event.endDate = endAt
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
    }

    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            handler()
        }
    }

    func colorHex(for calendar: EKCalendar) -> String? {
        guard let cgColor = calendar.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum EventCreationError: LocalizedError {
    case calendarAccessRequired
    case noWritableCalendar
    case invalidTimeRange

    var errorDescription: String? {
        switch self {
        case .calendarAccessRequired:
            return "予定の作成にはカレンダーへのアクセス許可が必要です。"
        case .noWritableCalendar:
            return "書き込み可能なカレンダーがありません。"
        case .invalidTimeRange:
            return "終了時刻は開始時刻より後にしてください。"
        }
    }
}
