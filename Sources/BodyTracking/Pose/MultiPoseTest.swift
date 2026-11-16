import Foundation

/// Testing aid: turns one detected person into a row of identical people, so multi-person
/// receivers can be exercised by a single tester.
enum MultiPoseTest {
    /// Copies are never packed tighter than this fraction of the frame width, which caps the
    /// row at 20 poses even when the detected person is very narrow or far away.
    static let minimumSpacing = 0.05

    /// When exactly one pose is given, returns it plus copies shifted left and right by whole
    /// multiples of its bounding-box width, as many as fit entirely inside the frame. The
    /// result is ordered left to right with `id` renumbered to match; the original keeps its
    /// position. Any other number of poses is returned unchanged.
    static func expand(_ poses: [Pose]) -> [Pose] {
        guard poses.count == 1, let pose = poses.first else { return poses }
        let box = pose.box
        let step = max(box.width, minimumSpacing)
        let copiesLeft = Int((max(box.x, 0) / step).rounded(.down))
        let copiesRight = Int((max(1 - (box.x + box.width), 0) / step).rounded(.down))

        return (-copiesLeft...copiesRight).enumerated().map { order, multiple in
            let offset = Double(multiple) * step
            return Pose(
                id: order,
                confidence: pose.confidence,
                box: BoundingBox(x: round4(box.x + offset), y: box.y, width: box.width, height: box.height),
                keypoints: pose.keypoints.map {
                    Keypoint(name: $0.name, x: round4($0.x + offset), y: $0.y, confidence: $0.confidence)
                }
            )
        }
    }

    private static func round4(_ v: Double) -> Double { (v * 1_000_000).rounded() / 1_000_000 }
}
