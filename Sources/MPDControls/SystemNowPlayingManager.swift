import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#endif

@MainActor
public final class SystemNowPlayingManager: NSObject {
    private let mpdClient: MPDClient
    private let albumArtManager: AlbumArtManager
    private var isEnabled: Bool = false
    private var lastSongFile: String?
    private var lastAlbumKey: String? // Track album changes
    private var currentArtwork: Any? // Store current MPMediaItemArtwork
    
    public init(mpdClient: MPDClient) {
        self.mpdClient = mpdClient
        self.albumArtManager = AlbumArtManager(mpdClient: mpdClient)
        super.init()
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        
        if enabled {
            setupNowPlayingInfo()
            setupRemoteCommandCenter()
        } else {
            clearNowPlayingInfo()
            disableRemoteCommands()
        }
    }
    
    public func updateNowPlayingInfo() {
        guard isEnabled else { return }
        setupNowPlayingInfo()
    }
    
    public func setMusicDirectory(_ path: String) {
        albumArtManager.setMusicDirectory(path)
    }
    
    #if os(macOS)
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        Logger.shared.log("SystemNowPlayingManager: Resizing image from \(image.size) to \(size)")
        Logger.shared.log("SystemNowPlayingManager: Original image isValid: \(image.isValid), representations: \(image.representations.count)")
        
        // If the requested size is the same as original, return original
        if image.size.width == size.width && image.size.height == size.height {
            Logger.shared.log("SystemNowPlayingManager: Size unchanged, returning original image")
            return image
        }
        
        // Create a new image with proper bitmap representation
        let scaledImage = NSImage(size: size)
        
        // Create a bitmap representation directly
        if let originalBitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) {
            let scaledBitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!
            
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaledBitmapRep)
            
            originalBitmapRep.draw(in: NSRect(origin: .zero, size: size))
            
            NSGraphicsContext.restoreGraphicsState()
            
            scaledImage.addRepresentation(scaledBitmapRep)
            
            Logger.shared.log("SystemNowPlayingManager: Created resized image with bitmap representation")
        } else {
            Logger.shared.log("SystemNowPlayingManager: Could not create bitmap rep, using simple approach")
            // Simple fallback - just return the original image
            return image
        }
        
        Logger.shared.log("SystemNowPlayingManager: Resized image isValid: \(scaledImage.isValid), representations: \(scaledImage.representations.count)")
        
        // Test save the resized image
        if let tiffData = scaledImage.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
            try? jpegData.write(to: URL(fileURLWithPath: "/tmp/debug_resized_\(Int(size.width))x\(Int(size.height)).jpg"))
            Logger.shared.log("SystemNowPlayingManager: Saved resized debug image to /tmp/debug_resized_\(Int(size.width))x\(Int(size.height)).jpg")
        }
        
        return scaledImage
    }
    #endif
    
    private func setupNowPlayingInfo() {
        guard let currentSong = mpdClient.currentSong else {
            clearNowPlayingInfo()
            return
        }
        
        var nowPlayingInfo: [String: Any] = [:]
        
        // Basic song information
        if let title = currentSong.title {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        if let artist = currentSong.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let album = currentSong.album {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        
        // Duration and elapsed time
        if let duration = currentSong.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        // Current playback position - use actual elapsed time from MPD
        if let elapsed = currentSong.elapsed {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        
        // Playback rate based on player state
        switch mpdClient.playerState {
        case .play:
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        case .pause, .stop, .stopped:
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        }
        
        // Media type
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        
        // Check if this is a different song or album than last time
        let currentSongFile = currentSong.file
        let songChanged = currentSongFile != lastSongFile
        
        // Create album key for comparison
        let artist = currentSong.artist ?? "unknown_artist"
        let album = currentSong.album ?? "unknown_album"
        let currentAlbumKey = "\(artist)_\(album)"
        let albumChanged = currentAlbumKey != lastAlbumKey
        
        if songChanged {
            Logger.shared.log("SystemNowPlayingManager: Song changed from '\(lastSongFile ?? "nil")' to '\(currentSongFile ?? "nil")'")
            lastSongFile = currentSongFile
        }
        
        if albumChanged {
            Logger.shared.log("SystemNowPlayingManager: Album changed from '\(lastAlbumKey ?? "nil")' to '\(currentAlbumKey)'")
            lastAlbumKey = currentAlbumKey
        }
        
        // Only fetch album artwork if the album has changed (not just the song)
        if albumChanged {
            Logger.shared.log("SystemNowPlayingManager: Fetching album art for new album")
            // Fetch album artwork asynchronously
            albumArtManager.getAlbumArt(for: currentSong) { [weak self] albumArt in
                Logger.shared.log("SystemNowPlayingManager: Album art callback received - albumArt is \(albumArt != nil ? "NOT nil" : "nil")")
                Task { @MainActor in
                    guard let self = self, self.isEnabled else { 
                        Logger.shared.log("SystemNowPlayingManager: Skipping album art update - self or isEnabled is nil/false")
                        return 
                    }
                    
                    var updatedInfo = nowPlayingInfo
                    
                    #if os(macOS)
                    if let albumArt = albumArt {
                        Logger.shared.log("SystemNowPlayingManager: Setting album art in now playing info - size: \(albumArt.size)")
                        Logger.shared.log("SystemNowPlayingManager: Album art isValid: \(albumArt.isValid), representations: \(albumArt.representations.count)")
                        
                        // Test if we can save the image to verify it's valid
                        let testPath = "/tmp/debug_album_art.jpg"
                        if let tiffData = albumArt.tiffRepresentation,
                           let bitmapRep = NSBitmapImageRep(data: tiffData),
                           let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                            try? jpegData.write(to: URL(fileURLWithPath: testPath))
                            Logger.shared.log("SystemNowPlayingManager: Saved debug image to \(testPath)")
                        } else {
                            Logger.shared.log("SystemNowPlayingManager: WARNING - Could not convert image to JPEG for testing")
                        }
                        
                        let artwork = MPMediaItemArtwork(boundsSize: albumArt.size) { requestedSize in
                            Logger.shared.log("SystemNowPlayingManager: MPMediaItemArtwork requested size: \(requestedSize)")
                            // Apple recommends NOT doing expensive resizing in the handler
                            // Just return the original image
                            return albumArt
                        }
                        updatedInfo[MPMediaItemPropertyArtwork] = artwork
                        self.currentArtwork = artwork // Store for future updates
                        Logger.shared.log("SystemNowPlayingManager: Album artwork added to nowPlayingInfo")
                    } else {
                        Logger.shared.log("SystemNowPlayingManager: No album art found, using default icon")
                        // Fallback to default music icon
                        if let musicIcon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
                            let artwork = MPMediaItemArtwork(boundsSize: musicIcon.size) { requestedSize in
                                return musicIcon
                            }
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            self.currentArtwork = artwork // Store for future updates
                            Logger.shared.log("SystemNowPlayingManager: Default music icon added to nowPlayingInfo")
                        }
                    }
                    #endif
                    
                    Logger.shared.log("SystemNowPlayingManager: Updating MPNowPlayingInfoCenter with artwork")
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    Logger.shared.log("SystemNowPlayingManager: MPNowPlayingInfoCenter updated")
                }
            }
        } else {
            Logger.shared.log("SystemNowPlayingManager: Same album, not fetching album art but updating basic info")
            // For same song, preserve existing artwork when updating basic info
            if let artwork = currentArtwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                Logger.shared.log("SystemNowPlayingManager: Preserved existing artwork in update")
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastSongFile = nil
        lastAlbumKey = nil
        currentArtwork = nil
        Logger.shared.log("SystemNowPlayingManager: Cleared now playing info, last song file, album key, and artwork")
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.mpdClient.play()
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.mpdClient.pause()
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            switch self?.mpdClient.playerState {
            case .play:
                self?.mpdClient.pause()
            case .pause, .stop, .stopped:
                self?.mpdClient.play()
            case .none:
                break
            }
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.mpdClient.stop()
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Previous track command
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.mpdClient.previous()
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.mpdClient.updateCurrentSong()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Next track command
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.mpdClient.next()
            // Schedule immediate update after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Task { @MainActor in
                    self?.mpdClient.updateStatus()
                    self?.mpdClient.updateCurrentSong()
                    self?.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Seek commands (optional - requires position tracking in MPDClient)
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
    }
    
    private func disableRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        
        // Remove all targets
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
    }
}