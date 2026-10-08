import Foundation

struct EventLinkAction: Identifiable, Hashable {
    let title: String
    let url: URL
    let symbol: String

    var id: String { url.absoluteString }
}

enum EventLinkResolver {
    static func actions(for event: CalendarEvent) -> [EventLinkAction] {
        var actions: [EventLinkAction] = []

        func add(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "zoommtg"].contains(scheme) else { return }
            let action = EventLinkAction(
                title: title(for: url),
                url: url,
                symbol: symbol(for: url)
            )
            guard !actions.contains(where: { $0.url.absoluteString == url.absoluteString }) else { return }
            actions.append(action)
        }

        if let url = event.url { add(url) }

        let textValues = [event.notes, event.location].compactMap { $0 }
        for text in textValues {
            for url in detectedURLs(in: text) { add(url) }

            for code in captureGroups(
                pattern: #"(?i)\b([a-z]{3}-[a-z]{4}-[a-z]{3})\b"#,
                in: text
            ) {
                if let url = URL(string: "https://meet.google.com/\(code.lowercased())") { add(url) }
            }

            let zoomPattern = #"(?i)(?:meeting\s*id|meeting\s*number|ミーティング\s*id|ミーティング番号|会議\s*id|会議番号|参加id)\s*[:：#]?\s*([0-9][0-9 -]{7,})"#
            for rawID in captureGroups(pattern: zoomPattern, in: text) {
                let meetingID = rawID.filter { $0 >= "0" && $0 <= "9" }
                guard (9...12).contains(meetingID.count),
                      let url = URL(string: "https://zoom.us/j/\(meetingID)") else { continue }
                add(url)
            }
        }

        return actions
    }

    private static func detectedURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    private static func captureGroups(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private static func title(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host.contains("zoom.us") || host.contains("zoom.com") || url.scheme == "zoommtg" {
            return "Zoomミーティングに参加"
        }
        if host == "meet.google.com" { return "Google Meetに参加" }
        if host.contains("teams.microsoft.com") { return "Teamsミーティングに参加" }
        return "リンクを開く"
    }

    private static func symbol(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host.contains("zoom") || host == "meet.google.com" || host.contains("teams.microsoft.com") {
            return "video"
        }
        return "arrow.up.right"
    }
}
