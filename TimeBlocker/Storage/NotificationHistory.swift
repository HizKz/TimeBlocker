import Foundation

struct SnoozedBatch: Identifiable, Codable, Equatable {
    let id: String
    var events: [CalendarEvent]
    let fireAt: Date
}

struct SnoozeStore {
    private let defaults = UserDefaults.standard
    private let key = "snoozedNotificationBatches"

    func load() -> [SnoozedBatch] {
        guard let data = defaults.data(forKey: key),
              let batches = try? JSONDecoder().decode([SnoozedBatch].self, from: data) else {
            return []
        }
        return batches
    }

    func save(_ batches: [SnoozedBatch]) {
        guard let data = try? JSONEncoder().encode(batches) else { return }
        defaults.set(data, forKey: key)
    }
}

struct NotificationHistory {
    private let defaults = UserDefaults.standard
    private let key = "handledEventStartKeys"

    func hasHandled(_ event: CalendarEvent) -> Bool {
        handledKeys.contains(Self.key(for: event))
    }

    func markHandled(_ events: [CalendarEvent], now: Date = .now) {
        var keys = handledKeys
        keys.formUnion(events.map(Self.key(for:)))
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970
        keys = Set(keys.filter { key in
            guard let timestamp = Double(key.split(separator: "|", omittingEmptySubsequences: false).last ?? "") else { return true }
            return timestamp >= cutoff
        })
        defaults.set(Array(keys), forKey: key)
    }

    private var handledKeys: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private static func key(for event: CalendarEvent) -> String {
        "\(event.id)|\(event.startAt.timeIntervalSince1970)"
    }
}
