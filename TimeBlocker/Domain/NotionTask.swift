import Foundation

struct NotionTask: Identifiable, Hashable {
    let id: String
    let title: String
    let dueAt: Date?
    let isDateOnly: Bool
    let url: URL

    var hasTimedDueDate: Bool { dueAt != nil && !isDateOnly }
}

enum NotionPropertyKind: String, CaseIterable, Identifiable, Codable {
    case status = "status"
    case select = "select"
    case checkbox = "checkbox"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "Status"
        case .select: "Select"
        case .checkbox: "Checkbox"
        }
    }
}

struct NotionPropertyOption: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

struct NotionPropertySchema: Identifiable, Hashable {
    let name: String
    let kind: NotionPropertyKind
    let options: [NotionPropertyOption]
    var id: String { name }
}
