import XCTest
@testable import MPDControlsCore

final class MPDProtocolTests: XCTestCase {
    
    func testMPDParserOKResponse() {
        let response = "OK MPD 0.21.0\n"
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            XCTAssertTrue(mpdResponse.fields.isEmpty)
            XCTAssertEqual(mpdResponse.rawResponse, response)
        case .failure:
            XCTFail("Parser should succeed for OK response")
        }
    }
    
    func testMPDParserStatusResponse() {
        let response = """
        volume: 50
        repeat: 0
        random: 1
        single: 0
        consume: 0
        playlist: 2
        playlistlength: 10
        state: play
        OK
        """
        
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            XCTAssertEqual(mpdResponse.fields["volume"], "50")
            XCTAssertEqual(mpdResponse.fields["repeat"], "0")
            XCTAssertEqual(mpdResponse.fields["random"], "1")
            XCTAssertEqual(mpdResponse.fields["state"], "play")
            XCTAssertEqual(mpdResponse.fields["playlistlength"], "10")
        case .failure:
            XCTFail("Parser should succeed for status response")
        }
    }
    
    func testMPDParserCurrentSongResponse() {
        let response = """
        file: music/song.mp3
        Last-Modified: 2024-01-01T00:00:00Z
        Artist: Test Artist
        Title: Test Song
        Album: Test Album
        Date: 2024
        Genre: Rock
        Time: 240
        duration: 240.123
        Pos: 5
        Id: 42
        OK
        """
        
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            XCTAssertEqual(mpdResponse.fields["file"], "music/song.mp3")
            XCTAssertEqual(mpdResponse.fields["Artist"], "Test Artist")
            XCTAssertEqual(mpdResponse.fields["Title"], "Test Song")
            XCTAssertEqual(mpdResponse.fields["Album"], "Test Album")
            XCTAssertEqual(mpdResponse.fields["Time"], "240")
            XCTAssertEqual(mpdResponse.fields["Id"], "42")
        case .failure:
            XCTFail("Parser should succeed for currentsong response")
        }
    }
    
    func testMPDParserErrorResponse() {
        let response = "ACK [50@0] {play} No such song\n"
        let result = MPDParser.parse(response)
        
        switch result {
        case .success:
            XCTFail("Parser should fail for ACK response")
        case .failure(let error):
            if case .commandFailed(let message) = error {
                XCTAssertEqual(message, "ACK [50@0] {play} No such song")
            } else {
                XCTFail("Expected commandFailed error")
            }
        }
    }
    
    func testMPDParserFieldsWithColons() {
        let response = """
        file: http://stream.example.com:8000/stream
        Title: Song Name: The Sequel
        OK
        """
        
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            XCTAssertEqual(mpdResponse.fields["file"], "http://stream.example.com:8000/stream")
            XCTAssertEqual(mpdResponse.fields["Title"], "Song Name: The Sequel")
        case .failure:
            XCTFail("Parser should succeed for fields with colons")
        }
    }
    
    func testMPDErrorDescriptions() {
        let notConnected = MPDError.notConnected
        XCTAssertEqual(notConnected.errorDescription, "Not connected to MPD server")
        
        let commandFailed = MPDError.commandFailed("Test error")
        XCTAssertEqual(commandFailed.errorDescription, "Command failed: Test error")
        
        let invalidResponse = MPDError.invalidResponse
        XCTAssertEqual(invalidResponse.errorDescription, "Invalid response from MPD server")
        
        let connectionFailed = MPDError.connectionFailed("Connection refused")
        XCTAssertEqual(connectionFailed.errorDescription, "Connection failed: Connection refused")
    }
}