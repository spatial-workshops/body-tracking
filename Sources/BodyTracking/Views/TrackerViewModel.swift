import AVFoundation
import Combine
import Foundation

/// Values that change on every processed frame. Kept separate from `TrackerViewModel`
/// so only the overlay and the statistics redraw at the detection rate.
@MainActor
final class LiveState: ObservableObject {
    @Published var poses: [Pose] = []
    @Published var frameSize: CGSize = .zero
    @Published var fps: Double = 0
    @Published var inferenceMs: Double = 0
    @Published var publishedCount: Int = 0
    @Published var detectionError: String?

    func reset() {
        poses = []
        fps = 0
        inferenceMs = 0
        detectionError = nil
    }
}

enum ModelStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// State and behaviour of one tracker window.
@MainActor
final class TrackerViewModel: ObservableObject {
    // User-facing options (persisted per window by the view).
    @Published var selectedCameraID: String = "" {
        didSet { if oldValue != selectedCameraID { cameraSelectionChanged() } }
    }
    @Published var selectedResolution: Resolution? {
        didSet { if oldValue != selectedResolution, !isUpdatingResolution { restartCamera() } }
    }
    @Published var targetFPS: Double = 15 {
        didSet { processor.setTargetFPS(targetFPS) }
    }
    @Published var confidence: Double = 0.35 {
        didSet { processor.setConfidence(confidence) }
    }
    @Published var selectedModelID: String = ModelCatalog.defaultModelID {
        didSet { if oldValue != selectedModelID { loadModel() } }
    }
    @Published var cameraEnabled = true {
        didSet { if oldValue != cameraEnabled { cameraEnabled ? restartCamera() : stopCamera() } }
    }
    @Published var topic: String = "pose"
    @Published var mirrorPreview = true

    // Derived state.
    @Published private(set) var cameras: [CameraDevice] = []
    @Published private(set) var resolutions: [Resolution] = []
    @Published private(set) var isRunning = false
    @Published private(set) var cameraMessage: String?
    @Published private(set) var modelStatus: ModelStatus = .idle

    let live = LiveState()
    let camera = CameraController()

    private let processor = FrameProcessor()
    private weak var socket: WebSocketClient?
    private weak var settings: AppSettings?
    private weak var store: ModelStore?
    private var isActive = false
    private var hasCameraAccess = false
    private var isUpdatingResolution = false
    private var loadTask: Task<Void, Never>?
    private var startGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    init() {
        processor.setTargetFPS(targetFPS)
        processor.setConfidence(confidence)
        processor.onResult = { [weak self] result in
            DispatchQueue.main.async { self?.handle(result) }
        }
        camera.onFrame = { [processor] buffer, time in
            processor.process(buffer, at: time)
        }
    }

    // MARK: - Lifecycle

    /// Called once when the window appears, after stored options have been restored.
    func activate(socket: WebSocketClient, settings: AppSettings, store: ModelStore) async {
        guard !isActive else { return }
        self.socket = socket
        self.settings = settings
        self.store = store
        isActive = true

        let center = NotificationCenter.default
        center.publisher(for: .AVCaptureDeviceWasConnected)
            .merge(with: center.publisher(for: .AVCaptureDeviceWasDisconnected))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCameras() }
            .store(in: &cancellables)

        loadModel()

        hasCameraAccess = await CameraController.requestAccess()
        guard hasCameraAccess else {
            cameraMessage = "Camera access is denied. Allow it in System Settings › Privacy & Security › Camera, then reopen this window."
            return
        }
        refreshCameras()
    }

    /// Called when the window closes.
    func shutdown() {
        isActive = false
        cancellables.removeAll()
        loadTask?.cancel()
        processor.setDetector(nil)
        camera.stop()
        isRunning = false
    }

    // MARK: - Camera

    func refreshCameras() {
        guard hasCameraAccess else { return }
        cameras = CameraController.availableCameras()
        if cameras.contains(where: { $0.id == selectedCameraID }) {
            if resolutions.isEmpty || !isRunning { cameraSelectionChanged() }
            return
        }
        // First launch, or the selected camera was unplugged: fall back to the default camera.
        let fallback = CameraController.defaultCameraID().flatMap { id in cameras.first { $0.id == id } } ?? cameras.first
        if let fallback {
            selectedCameraID = fallback.id
        } else {
            resolutions = []
            stopCamera()
            cameraMessage = "No camera found."
        }
    }

    private func cameraSelectionChanged() {
        guard isActive, hasCameraAccess else { return }
        resolutions = CameraController.resolutions(for: selectedCameraID)
        let keep = selectedResolution.flatMap { resolutions.contains($0) ? $0 : nil }
        isUpdatingResolution = true
        selectedResolution = keep ?? Resolution.preferred(in: resolutions)
        isUpdatingResolution = false
        restartCamera()
    }

    private func restartCamera() {
        guard isActive, hasCameraAccess, cameraEnabled, !selectedCameraID.isEmpty else { return }
        startGeneration += 1
        let generation = startGeneration
        cameraMessage = nil
        live.reset()
        camera.start(deviceID: selectedCameraID, resolution: selectedResolution) { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.startGeneration, self.isActive else { return }
                self.isRunning = error == nil
                self.cameraMessage = error?.localizedDescription
            }
        }
    }

    private func stopCamera() {
        startGeneration += 1
        camera.stop()
        isRunning = false
        live.reset()
    }

    // MARK: - Model

    func loadModel() {
        guard isActive, let store else { return }
        loadTask?.cancel()
        processor.setDetector(nil)
        live.reset()
        modelStatus = .loading
        let id = selectedModelID
        loadTask = Task { [weak self] in
            do {
                let url = try await store.ensureInstalled(id)
                try Task.checkCancellation()
                let detector = try await Task.detached(priority: .userInitiated) {
                    try PoseDetector(compiledModelURL: url)
                }.value
                guard let self, !Task.isCancelled, id == self.selectedModelID, self.isActive else { return }
                self.processor.setDetector(detector)
                self.modelStatus = .ready
            } catch is CancellationError {
                return
            } catch {
                guard let self, id == self.selectedModelID else { return }
                self.modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Results

    private func handle(_ result: DetectionResult) {
        guard isActive, isRunning else { return }
        live.poses = result.poses
        live.frameSize = result.frameSize
        live.fps = result.fps
        live.inferenceMs = result.inferenceMs
        live.detectionError = result.error
        if result.error == nil {
            publish(result.poses)
        }
    }

    private func publish(_ poses: [Pose]) {
        guard let socket, socket.state == .connected, let settings else { return }
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        let message = PublishMessage(clientId: settings.resolvedClientId(), topic: topic, poses: poses)
        guard let text = MessageEncoder.string(message) else { return }
        socket.send(text)
        live.publishedCount += 1
    }
}
