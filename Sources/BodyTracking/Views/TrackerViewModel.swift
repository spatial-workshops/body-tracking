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
    @Published var outputFormat: OutputFormat = .hands
    /// Scales every body about its chest before publishing; 1 is unchanged.
    @Published var bodyScale: Double = 1
    /// Moves every body by this many canvas pixels, after scaling.
    @Published var offsetX: Double = 0
    @Published var offsetY: Double = 0
    /// Size of the receiving canvas, in pixels: the unit of the offsets and of the hands format.
    @Published var canvasWidth: Double = 1920
    @Published var canvasHeight: Double = 1080
    /// Mirrors x in the published data (not just the preview).
    @Published var flipHorizontally = false
    /// Testing aid: a single detected person is published as a row of copies. See `MultiPoseTest`.
    @Published var multiPoseTest = false
    @Published var mirrorPreview = true

    // Derived state.
    @Published private(set) var cameras: [CameraDevice] = []
    @Published private(set) var resolutions: [Resolution] = []
    @Published private(set) var isRunning = false
    @Published private(set) var cameraMessage: String?
    @Published private(set) var modelStatus: ModelStatus = .idle
    /// Settings from bodytracking.yaml that could not be honoured for this window.
    @Published private(set) var configNotes: [String] = []

    let live = LiveState()
    let camera = CameraController()

    private let processor = FrameProcessor()
    private weak var socket: WebSocketClient?
    private weak var settings: AppSettings?
    private weak var store: ModelStore?
    private var isActive = false
    private var hasCameraAccess = false
    private var isUpdatingResolution = false
    /// Camera named in bodytracking.yaml, resolved once the camera list is known.
    private var requestedCamera: String?
    private var requestedResolution: Resolution?
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
        center.publisher(for: AVCaptureDevice.wasConnectedNotification)
            .merge(with: center.publisher(for: AVCaptureDevice.wasDisconnectedNotification))
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

    // MARK: - Configuration file

    /// Applies one window entry of bodytracking.yaml. Call before `activate`.
    func apply(_ config: WindowConfig, store: ModelStore) {
        if let topic = config.topic { self.topic = topic }
        if let value = config.format {
            if let format = OutputFormat(rawValue: value.lowercased()) {
                outputFormat = format
            } else {
                configNotes.append("Unknown format “\(value)”.")
            }
        }
        if let value = config.canvas {
            if let size = Resolution(id: value.lowercased()), size.width > 0, size.height > 0 {
                canvasWidth = Double(size.width)
                canvasHeight = Double(size.height)
            } else {
                configNotes.append("Canvas “\(value)” is not WIDTHxHEIGHT.")
            }
        }
        if let scale = config.scale, scale >= PoseTransform.minimumScale { bodyScale = scale }
        if let x = config.offsetX { offsetX = x }
        if let y = config.offsetY { offsetY = y }
        if let flip = config.flipHorizontally { flipHorizontally = flip }
        if let multi = config.multiPoseTest { multiPoseTest = multi }
        if let rate = config.detectionRate { targetFPS = min(max(rate.rounded(), 1), 60) }
        if let confidence = config.minConfidence { self.confidence = min(max(confidence, 0.05), 0.95) }
        if let mirror = config.mirrorPreview { mirrorPreview = mirror }
        if let on = config.cameraOn { cameraEnabled = on }
        if let value = config.model {
            if store.info(for: value) != nil {
                selectedModelID = value
            } else {
                configNotes.append("Model “\(value)” is not available; using \(selectedModelID).")
            }
        }
        if let value = config.resolution {
            if let resolution = Resolution(id: value.lowercased()) {
                selectedResolution = resolution
                requestedResolution = resolution
            } else {
                configNotes.append("Resolution “\(value)” is not WIDTHxHEIGHT.")
            }
        }
        if let camera = config.camera?.trimmingCharacters(in: .whitespaces), !camera.isEmpty {
            requestedCamera = camera
        }
    }

    /// Matches a camera by unique ID, then exact name, then part of the name (case-insensitive).
    static func camera(matching query: String, in cameras: [CameraDevice]) -> CameraDevice? {
        cameras.first { $0.id == query }
            ?? cameras.first { $0.name.caseInsensitiveCompare(query) == .orderedSame }
            ?? cameras.first { $0.name.range(of: query, options: .caseInsensitive) != nil }
    }

    // MARK: - Camera

    func refreshCameras() {
        guard hasCameraAccess else { return }
        cameras = CameraController.availableCameras()
        if let query = requestedCamera {
            requestedCamera = nil
            if let match = Self.camera(matching: query, in: cameras) {
                if match.id != selectedCameraID {
                    selectedCameraID = match.id
                    return
                }
            } else {
                configNotes.append("Camera “\(query)” was not found; using the default camera.")
            }
        }
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
        if let requested = requestedResolution {
            requestedResolution = nil
            if keep != requested, !resolutions.isEmpty {
                configNotes.append("This camera does not offer \(requested.label); using its default resolution.")
            }
        }
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
        var transform = PoseTransform(
            scale: bodyScale,
            offsetX: offsetX,
            offsetY: offsetY,
            canvas: canvasSize,
            flipHorizontally: flipHorizontally,
            multiPoseTest: multiPoseTest
        )
        let poses = transform.apply(to: result.poses)
        // The overlay shows what is published, minus the flip: the preview has its own mirror option.
        transform.flipHorizontally = false
        live.poses = flipHorizontally ? transform.apply(to: result.poses) : poses
        live.frameSize = result.frameSize
        live.fps = result.fps
        live.inferenceMs = result.inferenceMs
        live.detectionError = result.error
        if result.error == nil {
            publish(poses)
        }
    }

    private var canvasSize: CGSize {
        CGSize(width: max(canvasWidth, 1), height: max(canvasHeight, 1))
    }

    private func publish(_ poses: [Pose]) {
        guard let socket, socket.state == .connected, let settings else { return }
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        let data = PoseData(poses, format: outputFormat, canvas: canvasSize)
        let message = PublishMessage(clientId: settings.resolvedClientId(), topic: topic, data: data)
        guard let text = MessageEncoder.string(message) else { return }
        socket.send(text)
        live.publishedCount += 1
    }
}
