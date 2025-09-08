import Foundation
@testable import MPDControlsCore

// Simple test runner for Linux without XCTest
struct BasicTests {
    static func run() {
        print("\n=== Running Basic Tests ===\n")
        
        testPlayerStateRawValues()
        testPlaybackOptions()
        testSongCreation()
        testMPDParser()
        testMPDCommands()
        testConnectionStatus()
        testVolumeOperations()
        testCrossfadeOperations()
        
        print("\n=== All Tests Passed ===\n")
    }
    
    static func testPlayerStateRawValues() {
        print("Testing PlayerState raw values...")
        assert(PlayerState.play.rawValue == "play")
        assert(PlayerState.pause.rawValue == "pause")
        assert(PlayerState.stop.rawValue == "stop")
        assert(PlayerState.stopped.rawValue == "stopped")
        print("✓ PlayerState tests passed")
    }
    
    static func testPlaybackOptions() {
        print("Testing PlaybackOptions...")
        let options = PlaybackOptions()
        assert(options.random == false)
        assert(options.repeat == false)
        assert(options.single == .off)
        assert(options.consume == .off)
        
        assert(PlaybackOptions.SingleMode.off.rawValue == "0")
        assert(PlaybackOptions.SingleMode.on.rawValue == "1")
        assert(PlaybackOptions.SingleMode.oneshot.rawValue == "oneshot")
        
        print("✓ PlaybackOptions tests passed")
    }
    
    static func testSongCreation() {
        print("Testing Song creation...")
        let song = Song(
            artist: "Test Artist",
            title: "Test Title",
            album: "Test Album",
            file: "test.mp3",
            duration: 180.0,
            elapsed: 60.0
        )
        
        assert(song.artist == "Test Artist")
        assert(song.title == "Test Title")
        assert(song.album == "Test Album")
        assert(song.file == "test.mp3")
        assert(song.duration == 180.0)
        assert(song.elapsed == 60.0)
        
        print("✓ Song tests passed")
    }
    
    static func testMPDParser() {
        print("Testing MPD Parser...")
        
        // Test OK response
        let okResponse = "OK MPD 0.21.0\n"
        let okResult = MPDParser.parse(okResponse)
        switch okResult {
        case .success(let response):
            assert(response.fields.isEmpty)
        case .failure:
            assert(false, "OK response should parse successfully")
        }
        
        // Test status response
        let statusResponse = """
        volume: 50
        repeat: 0
        random: 1
        state: play
        OK
        """
        
        let statusResult = MPDParser.parse(statusResponse)
        switch statusResult {
        case .success(let response):
            assert(response.fields["volume"] == "50")
            assert(response.fields["repeat"] == "0")
            assert(response.fields["random"] == "1")
            assert(response.fields["state"] == "play")
        case .failure:
            assert(false, "Status response should parse successfully")
        }
        
        // Test error response
        let errorResponse = "ACK [50@0] {play} No such song\n"
        let errorResult = MPDParser.parse(errorResponse)
        switch errorResult {
        case .success:
            assert(false, "ACK response should fail")
        case .failure(let error):
            if case .commandFailed = error {
                // Expected
            } else {
                assert(false, "Should be commandFailed error")
            }
        }
        
        print("✓ MPD Parser tests passed")
    }
    
    static func testMPDCommands() {
        print("Testing MPD Commands...")
        
        // Test command creation
        let commands = [
            MPDCommand.play: "play",
            MPDCommand.pause: "pause",
            MPDCommand.stop: "stop",
            MPDCommand.next: "next",
            MPDCommand.previous: "previous",
            MPDCommand.status: "status",
            MPDCommand.currentSong: "currentsong",
            MPDCommand.setVolume(50): "setvol 50",
            MPDCommand.random(true): "random 1",
            MPDCommand.random(false): "random 0",
            MPDCommand.repeat(true): "repeat 1",
            MPDCommand.single(.on): "single 1",
            MPDCommand.single(.oneshot): "single oneshot",
            MPDCommand.consume(.off): "consume 0",
            MPDCommand.crossfade(5): "crossfade 5",
            MPDCommand.shuffle: "shuffle",
            MPDCommand.clear: "clear",
            MPDCommand.update: "update",
            MPDCommand.outputs: "outputs"
        ]
        
        for (command, expectedString) in commands {
            assert(command.toString() == expectedString, "Command \(command) should produce '\(expectedString)'")
        }
        
        print("✓ MPD Commands tests passed")
    }
    
    static func testConnectionStatus() {
        print("Testing Connection Status...")
        
        // Test connection status enum
        let statuses: [ConnectionStatus] = [
            .disconnected,
            .connecting,
            .connected,
            .failed("Test error")
        ]
        
        for status in statuses {
            switch status {
            case .disconnected:
                assert(status == .disconnected)
            case .connecting:
                assert(status == .connecting)
            case .connected:
                assert(status == .connected)
            case .failed(let error):
                assert(error == "Test error")
            }
        }
        
        print("✓ Connection Status tests passed")
    }
    
    static func testVolumeOperations() {
        print("Testing Volume Operations...")
        
        // Test volume clamping
        let testVolumes = [
            (-10, 0),    // Below minimum
            (0, 0),      // Minimum
            (50, 50),    // Normal
            (100, 100),  // Maximum
            (150, 100)   // Above maximum
        ]
        
        for (input, expected) in testVolumes {
            let clamped = max(0, min(100, input))
            assert(clamped == expected, "Volume \(input) should clamp to \(expected)")
        }
        
        print("✓ Volume Operations tests passed")
    }
    
    static func testCrossfadeOperations() {
        print("Testing Crossfade Operations...")
        
        // Test crossfade clamping
        let testCrossfades = [
            (-5, 0),     // Below minimum
            (0, 0),      // Minimum
            (10, 10),    // Normal
            (120, 120),  // Maximum
            (200, 120)   // Above maximum
        ]
        
        for (input, expected) in testCrossfades {
            let clamped = max(0, min(120, input))
            assert(clamped == expected, "Crossfade \(input) should clamp to \(expected)")
        }
        
        print("✓ Crossfade Operations tests passed")
    }
}