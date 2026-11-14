import SwiftUI

/// Draws skeletons over the camera preview, using the same aspect-fit geometry as the preview layer.
struct PoseOverlay: View {
    @ObservedObject var live: LiveState
    let mirrored: Bool
    let fallbackSize: CGSize

    private static let minimumKeypointConfidence = 0.5
    private static let palette: [Color] = [.green, .cyan, .yellow, .orange, .pink, .purple]

    var body: some View {
        Canvas { context, size in
            let frameSize = live.frameSize.width > 0 ? live.frameSize : fallbackSize
            guard frameSize.width > 0, frameSize.height > 0 else { return }
            let scale = min(size.width / frameSize.width, size.height / frameSize.height)
            let video = CGRect(
                x: (size.width - frameSize.width * scale) / 2,
                y: (size.height - frameSize.height * scale) / 2,
                width: frameSize.width * scale,
                height: frameSize.height * scale
            )
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: video.minX + (mirrored ? 1 - x : x) * video.width, y: video.minY + y * video.height)
            }

            for pose in live.poses {
                let color = Self.palette[pose.id % Self.palette.count]
                let keypoints = pose.keypoints

                let origin = point(pose.box.x, pose.box.y)
                let corner = point(pose.box.x + pose.box.width, pose.box.y + pose.box.height)
                let box = CGRect(
                    x: min(origin.x, corner.x), y: min(origin.y, corner.y),
                    width: abs(corner.x - origin.x), height: abs(corner.y - origin.y)
                )
                context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(color.opacity(0.5)), lineWidth: 1)

                if keypoints.count == PoseSkeleton.cocoKeypointNames.count {
                    var bones = Path()
                    for (a, b) in PoseSkeleton.cocoBones {
                        guard keypoints[a].confidence >= Self.minimumKeypointConfidence,
                              keypoints[b].confidence >= Self.minimumKeypointConfidence else { continue }
                        bones.move(to: point(keypoints[a].x, keypoints[a].y))
                        bones.addLine(to: point(keypoints[b].x, keypoints[b].y))
                    }
                    context.stroke(bones, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                for keypoint in keypoints where keypoint.confidence >= Self.minimumKeypointConfidence {
                    let center = point(keypoint.x, keypoint.y)
                    let dot = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                    context.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
