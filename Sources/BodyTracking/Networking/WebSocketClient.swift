import Foundation

/// The single WebSocket connection shared by all windows.
///
/// Once `connect` is called the client keeps the connection alive: if the socket drops or the
/// server is unreachable it retries every `retryInterval` seconds until `disconnect` is called.
/// A `client.register` message is sent after every successful (re)connection.
@MainActor
final class WebSocketClient: NSObject, ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case waitingToRetry
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastError: String?
    /// Non-nil while the user wants a connection (connected or still trying).
    @Published private(set) var activeURL: URL?

    var isActive: Bool { activeURL != nil }

    let retryInterval: TimeInterval = 2
    private let pingInterval: TimeInterval = 10

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var clientId = ""
    private var retryTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public API

    func connect(to urlString: String, clientId: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
              url.host != nil
        else {
            lastError = "Invalid WebSocket URL. It must start with ws:// or wss://"
            return
        }
        teardown()
        self.clientId = clientId
        activeURL = url
        lastError = nil
        openSocket()
    }

    /// Explicit user disconnect: stops the socket and stops retrying.
    func disconnect() {
        activeURL = nil
        teardown()
        state = .disconnected
    }

    /// Sends a text frame. Silently dropped unless connected.
    func send(_ text: String) {
        guard state == .connected, let task else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.handleFailure(of: task, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Connection lifecycle

    private func teardown() {
        retryTask?.cancel()
        retryTask = nil
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func openSocket() {
        guard let url = activeURL else { return }
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    private func handleOpen(of task: URLSessionWebSocketTask) {
        guard task === self.task else { return }
        state = .connected
        lastError = nil
        if let text = MessageEncoder.string(RegisterMessage(clientId: clientId)) {
            send(text)
        }
        receive(on: task)
        startPinging(task)
    }

    private func handleFailure(of task: URLSessionTask, message: String) {
        guard task === self.task else { return }
        self.task = nil
        task.cancel()
        pingTask?.cancel()
        pingTask = nil
        guard activeURL != nil else { return }
        lastError = message
        state = .waitingToRetry
        retryTask?.cancel()
        retryTask = Task { [weak self, retryInterval] in
            try? await Task.sleep(for: .seconds(retryInterval))
            guard !Task.isCancelled else { return }
            self?.openSocket()
        }
    }

    /// Incoming messages are not used, but a pending receive is what surfaces a dropped connection.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, task === self.task else { return }
                switch result {
                case .success:
                    self.receive(on: task)
                case .failure(let error):
                    self.handleFailure(of: task, message: error.localizedDescription)
                }
            }
        }
    }

    private func startPinging(_ task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self, pingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pingInterval))
                guard !Task.isCancelled, let self, task === self.task else { return }
                task.sendPing { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in
                        self?.handleFailure(of: task, message: error.localizedDescription)
                    }
                }
            }
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in self.handleOpen(of: webSocketTask) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.handleFailure(of: webSocketTask, message: "Server closed the connection (code \(closeCode.rawValue))")
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let message = error?.localizedDescription ?? "Connection closed"
        Task { @MainActor in self.handleFailure(of: task, message: message) }
    }
}
