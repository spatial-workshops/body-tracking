import CoreMedia
import CoreVideo
import Foundation

struct DetectionResult: Sendable {
    var poses: [Pose] = []
    var frameSize: CGSize = .zero
    var inferenceMs: Double = 0
    var fps: Double = 0
    var error: String?
}

extension Pose: @unchecked Sendable {}

/// Sits between the camera and the detector: drops frames to hit the target detection
/// rate and runs inference on the camera's delivery queue.
final class FrameProcessor: @unchecked Sendable {
    /// Called on the camera queue after every processed frame.
    var onResult: ((DetectionResult) -> Void)?

    private let lock = NSLock()
    private var detector: PoseDetector?
    private var interval: Double = 1.0 / 15.0
    private var confidence: Float = 0.35
    private var nextDue: Double = 0
    private var lastProcessed: Double?
    private var smoothedFPS: Double = 0

    func setDetector(_ detector: PoseDetector?) {
        lock.withLock { self.detector = detector }
    }

    func setTargetFPS(_ fps: Double) {
        lock.withLock { interval = 1.0 / min(max(fps, 1), 120) }
    }

    func setConfidence(_ value: Double) {
        lock.withLock { confidence = Float(value) }
    }

    func process(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        let now = time.seconds
        guard now.isFinite else { return }

        lock.lock()
        // A new camera restarts the clock; don't wait for the old schedule.
        if now < nextDue - 1 {
            nextDue = now
            lastProcessed = nil
        }
        guard let detector, now >= nextDue - interval * 0.1 else {
            lock.unlock()
            return
        }
        // Keep a steady schedule so the average rate matches the target even when it
        // isn't a divisor of the camera rate (e.g. 20 fps from a 30 fps camera).
        nextDue = max(nextDue + interval, now + interval * 0.5)
        if let last = lastProcessed, now > last {
            let instant = 1 / (now - last)
            smoothedFPS = smoothedFPS == 0 ? instant : smoothedFPS * 0.8 + instant * 0.2
        }
        lastProcessed = now
        let confidence = self.confidence
        let fps = smoothedFPS
        lock.unlock()

        var result = DetectionResult()
        result.fps = fps
        result.frameSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let started = CFAbsoluteTimeGetCurrent()
        do {
            result.poses = try detector.detect(pixelBuffer: pixelBuffer, confidenceThreshold: confidence)
        } catch {
            result.error = error.localizedDescription
        }
        result.inferenceMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
        onResult?(result)
    }
}
