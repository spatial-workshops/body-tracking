import Foundation
import Yams

/// The contents of `bodytracking.yaml`. Every key is optional; anything left out keeps the
/// app's own default (or, for the server settings, the value last used in the app).
struct ConfigFile: Codable, Equatable {
    var server: ServerConfig?
    var windows: [WindowConfig]?
}

/// App-wide settings.
struct ServerConfig: Codable, Equatable {
    var url: String?
    var connectOnStartup: Bool?
    var clientId: String?

    static let keys: Set<String> = ["url", "connectOnStartup", "clientId"]
}

/// Settings for one tracker window. One window is opened per entry at startup.
struct WindowConfig: Codable, Equatable {
    var topic: String?
    /// Camera name (as shown in the Camera menu), part of the name, or the camera's unique ID.
    var camera: String?
    /// `WIDTHxHEIGHT`, e.g. `1920x1080`.
    var resolution: String?
    var cameraOn: Bool?
    var mirrorPreview: Bool?
    var model: String?
    var detectionRate: Double?
    var minConfidence: Double?
    /// `mediapipe-modified`, `mediapipe` or `yolo`.
    var format: String?
    /// `WIDTHxHEIGHT`, e.g. `1920x1080`.
    var canvas: String?
    var scale: Double?
    var offsetX: Double?
    var offsetY: Double?
    var flipHorizontally: Bool?
    var multiPoseTest: Bool?

    static let keys: Set<String> = [
        "topic", "camera", "resolution", "cameraOn", "mirrorPreview", "model", "detectionRate",
        "minConfidence", "format", "canvas", "scale", "offsetX", "offsetY", "flipHorizontally",
        "multiPoseTest",
    ]
}

/// Reads `bodytracking.yaml` once at launch and hands its window entries to the windows
/// as they open.
@MainActor
final class StartupConfiguration: ObservableObject {
    static let defaultPath = "~/bodytracking.yaml"

    /// The file that was looked for.
    let url: URL
    /// The parsed file; nil when there is no file or it could not be read.
    let file: ConfigFile?

    private var unclaimedWindows: [WindowConfig]
    private var extraWindows: Int
    private var problems: [String]

    /// `--config <path>` on the command line overrides the default location.
    init(arguments: [String] = CommandLine.arguments) {
        url = Self.location(arguments: arguments)
        var problems: [String] = []
        var file: ConfigFile?
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let loaded = try Self.load(url)
                file = loaded.file
                problems = loaded.warnings
            } catch {
                problems = ["The file could not be read, so it was ignored.\n\(Self.describe(error))"]
            }
        } else if arguments.contains("--config") {
            problems = ["There is no file at \(url.path)."]
        }
        self.file = file
        self.problems = problems
        unclaimedWindows = file?.windows ?? []
        extraWindows = max(unclaimedWindows.count - 1, 0)
    }

    /// True when the file lists windows; the app then opens exactly those instead of
    /// restoring the windows of the previous session.
    var definesWindows: Bool { !(file?.windows ?? []).isEmpty }

    /// The settings for the next window to open, in file order; nil once all are handed out.
    func claimWindow() -> WindowConfig? {
        unclaimedWindows.isEmpty ? nil : unclaimedWindows.removeFirst()
    }

    /// How many windows still have to be opened beyond the one the app opens by itself.
    /// Non-zero only the first time it is called.
    func takeExtraWindowCount() -> Int {
        defer { extraWindows = 0 }
        return extraWindows
    }

    /// Problems found while reading the file, to show the user once.
    func takeProblems() -> String? {
        defer { problems = [] }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    // MARK: - Loading

    static func location(arguments: [String]) -> URL {
        var path = defaultPath
        if let flag = arguments.firstIndex(of: "--config"), flag + 1 < arguments.count {
            path = arguments[flag + 1]
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Parses the file. `warnings` lists keys the app does not know, which are otherwise ignored.
    static func load(_ url: URL) throws -> (file: ConfigFile, warnings: [String]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let root = try Yams.load(yaml: text) else {
            return (ConfigFile(), [])  // empty file, or comments only
        }
        let file = try YAMLDecoder().decode(ConfigFile.self, from: text)

        var warnings: [String] = []
        func unknownKeys(in value: Any?, allowed: Set<String>, where place: String) {
            guard let dictionary = value as? [String: Any] else { return }
            for key in dictionary.keys.sorted() where !allowed.contains(key) {
                warnings.append("Unknown setting “\(key)” \(place) was ignored.")
            }
        }
        unknownKeys(in: root, allowed: ["server", "windows"], where: "at the top level")
        if let dictionary = root as? [String: Any] {
            unknownKeys(in: dictionary["server"], allowed: ServerConfig.keys, where: "under server")
            for (index, window) in ((dictionary["windows"] as? [Any]) ?? []).enumerated() {
                unknownKeys(in: window, allowed: WindowConfig.keys, where: "in window \(index + 1)")
            }
        }
        return (file, warnings)
    }

    static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .typeMismatch(_, let context), .valueNotFound(_, let context),
                 .keyNotFound(_, let context), .dataCorrupted(let context):
                let path = context.codingPath.map { $0.intValue.map { "[\($0 + 1)]" } ?? $0.stringValue }.joined(separator: " › ")
                return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
            @unknown default:
                break
            }
        }
        return String(describing: error)
    }
}
