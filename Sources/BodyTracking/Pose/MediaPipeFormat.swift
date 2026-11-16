import Foundation

/// How a window formats `payload.data`.
enum OutputFormat: String, CaseIterable, Identifiable {
    /// A flat list of hands derived from the MediaPipe layout, in canvas pixels.
    case hands = "mediapipe-modified"
    /// MediaPipe Pose Landmarker layout: 33 landmarks per person.
    case mediaPipe = "mediapipe"
    /// The app's native layout: 17 named COCO keypoints plus a bounding box per person.
    case yolo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hands: return "MediaPipe (modified)"
        case .mediaPipe: return "MediaPipe (33 landmarks)"
        case .yolo: return "YOLO (17 keypoints)"
        }
    }
}

/// `payload.data` in either format.
enum PoseData: Encodable {
    case yolo([Pose])
    case mediaPipe([[MediaPipeLandmark]])
    case hands([TrackedHand])

    /// `canvas` is the size the hands format scales normalized coordinates to.
    init(_ poses: [Pose], format: OutputFormat, canvas: CGSize) {
        switch format {
        case .hands: self = .hands(HandsConverter.hands(for: poses.map(MediaPipeConverter.landmarks), canvas: canvas))
        case .yolo: self = .yolo(poses)
        case .mediaPipe: self = .mediaPipe(poses.map(MediaPipeConverter.landmarks))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .yolo(let poses): try container.encode(poses)
        case .mediaPipe(let landmarks): try container.encode(landmarks)
        case .hands(let hands): try container.encode(hands)
        }
    }
}

/// One entry of MediaPipe's `NormalizedLandmark` list.
struct MediaPipeLandmark: Encodable, Equatable {
    let x: Double
    let y: Double
    let z: Double
    let visibility: Double
}

/// Translates YOLO's 17 COCO keypoints into MediaPipe Pose Landmarker's 33-landmark topology,
/// matching the `landmarks` field of a `PoseLandmarkerResult`: one array of 33
/// `{x, y, z, visibility}` objects per person, normalized to the image with a top-left origin.
///
/// 17 of the 33 landmarks have a direct COCO counterpart and carry the keypoint's position
/// and confidence. YOLO does not detect the other 16 (inner/outer eye corners, mouth, fingers,
/// heels, toes); those take the position of the nearest detected joint and `visibility` 0,
/// so the array keeps MediaPipe's indices and consumers can tell them apart.
/// `z` is always 0: YOLO pose has no depth estimate.
enum MediaPipeConverter {
    /// For each MediaPipe landmark index: the COCO keypoint it comes from, and whether that
    /// is the same body point (`true`) or only the nearest detected joint (`false`).
    static let mapping: [(source: String, detected: Bool)] = [
        ("nose", true),             //  0 nose
        ("left_eye", false),        //  1 left eye (inner)
        ("left_eye", true),         //  2 left eye
        ("left_eye", false),        //  3 left eye (outer)
        ("right_eye", false),       //  4 right eye (inner)
        ("right_eye", true),        //  5 right eye
        ("right_eye", false),       //  6 right eye (outer)
        ("left_ear", true),         //  7 left ear
        ("right_ear", true),        //  8 right ear
        ("nose", false),            //  9 mouth (left)
        ("nose", false),            // 10 mouth (right)
        ("left_shoulder", true),    // 11 left shoulder
        ("right_shoulder", true),   // 12 right shoulder
        ("left_elbow", true),       // 13 left elbow
        ("right_elbow", true),      // 14 right elbow
        ("left_wrist", true),       // 15 left wrist
        ("right_wrist", true),      // 16 right wrist
        ("left_wrist", false),      // 17 left pinky
        ("right_wrist", false),     // 18 right pinky
        ("left_wrist", false),      // 19 left index
        ("right_wrist", false),     // 20 right index
        ("left_wrist", false),      // 21 left thumb
        ("right_wrist", false),     // 22 right thumb
        ("left_hip", true),         // 23 left hip
        ("right_hip", true),        // 24 right hip
        ("left_knee", true),        // 25 left knee
        ("right_knee", true),       // 26 right knee
        ("left_ankle", true),       // 27 left ankle
        ("right_ankle", true),      // 28 right ankle
        ("left_ankle", false),      // 29 left heel
        ("right_ankle", false),     // 30 right heel
        ("left_ankle", false),      // 31 left foot index
        ("right_ankle", false),     // 32 right foot index
    ]

    static func landmarks(for pose: Pose) -> [MediaPipeLandmark] {
        let byName = Dictionary(pose.keypoints.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return mapping.map { entry in
            guard let keypoint = byName[entry.source] else {
                return MediaPipeLandmark(x: 0, y: 0, z: 0, visibility: 0)
            }
            return MediaPipeLandmark(
                x: keypoint.x,
                y: keypoint.y,
                z: 0,
                visibility: entry.detected ? keypoint.confidence : 0
            )
        }
    }
}
