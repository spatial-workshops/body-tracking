import SwiftUI

extension WebSocketClient.State {
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .waitingToRetry: return "Waiting to reconnect…"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting, .waitingToRetry: return .orange
        case .connected: return .green
        }
    }
}

/// Connect / Disconnect, shared by the status bar and the settings window.
struct ConnectionButton: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var socket: WebSocketClient

    var body: some View {
        if socket.isActive {
            Button("Disconnect") { socket.disconnect() }
        } else {
            Button("Connect") {
                socket.connect(to: settings.serverURL, clientId: settings.resolvedClientId())
            }
        }
    }
}

/// Status strip at the bottom of every tracker window for the app-wide connection.
struct ConnectionBar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var socket: WebSocketClient

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(socket.state.color)
                .frame(width: 9, height: 9)
            Text(socket.state.label)
            Text(socket.activeURL?.absoluteString ?? settings.serverURL)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if socket.state != .connected, let error = socket.lastError {
                Text("— \(error)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            ConnectionButton()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Connection settings")
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// App-wide options (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var socket: WebSocketClient

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $settings.serverURL, prompt: Text(AppSettings.defaultServerURL))
                    .disabled(socket.isActive)
                LabeledContent("Client ID") {
                    HStack {
                        TextField("Client ID", text: $settings.clientId)
                            .labelsHidden()
                            .font(.body.monospaced())
                        Button("New UUID") { settings.regenerateClientId() }
                    }
                }
                .disabled(socket.isActive)
                Toggle("Connect when the app launches", isOn: $settings.connectOnLaunch)
            } header: {
                Text("WebSocket Server")
            } footer: {
                if socket.isActive {
                    Text("Disconnect to change the server URL or client ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Connection") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(socket.state.color).frame(width: 9, height: 9)
                        Text(socket.state.label)
                    }
                }
                if socket.state != .connected, let error = socket.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ConnectionButton()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
