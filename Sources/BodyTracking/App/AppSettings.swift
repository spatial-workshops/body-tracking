import Foundation

/// App-wide options, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let defaultServerURL = "ws://localhost:4000"

    private enum Keys {
        static let serverURL = "serverURL"
        static let clientId = "clientId"
        static let connectOnLaunch = "connectOnLaunch"
    }

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    /// Identifies this app to the server. Defaults to a random UUID generated on first launch.
    @Published var clientId: String {
        didSet { defaults.set(clientId, forKey: Keys.clientId) }
    }

    @Published var connectOnLaunch: Bool {
        didSet { defaults.set(connectOnLaunch, forKey: Keys.connectOnLaunch) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverURL = defaults.string(forKey: Keys.serverURL) ?? Self.defaultServerURL
        connectOnLaunch = defaults.bool(forKey: Keys.connectOnLaunch)
        if let stored = defaults.string(forKey: Keys.clientId), !stored.isEmpty {
            clientId = stored
        } else {
            let generated = UUID().uuidString
            clientId = generated
            defaults.set(generated, forKey: Keys.clientId)
        }
    }

    func regenerateClientId() {
        clientId = UUID().uuidString
    }

    /// The client ID to put on the wire; falls back to a fresh UUID if the field was cleared.
    func resolvedClientId() -> String {
        let trimmed = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            regenerateClientId()
            return clientId
        }
        return trimmed
    }
}
