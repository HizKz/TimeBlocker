import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            calendarSettings
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            generalSettings
                .tabItem { Label("一般", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 430)
        .padding()
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
