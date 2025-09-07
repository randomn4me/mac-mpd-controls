import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var showNotifications: Bool = false
    @State private var updateInterval: Double = 5.0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("MPD Controls Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            GroupBox("MPD Server") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Host:")
                            .frame(width: 80, alignment: .trailing)
                        TextField("127.0.0.1", text: $host)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Port:")
                            .frame(width: 80, alignment: .trailing)
                        TextField("6600", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        Text("Status: \(connectionStatusText)")
                            .font(.caption)
                            .foregroundColor(connectionStatusColor)
                    }
                }
                .padding()
            }
            
            GroupBox("Preferences") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show notifications for track changes", isOn: $showNotifications)
                        .disabled(true) // Not implemented yet
                    
                    HStack {
                        Text("Update interval:")
                        Slider(value: $updateInterval, in: 1...30, step: 1)
                            .frame(width: 150)
                        Text("\(Int(updateInterval))s")
                            .frame(width: 30)
                    }
                }
                .padding()
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Apply") {
                    applySettings()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private var connectionStatusText: String {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    private var connectionStatusColor: Color {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .secondary
        case .failed:
            return .red
        }
    }
    
    private func loadCurrentSettings() {
        host = UserDefaults.standard.string(forKey: "mpd_host") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "mpd_port")
        port = savedPort > 0 ? String(savedPort) : "6600"
        showNotifications = appState.settings.showNotifications
        updateInterval = appState.settings.updateInterval
    }
    
    private func applySettings() {
        // Validate port
        guard let portNumber = UInt16(port), portNumber > 0 else {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Invalid Port"
            alert.informativeText = "Please enter a valid port number between 1 and 65535."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        // Update settings
        appState.settings.showNotifications = showNotifications
        appState.settings.updateInterval = updateInterval
        
        // Update MPD connection
        appState.updateMPDConnection(host: host.isEmpty ? "127.0.0.1" : host, port: portNumber)
        
        dismiss()
    }
}