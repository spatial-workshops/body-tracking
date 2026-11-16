import Foundation

/// A point in canvas pixels.
struct CanvasPoint: Encodable, Equatable {
    let x: Double
    let y: Double
}

/// A point in canvas pixels with the landmark's visibility as its score.
struct ScoredCanvasPoint: Encodable, Equatable {
    let x: Double
    let y: Double
    let score: Double
}

/// One hand of one tracked body, the entry type of the "MediaPipe (modified)" format.
struct TrackedHand: Encodable, Equatable {
    /// "left" or "right": the person's own side.
    let side: String
    let wrist: CanvasPoint
    /// Estimated; see `HandsConverter.indexFingerExtension`.
    let index: CanvasPoint
    /// Index of the body this hand belongs to. Both hands of a body carry the same torso landmarks.
    let body: Int
    let elbow: ScoredCanvasPoint
    /// Midpoint between the shoulders; its score is the lower of the two shoulder scores.
    let torso: ScoredCanvasPoint
    let leftShoulder: ScoredCanvasPoint
    let rightShoulder: ScoredCanvasPoint
    let leftHip: ScoredCanvasPoint
    let rightHip: ScoredCanvasPoint
    /// The nose.
    let head: ScoredCanvasPoint
}

/// Flattens MediaPipe-format poses into a list of hands, two per body (left, then right),
/// with coordinates scaled from normalized 0–1 to a canvas of the given size.
enum HandsConverter {
    /// The index finger is placed on the ray from the elbow through the wrist, this fraction
    /// of the forearm's length beyond the wrist. YOLO does not detect fingers.
    static let indexFingerExtension = 1.0 / 3.0

    // MediaPipe landmark indices.
    private static let nose = 0
    private static let leftShoulder = 11, rightShoulder = 12
    private static let leftElbow = 13, rightElbow = 14
    private static let leftWrist = 15, rightWrist = 16
    private static let leftHip = 23, rightHip = 24

    static func hands(for bodies: [[MediaPipeLandmark]], canvas: CGSize) -> [TrackedHand] {
        let width = Double(canvas.width), height = Double(canvas.height)

        func scored(_ landmark: MediaPipeLandmark) -> ScoredCanvasPoint {
            ScoredCanvasPoint(x: round2(landmark.x * width), y: round2(landmark.y * height), score: landmark.visibility)
        }

        var result: [TrackedHand] = []
        for (bodyIndex, body) in bodies.enumerated() where body.count > rightHip {
            let left = scored(body[leftShoulder]), right = scored(body[rightShoulder])
            let torso = ScoredCanvasPoint(
                x: round2((left.x + right.x) / 2),
                y: round2((left.y + right.y) / 2),
                score: min(left.score, right.score)
            )
            for (side, wristIndex, elbowIndex) in [("left", leftWrist, leftElbow), ("right", rightWrist, rightElbow)] {
                let wrist = body[wristIndex], elbow = body[elbowIndex]
                let indexX = wrist.x + (wrist.x - elbow.x) * indexFingerExtension
                let indexY = wrist.y + (wrist.y - elbow.y) * indexFingerExtension
                result.append(TrackedHand(
                    side: side,
                    wrist: CanvasPoint(x: round2(wrist.x * width), y: round2(wrist.y * height)),
                    index: CanvasPoint(x: round2(indexX * width), y: round2(indexY * height)),
                    body: bodyIndex,
                    elbow: scored(elbow),
                    torso: torso,
                    leftShoulder: left,
                    rightShoulder: right,
                    leftHip: scored(body[leftHip]),
                    rightHip: scored(body[rightHip]),
                    head: scored(body[nose])
                ))
            }
        }
        return result
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

extension Pose {
    /// The same pose as seen in a mirror: x becomes 1 − x. Left and right labels are unchanged.
    func flippedHorizontally() -> Pose {
        func flip(_ x: Double) -> Double { ((1 - x) * 1_000_000).rounded() / 1_000_000 }
        return Pose(
            id: id,
            confidence: confidence,
            box: BoundingBox(x: flip(box.x + box.width), y: box.y, width: box.width, height: box.height),
            keypoints: keypoints.map { Keypoint(name: $0.name, x: flip($0.x), y: $0.y, confidence: $0.confidence) }
        )
    }
}
