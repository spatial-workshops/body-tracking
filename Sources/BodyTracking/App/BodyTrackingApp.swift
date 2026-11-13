import SwiftUI

enum WindowID {
    static let tracker = "tracker"
    static let models = "models"
}

struct BodyTrackingApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        // Each window is an independent tracker; File › New Window (⌘N) opens another.
        WindowGroup("Body Tracking", id: WindowID.tracker) {
            TrackerView()
                .environmentObject(app.settings)
                .environmentObject(app.socket)
                .environmentObject(app.models)
        }
        .defaultSize(width: 1100, height: 660)
        .commands {
            CommandGroup(after: .newItem) {
                ModelsWindowCommand()
            }
        }

        Window("Models", id: WindowID.models) {
            ModelManagerView()
                .environmentObject(app.models)
        }
        .defaultSize(width: 560, height: 420)

        Settings {
            SettingsView()
                .environmentObject(app.settings)
                .environmentObject(app.socket)
        }
    }
}

private struct ModelsWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Manage Models…") { openWindow(id: WindowID.models) }
            .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}
