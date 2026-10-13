import Foundation

@MainActor
protocol EventProvider {
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent]
    func deleteEvent(withIdentifier identifier: String) throws
}
