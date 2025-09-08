import Foundation
@testable import MPDControlsCore

#if canImport(XCTest)
import XCTest

final class MPDTypesTests: XCTestCase {
    
    func testPlayerStateRawValues() {
        XCTAssertEqual(PlayerState.play.rawValue, "play")
        XCTAssertEqual(PlayerState.pause.rawValue, "pause")
        XCTAssertEqual(PlayerState.stop.rawValue, "stop")
        XCTAssertEqual(PlayerState.stopped.rawValue, "stopped")
    }
    
    func testPlaybackOptionsSingleMode() {
        XCTAssertEqual(PlaybackOptions.SingleMode.off.rawValue, "0")
        XCTAssertEqual(PlaybackOptions.SingleMode.on.rawValue, "1")
        XCTAssertEqual(PlaybackOptions.SingleMode.oneshot.rawValue, "oneshot")
    }
    
    func testPlaybackOptionsConsumeMode() {
        XCTAssertEqual(PlaybackOptions.ConsumeMode.off.rawValue, "0")
        XCTAssertEqual(PlaybackOptions.ConsumeMode.on.rawValue, "1")
        XCTAssertEqual(PlaybackOptions.ConsumeMode.oneshot.rawValue, "oneshot")
    }
    
    func testPlaybackOptionsInitialization() {
        let options = PlaybackOptions()
        XCTAssertFalse(options.random)
        XCTAssertFalse(options.repeat)
        XCTAssertEqual(options.single, .off)
        XCTAssertEqual(options.consume, .off)
    }
    
    func testSongInitialization() {
        let song = Song(
            artist: "Test Artist",
            title: "Test Title",
            album: "Test Album",
            file: "test.mp3",
            duration: 180.0,
            elapsed: 60.0
        )
        
        XCTAssertEqual(song.artist, "Test Artist")
        XCTAssertEqual(song.title, "Test Title")
        XCTAssertEqual(song.album, "Test Album")
        XCTAssertEqual(song.file, "test.mp3")
        XCTAssertEqual(song.duration, 180.0)
        XCTAssertEqual(song.elapsed, 60.0)
    }
    
    func testConnectionStatusEquality() {
        let status1 = ConnectionStatus.connected
        let status2 = ConnectionStatus.connected
        XCTAssertEqual(status1, status2)
        
        let status3 = ConnectionStatus.failed("Error")
        let status4 = ConnectionStatus.failed("Error")
        XCTAssertEqual(status3, status4)
        
        let status5 = ConnectionStatus.failed("Error1")
        let status6 = ConnectionStatus.failed("Error2")
        XCTAssertNotEqual(status5, status6)
    }
}

#else

// Linux test runner without XCTest
struct MPDTypesTests {
    static func run() {
        print("Running MPDTypes tests...")
        testPlayerStateRawValues()
        testPlaybackOptionsSingleMode()
        testPlaybackOptionsConsumeMode()
        testPlaybackOptionsInitialization()
        testSongInitialization()
        testConnectionStatusEquality()
        print("✓ MPDTypes tests passed")
    }
    
    static func testPlayerStateRawValues() {
        assert(PlayerState.play.rawValue == "play")
        assert(PlayerState.pause.rawValue == "pause")
        assert(PlayerState.stop.rawValue == "stop")
        assert(PlayerState.stopped.rawValue == "stopped")
    }
    
    static func testPlaybackOptionsSingleMode() {
        assert(PlaybackOptions.SingleMode.off.rawValue == "0")
        assert(PlaybackOptions.SingleMode.on.rawValue == "1")
        assert(PlaybackOptions.SingleMode.oneshot.rawValue == "oneshot")
    }
    
    static func testPlaybackOptionsConsumeMode() {
        assert(PlaybackOptions.ConsumeMode.off.rawValue == "0")
        assert(PlaybackOptions.ConsumeMode.on.rawValue == "1")
        assert(PlaybackOptions.ConsumeMode.oneshot.rawValue == "oneshot")
    }
    
    static func testPlaybackOptionsInitialization() {
        let options = PlaybackOptions()
        assert(!options.random)
        assert(!options.repeat)
        assert(options.single == .off)
        assert(options.consume == .off)
    }
    
    static func testSongInitialization() {
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
    }
    
    static func testConnectionStatusEquality() {
        let status1 = ConnectionStatus.connected
        let status2 = ConnectionStatus.connected
        assert(status1 == status2)
        
        let status3 = ConnectionStatus.failed("Error")
        let status4 = ConnectionStatus.failed("Error")
        assert(status3 == status4)
        
        let status5 = ConnectionStatus.failed("Error1")
        let status6 = ConnectionStatus.failed("Error2")
        assert(status5 != status6)
    }
}

#endif