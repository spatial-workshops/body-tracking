import AVFoundation
import CoreMedia
import Foundation

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct Resolution: Identifiable, Hashable {
    let width: Int
    let height: Int

    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init?(id: String) {
        let parts = id.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(width: parts[0], height: parts[1])
    }

    /// 1920×1080 if offered, otherwise the largest mode up to 1080p, otherwise the smallest.
    static func preferred(in resolutions: [Resolution]) -> Resolution? {
        if let fullHD = resolutions.first(where: { $0.width == 1920 && $0.height == 1080 }) { return fullHD }
        return resolutions.last(where: { $0.width <= 1920 && $0.height <= 1080 }) ?? resolutions.first
    }
}

enum CameraError: LocalizedError {
    case deviceUnavailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "The selected camera is not available."
        case .cannotAddInput: return "The selected camera could not be opened."
        case .cannotAddOutput: return "Could not read frames from the camera."
        }
    }
}

/// One capture session feeding one tracker window.
final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Called on a background queue for every camera frame. Set before calling `start`.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let sessionQueue = DispatchQueue(label: "bodytracking.camera.session")
    private let videoQueue = DispatchQueue(label: "bodytracking.camera.video")
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?

    // MARK: - Discovery

    static func availableCameras() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func defaultCameraID() -> String? {
        AVCaptureDevice.default(for: .video)?.uniqueID
    }

    /// The distinct frame sizes a camera offers, smallest first.
    static func resolutions(for deviceID: String) -> [Resolution] {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { return [] }
        let all = device.formats.map { format -> Resolution in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Resolution(width: Int(dimensions.width), height: Int(dimensions.height))
        }
        return Array(Set(all)).sorted {
            ($0.width * $0.height, $0.width) < ($1.width * $1.height, $1.width)
        }
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Session control

    /// (Re)starts capture from the given camera. `completion` is called on the main queue.
    func start(deviceID: String, resolution: Resolution?, completion: @escaping @Sendable (Error?) -> Void) {
        sessionQueue.async { [self] in
            do {
                try configureAndRun(deviceID: deviceID, resolution: resolution)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun(deviceID: String, resolution: Resolution?) throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw CameraError.deviceUnavailable }

        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        var committed = false
        defer { if !committed { session.commitConfiguration() } }

        if let input {
            session.removeInput(input)
            self.input = nil
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else { throw CameraError.cannotAddInput }
        session.addInput(newInput)
        input = newInput

        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
            session.addOutput(output)
        }

        // On macOS the session can override the active format when it starts, so the device
        // stays locked until the session is running.
        var locked = false
        if let resolution, let (format, range) = Self.bestFormat(of: device, for: resolution) {
            try device.lockForConfiguration()
            locked = true
            device.activeFormat = format
            device.activeVideoMinFrameDuration = range.minFrameDuration
            device.activeVideoMaxFrameDuration = range.minFrameDuration
        }

        session.commitConfiguration()
        committed = true
        session.startRunning()
        if locked { device.unlockForConfiguration() }
    }

    /// Among the formats with the requested size, picks the one with the highest frame rate.
    private static func bestFormat(
        of device: AVCaptureDevice,
        for resolution: Resolution
    ) -> (AVCaptureDevice.Format, AVFrameRateRange)? {
        var best: (AVCaptureDevice.Format, AVFrameRateRange)?
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard Int(dimensions.width) == resolution.width, Int(dimensions.height) == resolution.height else { continue }
            guard let range = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { continue }
            if best == nil || range.maxFrameRate > best!.1.maxFrameRate {
                best = (format, range)
            }
        }
        return best
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
