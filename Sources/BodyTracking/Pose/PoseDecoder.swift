import Foundation

/// How a camera frame was fitted into the model's input: uniformly scaled, then centered with padding.
struct Letterbox {
    let scale: Double
    let padX: Double
    let padY: Double
    let sourceWidth: Double
    let sourceHeight: Double
}

enum PoseDecoderError: LocalizedError {
    case unsupportedOutput([Int])

    var errorDescription: String? {
        switch self {
        case .unsupportedOutput(let shape):
            return "Unsupported model output shape \(shape). Expected a single-class YOLO pose model."
        }
    }
}

/// Turns the raw output tensor of an Ultralytics YOLO pose model into poses.
///
/// Two layouts are supported and told apart by shape:
/// - End-to-end / NMS-free (YOLO26): `[1, N, 6 + 3K]`, each row `x1, y1, x2, y2, score, class, K × (x, y, conf)`.
/// - Classic (YOLO11, YOLOv8): `[1, 5 + 3K, anchors]`, channels `cx, cy, w, h, score, K × (x, y, conf)`, needs NMS.
///
/// Coordinates come out of the model in input pixels and are mapped back to the
/// original frame as normalized 0–1 values.
enum PoseDecoder {
    private struct Candidate {
        var x1: Float, y1: Float, x2: Float, y2: Float
        var score: Float
        var index: Int
    }

    static func decode(
        scalars: [Float],
        shape: [Int],
        letterbox: Letterbox,
        confidenceThreshold: Float,
        iouThreshold: Float = 0.45,
        maxPoses: Int = 50
    ) throws -> [Pose] {
        var dims = shape
        while dims.count > 2, dims.first == 1 { dims.removeFirst() }
        guard dims.count == 2, dims[0] > 0, dims[1] > 0, scalars.count == dims[0] * dims[1] else {
            throw PoseDecoderError.unsupportedOutput(shape)
        }

        // The feature axis is the short one: 57 of [300, 57], or 56 of [56, 8400].
        let featuresLast = dims[1] <= dims[0]
        let features = min(dims[0], dims[1])
        let count = max(dims[0], dims[1])

        let endToEnd: Bool
        let keypointOffset: Int
        if features > 6, (features - 6) % 3 == 0 {
            endToEnd = true
            keypointOffset = 6
        } else if features > 5, (features - 5) % 3 == 0 {
            endToEnd = false
            keypointOffset = 5
        } else {
            throw PoseDecoderError.unsupportedOutput(shape)
        }
        let keypointCount = (features - keypointOffset) / 3

        func value(_ item: Int, _ feature: Int) -> Float {
            featuresLast ? scalars[item * features + feature] : scalars[feature * count + item]
        }

        var candidates: [Candidate] = []
        for i in 0..<count {
            let score = value(i, 4)
            guard score >= confidenceThreshold else { continue }
            if endToEnd {
                candidates.append(Candidate(x1: value(i, 0), y1: value(i, 1), x2: value(i, 2), y2: value(i, 3), score: score, index: i))
            } else {
                let cx = value(i, 0), cy = value(i, 1), w = value(i, 2), h = value(i, 3)
                candidates.append(Candidate(x1: cx - w / 2, y1: cy - h / 2, x2: cx + w / 2, y2: cy + h / 2, score: score, index: i))
            }
        }
        candidates.sort { $0.score > $1.score }
        if !endToEnd {
            candidates = nonMaximumSuppression(candidates, iouThreshold: iouThreshold)
        }

        func normX(_ x: Float) -> Double {
            clamp01((Double(x) - letterbox.padX) / letterbox.scale / letterbox.sourceWidth)
        }
        func normY(_ y: Float) -> Double {
            clamp01((Double(y) - letterbox.padY) / letterbox.scale / letterbox.sourceHeight)
        }

        return candidates.prefix(maxPoses).enumerated().map { order, candidate in
            let keypoints = (0..<keypointCount).map { k -> Keypoint in
                let base = keypointOffset + k * 3
                return Keypoint(
                    name: PoseSkeleton.keypointName(k, total: keypointCount),
                    x: round4(normX(value(candidate.index, base))),
                    y: round4(normY(value(candidate.index, base + 1))),
                    confidence: round4(Double(value(candidate.index, base + 2)))
                )
            }
            let x1 = normX(candidate.x1), y1 = normY(candidate.y1)
            let x2 = normX(candidate.x2), y2 = normY(candidate.y2)
            return Pose(
                id: order,
                confidence: round4(Double(candidate.score)),
                box: BoundingBox(x: round4(x1), y: round4(y1), width: round4(max(0, x2 - x1)), height: round4(max(0, y2 - y1))),
                keypoints: keypoints
            )
        }
    }

    /// Greedy NMS over candidates already sorted by descending score.
    private static func nonMaximumSuppression(_ sorted: [Candidate], iouThreshold: Float) -> [Candidate] {
        var kept: [Candidate] = []
        for candidate in sorted {
            if kept.allSatisfy({ iou($0, candidate) <= iouThreshold }) {
                kept.append(candidate)
            }
        }
        return kept
    }

    private static func iou(_ a: Candidate, _ b: Candidate) -> Float {
        let w = max(0, min(a.x2, b.x2) - max(a.x1, b.x1))
        let h = max(0, min(a.y2, b.y2) - max(a.y1, b.y1))
        let intersection = w * h
        let union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - intersection
        return union > 0 ? intersection / union : 0
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    private static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
