import CoreImage
import CoreML
import CoreVideo
import Foundation

enum PoseDetectorError: LocalizedError {
    case noImageInput
    case noTensorOutput
    case bufferAllocationFailed
    case emptyImage

    var errorDescription: String? {
        switch self {
        case .noImageInput: return "The model has no image input."
        case .noTensorOutput: return "The model has no multi-array output."
        case .bufferAllocationFailed: return "Could not allocate the model input buffer."
        case .emptyImage: return "The frame is empty."
        }
    }
}

/// Runs a compiled Core ML YOLO pose model on camera frames.
/// Not thread-safe: call `detect` from one queue at a time.
final class PoseDetector: @unchecked Sendable {
    let inputWidth: Int
    let inputHeight: Int

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let inputBuffer: CVPixelBuffer

    init(compiledModelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        let description = model.modelDescription

        guard let input = description.inputDescriptionsByName
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.type == .image }),
            let constraint = input.value.imageConstraint
        else { throw PoseDetectorError.noImageInput }

        guard let output = description.outputDescriptionsByName
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.type == .multiArray })
        else { throw PoseDetectorError.noTensorOutput }

        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault, constraint.pixelsWide, constraint.pixelsHigh,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard let buffer else { throw PoseDetectorError.bufferAllocationFailed }

        self.model = model
        self.inputName = input.key
        self.outputName = output.key
        self.inputWidth = constraint.pixelsWide
        self.inputHeight = constraint.pixelsHigh
        self.inputBuffer = buffer
    }

    func detect(pixelBuffer: CVPixelBuffer, confidenceThreshold: Float) throws -> [Pose] {
        try detect(image: CIImage(cvPixelBuffer: pixelBuffer), confidenceThreshold: confidenceThreshold)
    }

    func detect(image: CIImage, confidenceThreshold: Float) throws -> [Pose] {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { throw PoseDetectorError.emptyImage }

        // Letterbox: scale uniformly to fit the model input and center on gray, as YOLO is trained.
        let targetWidth = Double(inputWidth), targetHeight = Double(inputHeight)
        let scale = min(targetWidth / extent.width, targetHeight / extent.height)
        let padX = (targetWidth - extent.width * scale) / 2
        let padY = (targetHeight - extent.height * scale) / 2
        let letterbox = Letterbox(scale: scale, padX: padX, padY: padY, sourceWidth: extent.width, sourceHeight: extent.height)

        let target = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: padX, y: padY))
        let gray = CIColor(red: 114.0 / 255, green: 114.0 / 255, blue: 114.0 / 255)
        let composed = image
            .transformed(by: transform)
            .composited(over: CIImage(color: gray))
            .cropped(to: target)
        context.render(composed, to: inputBuffer, bounds: target, colorSpace: colorSpace)

        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: inputBuffer)])
        let result = try model.prediction(from: provider)
        guard let array = result.featureValue(for: outputName)?.multiArrayValue else {
            throw PoseDetectorError.noTensorOutput
        }
        let shaped = MLShapedArray<Float>(converting: array)
        return try PoseDecoder.decode(
            scalars: shaped.scalars,
            shape: shaped.shape,
            letterbox: letterbox,
            confidenceThreshold: confidenceThreshold
        )
    }
}
