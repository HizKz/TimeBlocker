import Foundation

protocol EventProvider {
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent]
}
