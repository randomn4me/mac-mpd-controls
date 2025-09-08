@testable import MPDControlsCore

// Integration tests that run without XCTest
public struct IntegrationTests {
    public static func runAll() {
        print("\n=== Running Integration Tests ===\n")
        
        testMPDProtocolParsing()
        testMPDTypes()
        testPlaybackOptions()
        testSimpleMPDClient()
        
        print("\n=== All Integration Tests Passed ===\n")
    }
    
    static func testMPDProtocolParsing() {
        print("Testing MPD Protocol Parsing...")
        
        // Test various MPD responses
        let okResponse = "OK MPD 0.23.0\n"
        let okResult = MPDParser.parse(okResponse)
        assert(okResult.isSuccess, "OK response should parse")
        
        let statusResponse = """
        volume: 75
        repeat: 1
        random: 0
        state: play
        OK
        """
        let statusResult = MPDParser.parse(statusResponse)
        assert(statusResult.isSuccess, "Status response should parse")
        
        if case .success(let parsed) = statusResult {
            assert(parsed.fields["volume"] == "75", "Volume should be 75")
            assert(parsed.fields["state"] == "play", "State should be play")
        }
        
        let errorResponse = "ACK [50@0] {play} No such song\n"
        let errorResult = MPDParser.parse(errorResponse)
        assert(!errorResult.isSuccess, "Error response should fail")
        
        print("✓ MPD Protocol Parsing tests passed")
    }
    
    static func testMPDTypes() {
        print("Testing MPD Types...")
        
        let song = Song(
            artist: "Test Artist",
            title: "Test Song",
            album: "Test Album",
            file: "test.mp3",
            duration: 240.0,
            elapsed: 60.0
        )
        
        assert(song.artist == "Test Artist")
        assert(song.title == "Test Song")
        assert(song.duration == 240.0)
        
        print("✓ MPD Types tests passed")
    }
    
    static func testPlaybackOptions() {
        print("Testing Playback Options...")
        
        var options = PlaybackOptions()
        assert(!options.random)
        assert(!options.repeat)
        
        options.random = true
        options.repeat = true
        options.single = .oneshot
        options.consume = .on
        
        assert(options.random)
        assert(options.repeat)
        assert(options.single == .oneshot)
        assert(options.consume == .on)
        
        print("✓ Playback Options tests passed")
    }
    
    static func testSimpleMPDClient() {
        print("Testing Simple MPD Client...")
        
        let client = SimpleMPDClient(host: "localhost", port: 6600)
        assert(client.host == "localhost")
        assert(client.port == 6600)
        
        // Test command formatting
        let playCommand = MPDCommand.play.rawValue
        assert(playCommand == "play\n")
        
        let volumeCommand = MPDCommand.setVolume(75).rawValue
        assert(volumeCommand == "setvol 75\n")
        
        print("✓ Simple MPD Client tests passed")
    }
}

// Helper extension for Result
extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}