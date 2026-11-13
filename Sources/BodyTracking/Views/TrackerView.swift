import SwiftUI

/// One tracker window: camera preview with pose overlay, per-window options, connection bar.
struct TrackerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var socket: WebSocketClient
    @EnvironmentObject private var store: ModelStore
    @Environment(\.openWindow) private var openWindow

    @StateObject private var model = TrackerViewModel()

    // Per-window options, restored when the window is.
    @SceneStorage("tracker.topic") private var storedTopic = "pose"
    @SceneStorage("tracker.camera") private var storedCamera = ""
    @SceneStorage("tracker.resolution") private var storedResolution = ""
    @SceneStorage("tracker.fps") private var storedFPS = 15.0
    @SceneStorage("tracker.confidence") private var storedConfidence = 0.35
    @SceneStorage("tracker.model") private var storedModel = ModelCatalog.defaultModelID
    @SceneStorage("tracker.mirror") private var storedMirror = true

    var body: some View {
        HStack(spacing: 0) {
            videoPane
            Divider()
            optionsPane
                .frame(width: 300)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConnectionBar()
        }
        .frame(minWidth: 820, minHeight: 520)
        .navigationTitle(model.topic.isEmpty ? "Body Tracking" : "Body Tracking — \(model.topic)")
        .task {
            restoreOptions()
            await model.activate(socket: socket, settings: settings, store: store)
        }
        .onDisappear { model.shutdown() }
        .onChange(of: model.topic) { _, value in storedTopic = value }
        .onChange(of: model.selectedCameraID) { _, value in storedCamera = value }
        .onChange(of: model.selectedResolution) { _, value in storedResolution = value?.id ?? "" }
        .onChange(of: model.targetFPS) { _, value in storedFPS = value }
        .onChange(of: model.confidence) { _, value in storedConfidence = value }
        .onChange(of: model.selectedModelID) { _, value in storedModel = value }
        .onChange(of: model.mirrorPreview) { _, value in storedMirror = value }
    }

    private func restoreOptions() {
        model.topic = storedTopic
        model.targetFPS = min(max(storedFPS, 1), 60)
        model.confidence = min(max(storedConfidence, 0.05), 0.95)
        model.mirrorPreview = storedMirror
        model.selectedResolution = Resolution(id: storedResolution)
        model.selectedCameraID = storedCamera
        model.selectedModelID = store.info(for: storedModel) != nil ? storedModel : ModelCatalog.defaultModelID
    }

    // MARK: - Video

    private var videoPane: some View {
        ZStack {
            Color.black
            CameraPreview(session: model.camera.session, mirrored: model.mirrorPreview)
            PoseOverlay(
                live: model.live,
                mirrored: model.mirrorPreview,
                fallbackSize: model.selectedResolution.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            )
            if let message = videoMessage {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(24)
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoMessage: String? {
        if let message = model.cameraMessage { return message }
        if !model.cameraEnabled { return "Camera is off" }
        return nil
    }

    // MARK: - Options

    private var optionsPane: some View {
        Form {
            Section("Camera") {
                Picker("Camera", selection: $model.selectedCameraID) {
                    if !model.cameras.contains(where: { $0.id == model.selectedCameraID }) {
                        Text(model.cameras.isEmpty ? "No camera" : "Select…").tag(model.selectedCameraID)
                    }
                    ForEach(model.cameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                Picker("Resolution", selection: $model.selectedResolution) {
                    if model.selectedResolution == nil {
                        Text("Default").tag(Resolution?.none)
                    }
                    ForEach(model.resolutions) { resolution in
                        Text(resolution.label).tag(Resolution?.some(resolution))
                    }
                }
                Toggle("Camera on", isOn: $model.cameraEnabled)
                Toggle("Mirror preview", isOn: $model.mirrorPreview)
            }

            Section("Detection") {
                Picker("Model", selection: $model.selectedModelID) {
                    ForEach(store.models) { info in
                        Text(modelLabel(info)).tag(info.id)
                    }
                }
                modelStatusRow
                Stepper(value: $model.targetFPS, in: 1...60, step: 1) {
                    LabeledContent("Detection rate") {
                        HStack(spacing: 4) {
                            TextField("Detection rate", value: $model.targetFPS, format: .number.precision(.fractionLength(0)))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .onSubmit { model.targetFPS = min(max(model.targetFPS.rounded(), 1), 60) }
                            Text("fps").foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Min. confidence") {
                    HStack {
                        Slider(value: $model.confidence, in: 0.05...0.95)
                        Text(model.confidence, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Manage Models…") { openWindow(id: WindowID.models) }
            }

            Section("Publishing") {
                TextField("Topic", text: $model.topic, prompt: Text("pubsub topic"))
                if model.topic.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label("Enter a topic to publish poses.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Status") {
                LiveStats(live: model.live)
            }
        }
        .formStyle(.grouped)
    }

    private func modelLabel(_ info: ModelInfo) -> String {
        if store.state(for: info.id) == .installed || info.downloadSizeMB == nil {
            return info.name
        }
        return "\(info.name) (↓ \(String(format: "%.1f", info.downloadSizeMB ?? 0)) MB)"
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        switch model.modelStatus {
        case .idle, .ready:
            if let info = store.info(for: model.selectedModelID) {
                Text(info.detail).font(.caption).foregroundStyle(.secondary)
            }
        case .loading:
            switch store.state(for: model.selectedModelID) {
            case .downloading(let fraction):
                ProgressView(value: fraction) { Text("Downloading model…").font(.caption) }
            case .installing:
                HStack { ProgressView().controlSize(.small); Text("Compiling model…").font(.caption) }
            default:
                HStack { ProgressView().controlSize(.small); Text("Loading model…").font(.caption) }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry") { model.loadModel() }
            }
        }
    }
}

/// Per-frame numbers; observes `LiveState` directly so the rest of the form stays still.
private struct LiveStats: View {
    @ObservedObject var live: LiveState

    var body: some View {
        LabeledContent("People", value: "\(live.poses.count)")
        LabeledContent("Detection rate", value: String(format: "%.1f fps", live.fps))
        LabeledContent("Inference", value: String(format: "%.1f ms", live.inferenceMs))
        if live.frameSize.width > 0 {
            LabeledContent("Frame", value: "\(Int(live.frameSize.width)) × \(Int(live.frameSize.height))")
        }
        LabeledContent("Messages sent", value: "\(live.publishedCount)")
        if let error = live.detectionError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
