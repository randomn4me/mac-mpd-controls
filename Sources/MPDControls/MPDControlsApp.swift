import SwiftUI
import AppKit

@main
struct MPDControlsApp: App {
    @StateObject private var appState = AppState()
    @State private var updateTimer: Timer?
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    @Published var mpdClient: MPDClient
    @Published var mediaKeyHandler: MediaKeyHandler?
    @Published var settings = Settings()
    
    private var updateTimer: Timer?
    
    init() {
        let host = UserDefaults.standard.string(forKey: "mpd_host") ?? "127.0.0.1"
        let port = UInt16(UserDefaults.standard.integer(forKey: "mpd_port"))
        let actualPort = port > 0 ? port : 6600
        
        self.mpdClient = MPDClient(host: host, port: actualPort)
        self.mediaKeyHandler = MediaKeyHandler(mpdClient: mpdClient)
        
        // Auto-connect on launch
        connectToMPD()
        
        // Start media key listening
        mediaKeyHandler?.startListening()
        
        // Setup update timer
        startUpdateTimer()
    }
    
    deinit {
        stopUpdateTimer()
        mediaKeyHandler?.stopListening()
        mpdClient.disconnect()
    }
    
    func connectToMPD() {
        mpdClient.connect()
    }
    
    func disconnectFromMPD() {
        mpdClient.disconnect()
    }
    
    func updateMPDConnection(host: String, port: UInt16) {
        // Save to UserDefaults
        UserDefaults.standard.set(host, forKey: "mpd_host")
        UserDefaults.standard.set(port, forKey: "mpd_port")
        
        // Reconnect with new settings
        mpdClient.disconnect()
        mpdClient = MPDClient(host: host, port: port)
        mediaKeyHandler = MediaKeyHandler(mpdClient: mpdClient)
        mediaKeyHandler?.startListening()
        mpdClient.connect()
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: settings.updateInterval, repeats: true) { _ in
            if self.mpdClient.connectionStatus == .connected {
                self.mpdClient.updateStatus()
                self.mpdClient.updateCurrentSong()
            } else if self.mpdClient.connectionStatus == .disconnected {
                // Auto-reconnect
                self.mpdClient.connect()
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

struct Settings {
    var updateInterval: TimeInterval = 5.0
    var showNotifications: Bool = false
}