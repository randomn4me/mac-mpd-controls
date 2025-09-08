@testable import MPDControlsCore

// Integration tests that run without XCTest
public struct IntegrationTests {
    public static func runAll() {
        print("\n=== Running Integration Tests ===\n")
        
        testMPDProtocolParsing()
        testMPDTypes()
        testPlaybackOptions()
        testSimpleMPDClient()
        testQueueOperations()
        testSearchOperations()
        testDatabaseOperations()
        
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
        
        let _ = SimpleMPDClient(host: "localhost", port: 6600)
        // Client created successfully
        
        // Test command formatting
        let playCommand = MPDCommand.play.toString()
        assert(playCommand == "play")
        
        let volumeCommand = MPDCommand.setVolume(75).toString()
        assert(volumeCommand == "setvol 75")
        
        print("✓ Simple MPD Client tests passed")
    }
    
    static func testQueueOperations() {
        print("Testing Queue Operations...")
        
        // Test queue-related commands
        let clearCommand = MPDCommand.clear.toString()
        assert(clearCommand == "clear")
        
        let addCommand = MPDCommand.add("test.mp3").toString()
        assert(addCommand == "add \"test.mp3\"")
        
        let playIdCommand = MPDCommand.playId(5).toString()
        assert(playIdCommand == "playid 5")
        
        let deleteCommand = MPDCommand.delete(3).toString()
        assert(deleteCommand == "delete 3")
        
        let shuffleCommand = MPDCommand.shuffle.toString()
        assert(shuffleCommand == "shuffle")
        
        print("✓ Queue Operations tests passed")
    }
    
    static func testSearchOperations() {
        print("Testing Search Operations...")
        
        // Test search command formatting
        let searchArtistCommand = MPDCommand.search("artist", "Test Artist").toString()
        assert(searchArtistCommand == "search artist \"Test Artist\"")
        
        let searchAlbumCommand = MPDCommand.search("album", "Test Album").toString()
        assert(searchAlbumCommand == "search album \"Test Album\"")
        
        let searchTitleCommand = MPDCommand.search("title", "Test Song").toString()
        assert(searchTitleCommand == "search title \"Test Song\"")
        
        let searchAnyCommand = MPDCommand.search("any", "Test").toString()
        assert(searchAnyCommand == "search any \"Test\"")
        
        print("✓ Search Operations tests passed")
    }
    
    static func testDatabaseOperations() {
        print("Testing Database Operations...")
        
        // Test database update commands
        let updateCommand = MPDCommand.update(nil).toString()
        assert(updateCommand == "update")
        
        let updatePathCommand = MPDCommand.update("/music/new").toString()
        assert(updatePathCommand == "update \"/music/new\"")
        
        let rescanCommand = MPDCommand.rescan(nil).toString()
        assert(rescanCommand == "rescan")
        
        let rescanPathCommand = MPDCommand.rescan("/music/updated").toString()
        assert(rescanPathCommand == "rescan \"/music/updated\"")
        
        print("✓ Database Operations tests passed")
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