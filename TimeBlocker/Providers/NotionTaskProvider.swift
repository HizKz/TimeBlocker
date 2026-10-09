import Foundation
import Security

struct NotionConfiguration: Codable, Equatable {
    var dataSourceID = ""
    var titleProperty = ""
    var dueDateProperty = ""
    var completionProperty = ""
    var completionKind = NotionPropertyKind.status
    var completionValue = ""
}

enum NotionProviderError: LocalizedError {
    case missingConfiguration(String)
    case invalidResponse
    case http(Int, String)
    case missingProperty(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let item): "Notion設定の\(item)を入力してください。"
        case .invalidResponse: "Notionからの応答を読み取れませんでした。"
        case .http(let code, let message): "Notion APIエラー (\(code)): \(message)"
        case .missingProperty(let name): "Notionプロパティ「\(name)」が見つかりません。"
        }
    }
}

final class NotionTaskProvider {
    private let keychainService = "com.hizumekazushi.TimeBlocker.notion"
    private let tokenAccount = "integration-token"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func loadToken() -> String {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: tokenAccount,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        query.removeAll()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveToken(_ token: String) throws {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: tokenAccount]
        SecItemDelete(query as CFDictionary)
        guard !clean.isEmpty else { return }
        var values = query
        values[kSecValueData as String] = Data(clean.utf8)
        let status = SecItemAdd(values as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func fetchSchema(configuration: NotionConfiguration) async throws -> [NotionPropertySchema] {
        guard !configuration.dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotionProviderError.missingConfiguration("Data Source ID") }
        let data = try await request(path: "/v1/data_sources/\(configuration.dataSourceID)", method: "GET")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = root["properties"] as? [String: [String: Any]] else {
            throw NotionProviderError.invalidResponse
        }
        return properties.compactMap { name, value in
            for kind in NotionPropertyKind.allCases {
                guard let details = value[kind.rawValue] as? [String: Any] else { continue }
                let options = (details["options"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.map(NotionPropertyOption.init(name:))
                return NotionPropertySchema(name: name, kind: kind, options: options)
            }
            return nil
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchPropertyNames(configuration: NotionConfiguration) async throws -> [String] {
        guard !configuration.dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotionProviderError.missingConfiguration("Data Source ID") }
        let data = try await request(path: "/v1/data_sources/\(configuration.dataSourceID)", method: "GET")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = root["properties"] as? [String: Any] else { throw NotionProviderError.invalidResponse }
        return properties.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func fetchTasks(configuration: NotionConfiguration) async throws -> [NotionTask] {
        let token = loadToken()
        guard !token.isEmpty else { throw NotionProviderError.missingConfiguration("Integration Token") }
        try validate(configuration, requireCompletion: true)
        var tasks: [NotionTask] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let data = try await request(path: "/v1/data_sources/\(configuration.dataSourceID)/query", method: "POST", body: body)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { throw NotionProviderError.invalidResponse }
            tasks.append(contentsOf: results.compactMap { page in parseTask(page, configuration: configuration) })
            cursor = (root["has_more"] as? Bool == true) ? root["next_cursor"] as? String : nil
        } while cursor != nil
        return tasks.sorted {
            switch ($0.dueAt, $1.dueAt) {
            case let (a?, b?): a == b ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending : a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    func markComplete(pageID: String, configuration: NotionConfiguration) async throws {
        try validate(configuration, requireCompletion: true)
        let value: Any
        switch configuration.completionKind {
        case .checkbox: value = ["checkbox": true]
        case .select: value = ["select": ["name": configuration.completionValue]]
        case .status: value = ["status": ["name": configuration.completionValue]]
        }
        _ = try await request(path: "/v1/pages/\(pageID)", method: "PATCH", body: ["properties": [configuration.completionProperty: value]])
    }

    func createTask(title: String, dueAt: Date?, isDateOnly: Bool, configuration: NotionConfiguration) async throws {
        try validate(configuration, requireCompletion: true)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw NotionProviderError.missingConfiguration("タスク名") }

        var properties: [String: Any] = [
            configuration.titleProperty: ["title": [["text": ["content": cleanTitle]]]]
        ]
        if let dueAt {
            let dateString: String
            if isDateOnly {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = "yyyy-MM-dd"
                dateString = formatter.string(from: dueAt)
            } else {
                dateString = ISO8601DateFormatter().string(from: dueAt)
            }
            properties[configuration.dueDateProperty] = ["date": ["start": dateString]]
        }
        if configuration.completionKind == .checkbox {
            properties[configuration.completionProperty] = ["checkbox": false]
        }
        _ = try await request(path: "/v1/pages", method: "POST", body: [
            "parent": ["type": "data_source_id", "data_source_id": configuration.dataSourceID],
            "properties": properties
        ])
    }

    private func parseTask(_ page: [String: Any], configuration: NotionConfiguration) -> NotionTask? {
        guard let id = page["id"] as? String,
              let urlText = page["url"] as? String, let url = URL(string: urlText),
              let props = page["properties"] as? [String: [String: Any]],
              let titleProperty = props[configuration.titleProperty],
              let title = propertyTitle(titleProperty), !title.isEmpty,
              !isComplete(props[configuration.completionProperty], configuration: configuration) else { return nil }
        let dueProperty = props[configuration.dueDateProperty]
        let dateValue = (dueProperty?["date"] as? [String: Any])?["start"] as? String
        let isDateOnly = dateValue.map { !$0.contains("T") } ?? false
        let dueAt = dateValue.flatMap(parseISODate)
        return NotionTask(id: id, title: title, dueAt: dueAt, isDateOnly: isDateOnly, url: url)
    }

    private func propertyTitle(_ property: [String: Any]) -> String? {
        for key in ["title", "rich_text"] {
            if let items = property[key] as? [[String: Any]] {
                let text = items.compactMap { ($0["plain_text"] as? String) ?? (($0["text"] as? [String: Any])?["content"] as? String) }.joined()
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func isComplete(_ property: [String: Any]?, configuration: NotionConfiguration) -> Bool {
        guard let property else { return false }
        if configuration.completionKind == .checkbox { return property["checkbox"] as? Bool == true }
        let key = configuration.completionKind.rawValue
        let value = (property[key] as? [String: Any])?["name"] as? String
        return value == configuration.completionValue
    }

    private func parseISODate(_ string: String) -> Date? {
        if !string.contains("T") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: string)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private func validate(_ configuration: NotionConfiguration, requireCompletion: Bool) throws {
        guard !configuration.dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotionProviderError.missingConfiguration("Data Source ID") }
        guard !configuration.titleProperty.isEmpty else { throw NotionProviderError.missingConfiguration("タイトルプロパティ") }
        guard !configuration.dueDateProperty.isEmpty else { throw NotionProviderError.missingConfiguration("期限プロパティ") }
        if requireCompletion {
            guard !configuration.completionProperty.isEmpty else { throw NotionProviderError.missingConfiguration("完了プロパティ") }
            if configuration.completionKind != .checkbox && configuration.completionValue.isEmpty { throw NotionProviderError.missingConfiguration("完了値") }
        }
    }

    private func request(path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        let token = loadToken()
        guard !token.isEmpty else { throw NotionProviderError.missingConfiguration("Integration Token") }
        guard let url = URL(string: "https://api.notion.com\(path)") else { throw NotionProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-11", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        var (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionProviderError.invalidResponse }
        if http.statusCode == 429 {
            let delay = max(1, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1)
            try await Task.sleep(for: .seconds(delay))
            (data, response) = try await session.data(for: request)
        }
        guard let final = response as? HTTPURLResponse else { throw NotionProviderError.invalidResponse }
        guard (200..<300).contains(final.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw NotionProviderError.http(final.statusCode, message)
        }
        return data
    }
}
