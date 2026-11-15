import CoreImage
import Foundation

/// A headless mode for checking a model without a camera or a server:
///
///     BodyTracking.app/Contents/MacOS/BodyTracking --detect photo.jpg [--model <id | path | https URL>] [--confidence 0.35] [--format mediapipe-modified|mediapipe|yolo] [--canvas 1920x1080] [--flip] [--multi-pose]
///
/// Prints the `pubsub.publish` message the app would send for that image.
enum CommandLineTool {
    struct Options {
        var image: URL
        var model = ModelCatalog.defaultModelID
        var confidence: Float = 0.35
        var format = OutputFormat.hands
        var canvas = CGSize(width: 1920, height: 1080)
        var flip = false
        var multiPose = false

        init?(arguments: [String]) {
            guard let flag = arguments.firstIndex(of: "--detect"), flag + 1 < arguments.count else { return nil }
            image = URL(fileURLWithPath: arguments[flag + 1])
            if let index = arguments.firstIndex(of: "--model"), index + 1 < arguments.count {
                model = arguments[index + 1]
            }
            if let index = arguments.firstIndex(of: "--confidence"), index + 1 < arguments.count,
               let value = Float(arguments[index + 1]) {
                confidence = value
            }
            if let index = arguments.firstIndex(of: "--format"), index + 1 < arguments.count,
               let value = OutputFormat(rawValue: arguments[index + 1].lowercased()) {
                format = value
            }
            if let index = arguments.firstIndex(of: "--canvas"), index + 1 < arguments.count,
               let size = Resolution(id: arguments[index + 1].lowercased()) {
                canvas = CGSize(width: size.width, height: size.height)
            }
            flip = arguments.contains("--flip")
            multiPose = arguments.contains("--multi-pose")
        }
    }

    static func run(_ options: Options) async -> Int32 {
        do {
            let compiled = try await compiledModel(for: options.model)
            let detector = try PoseDetector(compiledModelURL: compiled)
            guard let image = CIImage(contentsOf: options.image, options: [.applyOrientationProperty: true]) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: options.image.path])
            }
            var poses = try detector.detect(image: image, confidenceThreshold: options.confidence)
            if options.multiPose { poses = MultiPoseTest.expand(poses) }
            let data = PoseData(poses, format: options.format, canvas: options.canvas, flipHorizontally: options.flip)
            let message = PublishMessage(clientId: "command-line", topic: "command-line", data: data)
            print(MessageEncoder.string(message, pretty: true) ?? "{}")
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func compiledModel(for model: String) async throws -> URL {
        if let info = ModelCatalog.builtIn.first(where: { $0.id == model }) {
            _ = info
            return try await ModelStore().ensureInstalled(model)
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodytracking-cli-\(UUID().uuidString).mlmodelc")
        if let url = URL(string: model), url.scheme == "https" || url.scheme == "http" {
            let archive = try await ModelInstaller.download(from: url) { _ in }
            defer { try? FileManager.default.removeItem(at: archive) }
            try await ModelInstaller.install(from: archive, to: destination)
        } else {
            try await ModelInstaller.install(from: URL(fileURLWithPath: model), to: destination)
        }
        return destination
    }
}
