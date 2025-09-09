import SwiftUI
import AppKit

@main
struct MPDControlsApp: App {
    @StateObject private var appState = AppState()
    @State private var updateTimer: Timer?
    
    var body: some Scene {
        MenuBarExtra {
            if appState.settings.showSeparateMenuBar {
                MenuBarView(appState: appState)
            } else {
                // Create minimal menu when using system now playing only
                VStack(alignment: .leading, spacing: 8) {
                    Text("MPD Controls")
                        .font(.headline)
                    
                    Text("Using system Now Playing controls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Button("Open Settings") {
                        // TODO: Add settings action
                    }
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding()
            }
        } label: {
            if appState.settings.showSeparateMenuBar {
                MenuBarLabel(appState: appState)
            } else {
                // Show minimal indicator
                Image(systemName: "music.note")
                    .opacity(0.6)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var mpdClient: MPDClient
    @Published var mediaKeyHandler: MediaKeyHandler?
    @Published var notificationManager: NotificationManager?
    @Published var systemNowPlayingManager: SystemNowPlayingManager?
    @Published var settings = Settings()
    
    private var updateTimer: Timer?
    
    init() {
        print("AppState initializing...")
        let host = UserDefaults.standard.string(forKey: "mpd_host") ?? "127.0.0.1"
        let port = UInt16(UserDefaults.standard.integer(forKey: "mpd_port"))
        let actualPort = port > 0 ? port : 6600
        
        print("MPD settings: \(host):\(actualPort)")
        
        self.mpdClient = MPDClient(host: host, port: actualPort)
        self.mediaKeyHandler = MediaKeyHandler(mpdClient: mpdClient)
        self.notificationManager = NotificationManager(mpdClient: mpdClient)
        self.systemNowPlayingManager = SystemNowPlayingManager(mpdClient: mpdClient)
        
        // Load settings from UserDefaults
        loadSettings()
        
        // Auto-connect on launch
        connectToMPD()
        
        // Start media key listening on main thread
        DispatchQueue.main.async {
            self.mediaKeyHandler?.startListening()
        }
        
        // Enable notifications if settings allow
        notificationManager?.setEnabled(settings.showNotifications)
        
        // Enable system now playing if settings allow
        systemNowPlayingManager?.setEnabled(settings.useSystemNowPlaying)
        
        // Setup update timer
        startUpdateTimer()
        
        // Listen for MPD status changes from idle mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMPDStatusChanged),
            name: Notification.Name("MPDStatusChanged"),
            object: nil
        )
        
        print("AppState initialization complete")
    }
    
    deinit {
        // Cleanup handled by system
    }
    
    func loadSettings() {
        settings.updateInterval = UserDefaults.standard.double(forKey: "mpd_update_interval") 
        if settings.updateInterval <= 0 { settings.updateInterval = 10.0 }
        
        if UserDefaults.standard.object(forKey: "mpd_show_notifications") != nil {
            settings.showNotifications = UserDefaults.standard.bool(forKey: "mpd_show_notifications")
        } else {
            settings.showNotifications = true
        }
        
        if UserDefaults.standard.object(forKey: "mpd_auto_reconnect") != nil {
            settings.autoReconnect = UserDefaults.standard.bool(forKey: "mpd_auto_reconnect")
        } else {
            settings.autoReconnect = true
        }
        
        if UserDefaults.standard.object(forKey: "mpd_use_system_now_playing") != nil {
            settings.useSystemNowPlaying = UserDefaults.standard.bool(forKey: "mpd_use_system_now_playing")
        } else {
            settings.useSystemNowPlaying = true
        }
        
        settings.showSeparateMenuBar = UserDefaults.standard.bool(forKey: "mpd_show_separate_menu_bar")
    }
    
    func saveSettings() {
        UserDefaults.standard.set(settings.updateInterval, forKey: "mpd_update_interval")
        UserDefaults.standard.set(settings.showNotifications, forKey: "mpd_show_notifications")
        UserDefaults.standard.set(settings.autoReconnect, forKey: "mpd_auto_reconnect")
        UserDefaults.standard.set(settings.useSystemNowPlaying, forKey: "mpd_use_system_now_playing")
        UserDefaults.standard.set(settings.showSeparateMenuBar, forKey: "mpd_show_separate_menu_bar")
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
        
        // Properly stop the old media key handler before creating a new one
        mediaKeyHandler?.stopListening()
        
        // Reconnect with new settings
        mpdClient.disconnect()
        mpdClient = MPDClient(host: host, port: port)
        mediaKeyHandler = MediaKeyHandler(mpdClient: mpdClient)
        mediaKeyHandler?.startListening()
        notificationManager = NotificationManager(mpdClient: mpdClient)
        notificationManager?.setEnabled(settings.showNotifications)
        systemNowPlayingManager = SystemNowPlayingManager(mpdClient: mpdClient)
        systemNowPlayingManager?.setEnabled(settings.useSystemNowPlaying)
        mpdClient.connect()
    }
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: settings.updateInterval, repeats: true) { _ in
            Task { @MainActor in
                if self.mpdClient.connectionStatus == .connected {
                    self.mpdClient.updateStatus()
                    self.mpdClient.updateCurrentSong()
                    self.notificationManager?.checkForSongChange()
                    self.systemNowPlayingManager?.updateNowPlayingInfo()
                } else if self.mpdClient.connectionStatus == .disconnected {
                    // Auto-reconnect if enabled
                    if self.settings.autoReconnect {
                        self.mpdClient.connect()
                    }
                }
            }
        }
    }
    
    func restartUpdateTimer() {
        startUpdateTimer()
    }
    
    @objc private func handleMPDStatusChanged() {
        // Update UI components when MPD status changes via idle mode
        notificationManager?.checkForSongChange()
        systemNowPlayingManager?.updateNowPlayingInfo()
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

struct Settings {
    var updateInterval: TimeInterval = 10.0  // Fallback polling (idle mode handles real-time updates)
    var showNotifications: Bool = true
    var autoReconnect: Bool = true
    var notificationSound: Bool = false
    var useSystemNowPlaying: Bool = true  // Default to Now Playing integration
    var showSeparateMenuBar: Bool = false // Optional separate menu bar icon
}