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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.isEnabled = granted
                if granted {
                    print("Notifications enabled")
                } else if let error = error {
                    print("Notification authorization error: \(error)")
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
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

extension NotificationManager: UNUserNotificationCenterDelegate {
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