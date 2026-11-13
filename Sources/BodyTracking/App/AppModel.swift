import Foundation

/// Owns the app-wide singletons shared by every window.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let socket = WebSocketClient()
    let models = ModelStore()

    init() {
        if settings.connectOnLaunch {
            connect()
        }
    }

    func connect() {
        socket.connect(to: settings.serverURL, clientId: settings.resolvedClientId())
    }
}
