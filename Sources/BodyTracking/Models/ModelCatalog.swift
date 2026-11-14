import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    /// Where the Core ML package is downloaded from; nil for models imported from disk.
    let downloadURL: URL?
    let downloadSizeMB: Double?

    var isBuiltIn: Bool { downloadURL != nil }
}

/// The models the app knows how to download.
///
/// These are the official Core ML exports of the Ultralytics YOLO26 pose models (640×640 input,
/// 17 COCO keypoints, NMS-free), published as release assets of ultralytics/yolo-ios-app.
/// To offer a newer generation, add entries here (the decoder also handles the classic
/// YOLO11/YOLOv8 output layout) or import a .mlpackage through the Models window.
enum ModelCatalog {
    static let releaseBase = "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0"
    static let defaultModelID = "yolo26n-pose"

    static let builtIn: [ModelInfo] = [
        entry("yolo26n-pose", "YOLO26n Pose", "Nano — fastest", 2.8),
        entry("yolo26s-pose", "YOLO26s Pose", "Small", 9.7),
        entry("yolo26m-pose", "YOLO26m Pose", "Medium", 19.9),
        entry("yolo26l-pose", "YOLO26l Pose", "Large", 24.1),
        entry("yolo26x-pose", "YOLO26x Pose", "Extra large — most accurate", 53.0),
    ]

    private static func entry(_ id: String, _ name: String, _ detail: String, _ sizeMB: Double) -> ModelInfo {
        ModelInfo(
            id: id,
            name: name,
            detail: detail,
            downloadURL: URL(string: "\(releaseBase)/\(id).mlpackage.zip"),
            downloadSizeMB: sizeMB
        )
    }
}
