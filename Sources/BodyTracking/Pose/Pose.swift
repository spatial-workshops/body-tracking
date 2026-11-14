import Foundation

/// One body keypoint. Coordinates are normalized to the camera frame:
/// (0, 0) is the top-left corner and (1, 1) the bottom-right. Never mirrored.
struct Keypoint: Encodable, Equatable {
    let name: String
    let x: Double
    let y: Double
    let confidence: Double
}

struct BoundingBox: Encodable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// One detected person.
struct Pose: Encodable, Equatable {
    /// Index within this frame, ordered by descending confidence. Not a stable identity across frames.
    let id: Int
    let confidence: Double
    let box: BoundingBox
    let keypoints: [Keypoint]
}

enum PoseSkeleton {
    static let cocoKeypointNames = [
        "nose", "left_eye", "right_eye", "left_ear", "right_ear",
        "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
        "left_wrist", "right_wrist", "left_hip", "right_hip",
        "left_knee", "right_knee", "left_ankle", "right_ankle",
    ]

    /// Pairs of keypoint indices to connect when drawing a COCO 17-point skeleton.
    static let cocoBones: [(Int, Int)] = [
        (15, 13), (13, 11), (16, 14), (14, 12), (11, 12),
        (5, 11), (6, 12), (5, 6), (5, 7), (6, 8), (7, 9), (8, 10),
        (1, 2), (0, 1), (0, 2), (1, 3), (2, 4), (3, 5), (4, 6),
    ]

    static func keypointName(_ index: Int, total: Int) -> String {
        total == cocoKeypointNames.count ? cocoKeypointNames[index] : "keypoint_\(index)"
    }
}
