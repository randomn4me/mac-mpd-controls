import Foundation
import AppKit
import UserNotifications

@MainActor
public final class NotificationManager: NSObject {
    private let mpdClient: MPDClient
    private var lastSong: MPDClient.Song?
    private var isEnabled: Bool = false
    
    public init(mpdClient: MPDClient) {
        self.mpdClient = mpdClient
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Only setup notifications if we're running in an app context (not command line)
        guard Bundle.main.bundleIdentifier != nil else {
            Logger.shared.log("Skipping notification setup in command-line context")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.isEnabled = granted
                if granted {
                    Logger.shared.log("Notifications enabled")
                } else if let error = error {
                    Logger.shared.log("Notification authorization error: \(error)")
                }
            }
        }
        
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func checkForSongChange() {
        guard isEnabled else { return }
        
        let currentSong = mpdClient.currentSong
        
        if let current = currentSong,
           current != lastSong,
           mpdClient.playerState == .play {
            showNotification(for: current)
            lastSong = current
        }
    }
    
    private func showNotification(for song: MPDClient.Song) {
        let content = UNMutableNotificationContent()
        content.title = song.title ?? "Unknown Title"
        
        var subtitle = ""
        if let artist = song.artist {
            subtitle = artist
        }
        if let album = song.album {
            if !subtitle.isEmpty {
                subtitle += " - "
            }
            subtitle += album
        }
        
        if !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        
        content.sound = nil // Silent notification
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Show immediately
        )
        
        // Only send notifications if we're in an app context
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.log("Failed to show notification: \(error)")
            }
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            checkForSongChange()
        }
    }
}

extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .list])
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification click if needed
        completionHandler()
    }
}