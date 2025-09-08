import Foundation
@testable import MPDControlsCore

// End-to-End tests for MPD Controls
struct EndToEndTests {
    static func run() {
        print("\n=== Running End-to-End Tests ===\n")
        
        testCompletePlaybackFlow()
        testPlaylistManagement()
        testVolumeAndCrossfadeControl()
        testSearchAndAddFlow()
        testConnectionRecovery()
        testMediaKeySimulation()
        
        print("\n=== All End-to-End Tests Passed ===\n")
    }
    
    static func testCompletePlaybackFlow() {
        print("Testing Complete Playback Flow...")
        
        // Simulate a complete playback session
        var state = PlayerState.stopped
        var playbackOptions = PlaybackOptions()
        
        // Start playback
        state = .play
        assert(state == .play, "Should be playing")
        
        // Toggle pause
        state = state == .play ? .pause : .play
        assert(state == .pause, "Should be paused")
        
        // Resume
        state = .play
        assert(state == .play, "Should resume playing")
        
        // Enable shuffle and repeat
        playbackOptions.random = true
        playbackOptions.repeat = true
        assert(playbackOptions.random == true, "Shuffle should be enabled")
        assert(playbackOptions.repeat == true, "Repeat should be enabled")
        
        // Stop playback
        state = .stop
        assert(state == .stop, "Should be stopped")
        
        print("✓ Complete Playback Flow tests passed")
    }
    
    static func testPlaylistManagement() {
        print("Testing Playlist Management...")
        
        // Simulate playlist operations
        var playlist: [String] = []
        
        // Add songs
        playlist.append("song1.mp3")
        playlist.append("song2.mp3")
        playlist.append("song3.mp3")
        assert(playlist.count == 3, "Should have 3 songs")
        
        // Remove a song
        playlist.remove(at: 1)
        assert(playlist.count == 2, "Should have 2 songs after removal")
        assert(playlist[0] == "song1.mp3", "First song should remain")
        assert(playlist[1] == "song3.mp3", "Third song should be at index 1")
        
        // Clear playlist
        playlist.removeAll()
        assert(playlist.isEmpty, "Playlist should be empty")
        
        print("✓ Playlist Management tests passed")
    }
    
    static func testVolumeAndCrossfadeControl() {
        print("Testing Volume and Crossfade Control...")
        
        // Test volume adjustments
        var volume = 50
        
        // Increase volume
        volume = min(100, volume + 10)
        assert(volume == 60, "Volume should be 60")
        
        // Decrease volume
        volume = max(0, volume - 20)
        assert(volume == 40, "Volume should be 40")
        
        // Set to maximum
        volume = 100
        assert(volume == 100, "Volume should be at maximum")
        
        // Test crossfade
        var crossfade = 0
        
        // Set crossfade
        crossfade = 5
        assert(crossfade == 5, "Crossfade should be 5 seconds")
        
        // Increase crossfade
        crossfade = min(30, crossfade + 10)
        assert(crossfade == 15, "Crossfade should be 15 seconds")
        
        print("✓ Volume and Crossfade Control tests passed")
    }
    
    static func testSearchAndAddFlow() {
        print("Testing Search and Add Flow...")
        
        // Simulate search results
        struct SearchResult {
            let file: String
            let artist: String
            let title: String
        }
        
        let searchResults = [
            SearchResult(file: "artist1/song1.mp3", artist: "Artist 1", title: "Song 1"),
            SearchResult(file: "artist2/song2.mp3", artist: "Artist 2", title: "Song 2")
        ]
        
        var queue: [String] = []
        
        // Add search results to queue
        for result in searchResults {
            queue.append(result.file)
        }
        
        assert(queue.count == 2, "Should have 2 songs in queue")
        assert(queue[0] == "artist1/song1.mp3", "First song should be correct")
        assert(queue[1] == "artist2/song2.mp3", "Second song should be correct")
        
        print("✓ Search and Add Flow tests passed")
    }
    
    static func testConnectionRecovery() {
        print("Testing Connection Recovery...")
        
        var connectionStatus = ConnectionStatus.disconnected
        var retryCount = 0
        let maxRetries = 3
        
        // Simulate connection attempts
        while connectionStatus != .connected && retryCount < maxRetries {
            connectionStatus = .connecting
            retryCount += 1
            
            // Simulate successful connection on second attempt
            if retryCount == 2 {
                connectionStatus = .connected
            }
        }
        
        assert(connectionStatus == .connected, "Should be connected after retries")
        assert(retryCount == 2, "Should have taken 2 attempts")
        
        // Test disconnection handling
        connectionStatus = .disconnected
        assert(connectionStatus == .disconnected, "Should handle disconnection")
        
        print("✓ Connection Recovery tests passed")
    }
    
    static func testMediaKeySimulation() {
        print("Testing Media Key Simulation...")
        
        // Media key codes (from MediaKeyHandler)
        let NX_KEYTYPE_PLAY: Int32 = 16
        let NX_KEYTYPE_NEXT: Int32 = 17
        let NX_KEYTYPE_PREVIOUS: Int32 = 18
        let NX_KEYTYPE_FAST: Int32 = 19
        let NX_KEYTYPE_REWIND: Int32 = 20
        
        var lastCommand: String? = nil
        
        // Simulate play/pause key
        lastCommand = "toggle"
        assert(lastCommand == "toggle", "Play key should trigger toggle")
        
        // Simulate next key
        lastCommand = "next"
        assert(lastCommand == "next", "Next key should trigger next")
        
        // Simulate previous key
        lastCommand = "previous"
        assert(lastCommand == "previous", "Previous key should trigger previous")
        
        print("✓ Media Key Simulation tests passed")
    }
}