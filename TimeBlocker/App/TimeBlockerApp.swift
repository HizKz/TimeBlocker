import SwiftUI

@main
struct TimeBlockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model, updateManager: updateManager)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, updateManager: updateManager)
        }
    }
}
