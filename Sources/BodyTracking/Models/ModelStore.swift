import Foundation

enum ModelState: Equatable {
    case notInstalled
    case downloading(Double)
    case installing
    case installed
    case failed(String)
}

/// Downloads, compiles, caches and lists pose models.
///
/// Compiled models live in `~/Library/Application Support/BodyTracking/Models/<id>/<id>.mlmodelc`.
@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [ModelInfo] = ModelCatalog.builtIn
    @Published private(set) var states: [String: ModelState] = [:]

    let root: URL
    private var installs: [String: Task<Void, Error>] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = support.appendingPathComponent("BodyTracking/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        refresh()
    }

    func compiledURL(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("\(id).mlmodelc", isDirectory: true)
    }

    func state(for id: String) -> ModelState {
        states[id] ?? .notInstalled
    }

    func info(for id: String) -> ModelInfo? {
        models.first { $0.id == id }
    }

    /// Rebuilds the model list from the catalog plus whatever is on disk.
    func refresh() {
        let fileManager = FileManager.default
        var list = ModelCatalog.builtIn
        let builtInIDs = Set(list.map(\.id))
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = folder.lastPathComponent
            guard !builtInIDs.contains(id), fileManager.fileExists(atPath: compiledURL(for: id).path) else { continue }
            list.append(ModelInfo(id: id, name: id, detail: "Imported", downloadURL: nil, downloadSizeMB: nil))
        }
        models = list
        for model in list where installs[model.id] == nil {
            let installed = fileManager.fileExists(atPath: compiledURL(for: model.id).path)
            if installed {
                states[model.id] = .installed
            } else if case .failed = states[model.id] {
                continue
            } else {
                states[model.id] = .notInstalled
            }
        }
    }

    /// Returns the compiled model's location, downloading and compiling it first if necessary.
    /// Concurrent callers for the same model share one download.
    func ensureInstalled(_ id: String) async throws -> URL {
        let destination = compiledURL(for: id)
        if let running = installs[id] {
            try await running.value
            return destination
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            states[id] = .installed
            return destination
        }
        guard let url = info(for: id)?.downloadURL else {
            states[id] = .notInstalled
            throw ModelInstallError.noModelFound
        }

        states[id] = .downloading(0)
        let task = Task { [weak self] in
            let archive = try await ModelInstaller.download(from: url) { fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.states[id] else { return }
                    self.states[id] = .downloading(fraction)
                }
            }
            defer { try? FileManager.default.removeItem(at: archive) }
            await MainActor.run { self?.states[id] = .installing }
            try await ModelInstaller.install(from: archive, to: destination)
        }
        installs[id] = task
        do {
            try await task.value
            installs[id] = nil
            states[id] = .installed
            return destination
        } catch {
            installs[id] = nil
            states[id] = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Imports a .mlpackage, .mlmodel, .mlmodelc or zip from disk and returns the new model's id.
    @discardableResult
    func importModel(from source: URL) async throws -> String {
        var base = source.deletingPathExtension().lastPathComponent
        if base.lowercased().hasSuffix(".mlpackage") { base = String(base.dropLast(".mlpackage".count)) }
        let safe = base.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "-" }
        var id = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if id.isEmpty { id = "model" }
        if ModelCatalog.builtIn.contains(where: { $0.id == id }) { id += "-custom" }

        states[id] = .installing
        do {
            try await ModelInstaller.install(from: source, to: compiledURL(for: id))
            refresh()
            return id
        } catch {
            states[id] = nil
            refresh()
            throw error
        }
    }

    func remove(_ id: String) {
        guard installs[id] == nil else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
        states[id] = nil
        refresh()
    }
}
