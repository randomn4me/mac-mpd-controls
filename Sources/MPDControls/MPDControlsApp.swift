import Foundation
import AppKit

// Logger for handling verbose output and file logging
class Logger {
    static let shared = Logger()
    private var logFile: FileHandle?
    private var verbose = false
    
    func setup(verbose: Bool, logFile: String?) {
        self.verbose = verbose
        
        if let logPath = logFile {
            let url = URL(fileURLWithPath: logPath)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            do {
                self.logFile = try FileHandle(forWritingTo: url)
                self.logFile?.seekToEndOfFile()
            } catch {
                print("Error: Could not open log file '\(logPath)': \(error)")
            }
        }
    }
    
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if verbose {
            print(message)
        }
        
        if let logFile = logFile {
            logFile.write(logMessage.data(using: .utf8) ?? Data())
        }
    }
    
    deinit {
        logFile?.closeFile()
    }
}

// Configuration structure for command line arguments
struct Configuration {
    var host: String = "127.0.0.1"
    var port: UInt16 = 6600
    var updateInterval: TimeInterval = 2.0
    var showNotifications: Bool = true
    var autoReconnect: Bool = true
    var useSystemNowPlaying: Bool = true
    var musicDirectory: String?
    var verbose: Bool = false
    var logFile: String?
    var help: Bool = false
    
    init(arguments: [String]) {
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case "-h", "--help":
                help = true
            case "-v", "--verbose":
                verbose = true
            case "--host":
                if i + 1 < arguments.count {
                    host = arguments[i + 1]
                    i += 1
                }
            case "--port":
                if i + 1 < arguments.count {
                    port = UInt16(arguments[i + 1]) ?? 6600
                    i += 1
                }
            case "--update-interval":
                if i + 1 < arguments.count {
                    updateInterval = TimeInterval(arguments[i + 1]) ?? 2.0
                    i += 1
                }
            case "--no-notifications":
                showNotifications = false
            case "--no-auto-reconnect":
                autoReconnect = false
            case "--no-system-now-playing":
                useSystemNowPlaying = false
            case "--music-directory":
                if i + 1 < arguments.count {
                    musicDirectory = arguments[i + 1]
                    i += 1
                }
            case "--log-file":
                if i + 1 < arguments.count {
                    logFile = arguments[i + 1]
                    i += 1
                }
            default:
                if !arg.starts(with: "-") {
                    // Ignore unknown arguments
                }
            }
            i += 1
        }
    }
    
    func printHelp() {
        print("""
        MPD Controls - A command-line MPD client with system Now Playing integration
        
        USAGE:
            MPDControls [OPTIONS]
        
        OPTIONS:
            -h, --help                      Show this help message
            -v, --verbose                   Enable verbose logging to stdout
            --host HOST                     MPD server host (default: 127.0.0.1)
            --port PORT                     MPD server port (default: 6600)
            --update-interval SECONDS       Update interval in seconds (default: 2.0)
            --no-notifications             Disable desktop notifications
            --no-auto-reconnect            Disable automatic reconnection
            --no-system-now-playing        Disable system Now Playing integration
            --music-directory PATH          Path to music directory for album art
            --log-file PATH                 Log to file instead of/in addition to stdout
        
        EXAMPLES:
            MPDControls --host 192.168.1.100 --port 6600 -v
            MPDControls --music-directory ~/Music --log-file ~/.mpd-controls.log
            MPDControls --no-notifications --update-interval 5.0
        """)
    }
}

@main
struct MPDControlsApp {
    static func main() {
        let config = Configuration(arguments: CommandLine.arguments)
        
        if config.help {
            config.printHelp()
            return
        }
        
        // Setup logging
        Logger.shared.setup(verbose: config.verbose, logFile: config.logFile)
        Logger.shared.log("MPD Controls starting...")
        Logger.shared.log("Configuration: host=\(config.host), port=\(config.port), update_interval=\(config.updateInterval)")
        
        // Create and start the app state
        let _ = AppState(config: config)
        
        // Set up signal handlers for clean shutdown
        signal(SIGINT) { _ in
            Logger.shared.log("Received SIGINT, shutting down...")
            exit(0)
        }
        
        signal(SIGTERM) { _ in
            Logger.shared.log("Received SIGTERM, shutting down...")
            exit(0)
        }
        
        Logger.shared.log("MPD Controls started. Press Ctrl+C to stop.")
        
        // Keep the app running
        NSApplication.shared.run()
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var mpdClient: MPDClient
    @Published var mediaKeyHandler: MediaKeyHandler?
    @Published var notificationManager: NotificationManager?
    @Published var systemNowPlayingManager: SystemNowPlayingManager?
    
    private var config: Configuration
    private var updateTimer: Timer?
    
    init(config: Configuration) {
        self.config = config
        
        Logger.shared.log("AppState initializing...")
        Logger.shared.log("MPD settings: \(config.host):\(config.port)")
        
        self.mpdClient = MPDClient(host: config.host, port: config.port)
        self.mediaKeyHandler = MediaKeyHandler(mpdClient: mpdClient)
        self.notificationManager = NotificationManager(mpdClient: mpdClient)
        self.systemNowPlayingManager = SystemNowPlayingManager(mpdClient: mpdClient)
        
        // Configure music directory if provided
        if let musicDir = config.musicDirectory {
            Logger.shared.log("Setting music directory: \(musicDir)")
            systemNowPlayingManager?.setMusicDirectory(musicDir)
        }
        
        // Auto-connect on launch
        connectToMPD()
        
        // Start media key listening on main thread
        DispatchQueue.main.async {
            self.mediaKeyHandler?.startListening()
        }
        
        // Enable notifications if settings allow
        notificationManager?.setEnabled(config.showNotifications)
        Logger.shared.log("Notifications: \(config.showNotifications ? "enabled" : "disabled")")
        
        // Enable system now playing if settings allow
        systemNowPlayingManager?.setEnabled(config.useSystemNowPlaying)
        Logger.shared.log("System Now Playing: \(config.useSystemNowPlaying ? "enabled" : "disabled")")
        
        // Setup update timer
        startUpdateTimer()
        
        // Listen for MPD status changes from idle mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMPDStatusChanged),
            name: Notification.Name("MPDStatusChanged"),
            object: nil
        )
        
        Logger.shared.log("AppState initialization complete")
    }
    
    deinit {
        Task { @MainActor in
            self.stopUpdateTimer()
        }
        Logger.shared.log("AppState deinitialized")
    }
    
    func connectToMPD() {
        Logger.shared.log("Connecting to MPD server...")
        mpdClient.connect()
    }
    
    func disconnectFromMPD() {
        Logger.shared.log("Disconnecting from MPD server...")
        mpdClient.disconnect()
    }
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        Logger.shared.log("Starting update timer with interval: \(config.updateInterval)s")
        updateTimer = Timer.scheduledTimer(withTimeInterval: config.updateInterval, repeats: true) { _ in
            Task { @MainActor in
                if self.mpdClient.connectionStatus == .connected {
                    self.mpdClient.updateStatus()
                    // Still periodically update current song for streaming metadata changes
                    self.mpdClient.updateCurrentSong()
                    self.notificationManager?.checkForSongChange()
                    self.systemNowPlayingManager?.updateNowPlayingInfo()
                } else if self.mpdClient.connectionStatus == .disconnected {
                    // Auto-reconnect if enabled
                    if self.config.autoReconnect {
                        Logger.shared.log("Auto-reconnecting to MPD server...")
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
        // Update components when MPD status changes via idle mode
        notificationManager?.checkForSongChange()
        systemNowPlayingManager?.updateNowPlayingInfo()
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        Logger.shared.log("Update timer stopped")
    }
}