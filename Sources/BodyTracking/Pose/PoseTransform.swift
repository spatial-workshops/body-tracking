import Foundation

/// The per-window adjustments applied to detected poses before they are published.
///
/// Order: scale each body about its chest → multi-pose test copies → horizontal flip → offset.
/// The offset comes last so it is a plain translation in canvas pixels, whatever the scale,
/// and so a positive x offset always moves bodies to the right, flipped or not.
struct PoseTransform {
    /// 1 leaves bodies unchanged, 0.5 halves them, 2 doubles them.
    var scale: Double = 1
    /// Translation in canvas pixels; positive x is right, positive y is down.
    var offsetX: Double = 0
    var offsetY: Double = 0
    /// Size of the receiving canvas in pixels; converts the offset to normalized coordinates.
    var canvas = CGSize(width: 1920, height: 1080)
    var flipHorizontally = false
    var multiPoseTest = false

    static let minimumScale = 0.01

    func apply(to poses: [Pose]) -> [Pose] {
        var poses = poses
        let scale = max(self.scale, Self.minimumScale)
        if scale != 1 {
            poses = poses.map { $0.scaled(by: scale, about: $0.chest) }
        }
        if multiPoseTest {
            poses = MultiPoseTest.expand(poses)
        }
        if flipHorizontally {
            poses = poses.map { $0.flippedHorizontally() }
        }
        if offsetX != 0 || offsetY != 0 {
            let dx = offsetX / max(Double(canvas.width), 1)
            let dy = offsetY / max(Double(canvas.height), 1)
            poses = poses.map { $0.translated(dx: dx, dy: dy) }
        }
        return poses
    }
}

extension Pose {
    /// The midpoint between the shoulders, or the center of the bounding box for models
    /// that do not report shoulders.
    var chest: (x: Double, y: Double) {
        if let left = keypoints.first(where: { $0.name == "left_shoulder" }),
           let right = keypoints.first(where: { $0.name == "right_shoulder" }) {
            return ((left.x + right.x) / 2, (left.y + right.y) / 2)
        }
        return (box.x + box.width / 2, box.y + box.height / 2)
    }

    /// Scaling the normalized x and y by the same factor is a uniform scale in pixels too.
    func scaled(by factor: Double, about center: (x: Double, y: Double)) -> Pose {
        func sx(_ x: Double) -> Double { round6(center.x + (x - center.x) * factor) }
        func sy(_ y: Double) -> Double { round6(center.y + (y - center.y) * factor) }
        return Pose(
            id: id,
            confidence: confidence,
            box: BoundingBox(x: sx(box.x), y: sy(box.y), width: round6(box.width * factor), height: round6(box.height * factor)),
            keypoints: keypoints.map { Keypoint(name: $0.name, x: sx($0.x), y: sy($0.y), confidence: $0.confidence) }
        )
    }

    func translated(dx: Double, dy: Double) -> Pose {
        Pose(
            id: id,
            confidence: confidence,
            box: BoundingBox(x: round6(box.x + dx), y: round6(box.y + dy), width: box.width, height: box.height),
            keypoints: keypoints.map { Keypoint(name: $0.name, x: round6($0.x + dx), y: round6($0.y + dy), confidence: $0.confidence) }
        )
    }
}

/// Transformed coordinates keep six decimals so a pixel offset survives the round trip
/// through normalized coordinates on any realistic canvas.
private func round6(_ v: Double) -> Double { (v * 1_000_000).rounded() / 1_000_000 }
