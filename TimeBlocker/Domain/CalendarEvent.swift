import Foundation

struct CalendarEvent: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let startAt: Date
    let endAt: Date?
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let calendarIdentifier: String
    let calendarColorHex: String?

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: startAt)
        guard let endAt else { return start }
        return "\(start) – \(formatter.string(from: endAt))"
    }
}
