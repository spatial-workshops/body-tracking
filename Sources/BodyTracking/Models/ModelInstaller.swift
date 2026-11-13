import CoreML
import Foundation

enum ModelInstallError: LocalizedError {
    case downloadFailed(String)
    case unzipFailed(Int32)
    case noModelFound
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): return "Download failed: \(reason)"
        case .unzipFailed(let status): return "Could not unpack the model archive (ditto exited with \(status))."
        case .noModelFound: return "The archive does not contain a Core ML model."
        case .unsupportedFile(let ext): return "Unsupported model file type “.\(ext)”. Use .mlpackage, .mlmodel, .mlmodelc or a zip of one."
        }
    }
}

/// Stateless steps for turning a model source (remote zip, local package) into a compiled .mlmodelc.
enum ModelInstaller {
    static let modelExtensions: Set<String> = ["mlpackage", "mlmodel", "mlmodelc"]

    /// Downloads to a temporary file and returns its location.
    static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        final class ObservationBox: @unchecked Sendable { var observation: NSKeyValueObservation? }
        let box = ObservationBox()
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                box.observation = nil
                if let error {
                    continuation.resume(throwing: ModelInstallError.downloadFailed(error.localizedDescription))
                    return
                }
                guard let location, let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: ModelInstallError.downloadFailed("no response"))
                    return
                }
                guard http.statusCode == 200 else {
                    continuation.resume(throwing: ModelInstallError.downloadFailed("HTTP \(http.statusCode)"))
                    return
                }
                do {
                    // The system deletes `location` when this handler returns, so move it first.
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent("bodytracking-\(UUID().uuidString).zip")
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            box.observation = task.progress.observe(\.fractionCompleted) { taskProgress, _ in
                progress(taskProgress.fractionCompleted)
            }
            task.resume()
        }
    }

    /// Compiles (if needed) the model at `source` and places the result at `destination` (.mlmodelc).
    /// `source` may be a .zip, .mlpackage, .mlmodel or .mlmodelc.
    static func install(from source: URL, to destination: URL) async throws {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent("bodytracking-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        var modelURL = source
        if source.pathExtension.lowercased() == "zip" {
            let unpacked = workDirectory.appendingPathComponent("unpacked")
            try unzip(source, to: unpacked)
            modelURL = try locateModel(in: unpacked)
        }

        let ext = modelURL.pathExtension.lowercased()
        guard modelExtensions.contains(ext) else { throw ModelInstallError.unsupportedFile(ext) }

        let staged = workDirectory.appendingPathComponent("staged.mlmodelc")
        if ext == "mlmodelc" {
            try fileManager.copyItem(at: modelURL, to: staged)
        } else {
            let compiled = try await MLModel.compileModel(at: modelURL)
            try fileManager.moveItem(at: compiled, to: staged)
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staged, to: destination)
    }

    private static func unzip(_ archive: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ModelInstallError.unzipFailed(process.terminationStatus) }
    }

    /// Finds the model inside an unpacked archive. Some archives contain `name.mlpackage/…`,
    /// others contain the package's contents (`Manifest.json`, `Data/`) at the top level.
    private static func locateModel(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("Manifest.json").path) {
            let package = directory.deletingLastPathComponent().appendingPathComponent("model.mlpackage")
            try fileManager.moveItem(at: directory, to: package)
            return package
        }
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent != "__MACOSX" }
        if let model = children.first(where: { modelExtensions.contains($0.pathExtension.lowercased()) }) {
            return model
        }
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let model = try? locateModel(in: child) { return model }
        }
        throw ModelInstallError.noModelFound
    }
}
