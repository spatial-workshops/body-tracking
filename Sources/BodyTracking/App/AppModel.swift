import Foundation

/// Owns the app-wide singletons shared by every window.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let socket = WebSocketClient()
    let models = ModelStore()
    let startup = StartupConfiguration()

    init() {
        // bodytracking.yaml, when present, overrides the stored server settings at every launch.
        if let server = startup.file?.server {
            if let url = server.url { settings.serverURL = url }
            if let clientId = server.clientId, !clientId.isEmpty { settings.clientId = clientId }
            if let connect = server.connectOnStartup { settings.connectOnLaunch = connect }
        }
        if settings.connectOnLaunch {
            connect()
        }
    }

    func connect() {
        socket.connect(to: settings.serverURL, clientId: settings.resolvedClientId())
    }
}
