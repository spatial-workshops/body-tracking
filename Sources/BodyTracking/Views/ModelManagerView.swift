import AppKit
import SwiftUI

/// Lists downloadable and imported models; download, delete, import.
struct ModelManagerView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            List(store.models) { info in
                ModelRow(info: info)
            }
            Divider()
            HStack {
                Button("Import Core ML Model…") { importModel() }
                    .disabled(isImporting)
                if isImporting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.open(store.root) }
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { store.refresh() }
        .alert("Could not import model", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.message = "Choose a YOLO pose model: .mlpackage, .mlmodel, .mlmodelc, or a zip of one."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImporting = true
        Task {
            do {
                try await store.importModel(from: url)
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }
}

private struct ModelRow: View {
    @EnvironmentObject private var store: ModelStore
    let info: ModelInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            switch store.state(for: info.id) {
            case .installed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Delete", role: .destructive) { store.remove(info.id) }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 100)
            case .installing:
                ProgressView().controlSize(.small)
                Text("Compiling…").font(.caption).foregroundStyle(.secondary)
            case .notInstalled, .failed:
                if info.isBuiltIn {
                    Button("Download") {
                        Task { _ = try? await store.ensureInstalled(info.id) }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if case .failed(let message) = store.state(for: info.id) { return message }
        if let size = info.downloadSizeMB {
            return "\(info.detail) · \(String(format: "%.1f", size)) MB download"
        }
        return info.detail
    }
}
