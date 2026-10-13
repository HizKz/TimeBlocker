import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateManager: UpdateManager
    @State private var tokenDraft = ""
    @State private var tokenMessage: String?

    var body: some View {
        TabView {
            calendarSettings
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            notionSettings
                .tabItem { Label("Notion", systemImage: "checklist") }
            generalSettings
                .tabItem { Label("一般", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 430)
        .padding()
    }

    private var notionSettings: some View {
        Form {
            Section("Notion接続") {
                SecureField("Integration Token", text: $tokenDraft)
                HStack {
                    Button("Tokenを保存") {
                        do { try model.setNotionToken(tokenDraft); tokenDraft = ""; tokenMessage = "Keychainに保存しました" }
                        catch { tokenMessage = error.localizedDescription }
                    }
                    Button("Tokenを削除") {
                        do { try model.setNotionToken(""); tokenDraft = ""; tokenMessage = "Tokenを削除しました" }
                        catch { tokenMessage = error.localizedDescription }
                    }
                    Text(model.notionToken.isEmpty ? "未設定" : "保存済み").font(.caption).foregroundStyle(.secondary)
                }
                if let tokenMessage { Text(tokenMessage).font(.caption).foregroundStyle(.secondary) }
                TextField("Data Source ID", text: binding(\.dataSourceID))
                Text("データベースをTimeBlockerに共有してください。タスクの追加にはIntegrationのInsert content権限も必要です。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Data Sourceのスキーマを取得") { Task { await model.refreshNotionSchema() } }
                    .disabled(model.notionToken.isEmpty || model.notionConfiguration.dataSourceID.isEmpty)
            }

            Section("タスクのプロパティ") {
                if !model.notionPropertyNames.isEmpty {
                    Picker("タイトルプロパティ", selection: binding(\.titleProperty)) {
                        ForEach(model.notionPropertyNames, id: \.self) { name in Text(name).tag(name) }
                    }
                    Picker("期限プロパティ", selection: binding(\.dueDateProperty)) {
                        ForEach(model.notionPropertyNames, id: \.self) { name in Text(name).tag(name) }
                    }
                    Picker("完了列", selection: binding(\.completionProperty)) {
                        Text("選択してください").tag("")
                        ForEach(model.notionSchemas.filter { $0.kind == model.notionConfiguration.completionKind }) { schema in Text(schema.name).tag(schema.name) }
                    }
                    Picker("完了列の種類", selection: binding(\.completionKind)) {
                        ForEach(NotionPropertyKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    if model.notionConfiguration.completionKind != .checkbox {
                        Picker("完了を表す値", selection: binding(\.completionValue)) {
                            Text("選択してください").tag("")
                            ForEach(selectedCompletionSchema?.options ?? []) { option in Text(option.name).tag(option.name) }
                        }
                    }
                } else {
                    TextField("完了プロパティ名", text: binding(\.completionProperty))
                    Picker("完了列の種類", selection: binding(\.completionKind)) {
                        ForEach(NotionPropertyKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    if model.notionConfiguration.completionKind != .checkbox {
                        TextField("完了を表す値", text: binding(\.completionValue))
                    }
                }
                Text(model.notionStatus).font(.caption).foregroundStyle(.secondary)
                Text("起動時・設定変更時・スリープ復帰時と、起動中は60秒ごとに自動同期します。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("今すぐ同期") { Task { await model.syncNotion(force: true) } }
                    .disabled(model.notionToken.isEmpty)
            }
        }
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var selectedCompletionSchema: NotionPropertySchema? {
        model.notionSchemas.first { $0.name == model.notionConfiguration.completionProperty }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotionConfiguration, Value>) -> Binding<Value> {
        Binding(get: { model.notionConfiguration[keyPath: keyPath] }, set: { model.notionConfiguration[keyPath: keyPath] = $0 })
    }

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カレンダーへのアクセス").font(.title2.weight(.semibold))
            Text(model.permissionMessage).foregroundStyle(.secondary)
            if !model.hasCalendarAccess {
                HStack {
                    Button("アクセスを許可") { Task { await model.requestCalendarAccess() } }
                        .buttonStyle(.borderedProminent)
                    Button("システム設定を開く") { model.openSystemCalendarSettings() }
                }
                Spacer()
            } else {
                Text("通知するカレンダー").font(.headline).padding(.top, 4)
                List(model.calendars) { calendar in
                    Toggle(isOn: selectionBinding(for: calendar.id)) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(Color(calendarHex: calendar.colorHex))
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                Text(calendar.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 10)
    }

    private var generalSettings: some View {
        Form {
            Section("アップデート") {
                Button("アップデートを確認") { updateManager.checkForUpdates() }
                Text("TimeBlockerの新しいバージョンを確認します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通知") {
                Picker("スリープ復帰後の通知期限", selection: $model.notificationGraceMinutes) {
                    ForEach([1, 3, 5, 10, 15], id: \.self) { minutes in
                        Text("予定開始から\(minutes)分").tag(minutes)
                    }
                }
                Text("Macがスリープから戻ったとき、この時間内に始まった予定を通知します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("表示") {
                Picker("通知を表示する画面", selection: $model.overlayDisplayMode) {
                    ForEach(OverlayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("予定の追加") {
                Picker("初期の所要時間", selection: $model.quickAddDefaultDurationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text("\(minutes)分").tag(minutes)
                    }
                }
                Picker("初期の保存先", selection: $model.quickAddCalendarIdentifier) {
                    Text("システム標準").tag("")
                    ForEach(model.writableCalendars) { calendar in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(calendarHex: calendar.colorHex))
                                .frame(width: 8, height: 8)
                            Text(calendar.title)
                        }
                        .tag(calendar.id)
                    }
                }
                .disabled(model.writableCalendars.isEmpty)
            }

            Section {
                Button("10秒後に通知をテスト") { model.scheduleTestNotification() }
            }
        }
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func selectionBinding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedCalendarIdentifiers.contains(identifier) },
            set: { isSelected in
                if isSelected {
                    model.selectedCalendarIdentifiers.insert(identifier)
                } else {
                    model.selectedCalendarIdentifiers.remove(identifier)
                }
            }
        )
    }
}
