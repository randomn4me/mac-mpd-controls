import XCTest
@testable import MPDControlsCore

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