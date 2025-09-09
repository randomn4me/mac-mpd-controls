import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#endif

@MainActor
public final class SystemNowPlayingManager: NSObject {
    private let mpdClient: MPDClient
    private var isEnabled: Bool = false
    
    public init(mpdClient: MPDClient) {
        self.mpdClient = mpdClient
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
        
        // Album artwork (placeholder for future implementation)
        // TODO: Implement album artwork retrieval from MPD via albumart command
        // For now, we could set a default music icon
        #if os(macOS)
        if let musicIcon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
            let artwork = MPMediaItemArtwork(boundsSize: musicIcon.size) { _ in
                return musicIcon
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        #endif
        
        // Set the now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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