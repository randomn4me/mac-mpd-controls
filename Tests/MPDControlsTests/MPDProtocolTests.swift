import Foundation
@testable import MPDControlsCore

#if canImport(XCTest)
import XCTest

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

#else

// Linux test runner without XCTest
struct MPDProtocolTests {
    static func run() {
        print("Running MPDProtocol tests...")
        testMPDParserOKResponse()
        testMPDParserStatusResponse()
        testMPDParserCurrentSongResponse()
        testMPDParserErrorResponse()
        testMPDParserFieldsWithColons()
        testMPDErrorDescriptions()
        print("✓ MPDProtocol tests passed")
    }
    
    static func testMPDParserOKResponse() {
        let response = "OK MPD 0.21.0\n"
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            assert(mpdResponse.fields.isEmpty)
            assert(mpdResponse.rawResponse == response)
        case .failure:
            fatalError("Parser should succeed for OK response")
        }
    }
    
    static func testMPDParserStatusResponse() {
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
            assert(mpdResponse.fields["volume"] == "50")
            assert(mpdResponse.fields["repeat"] == "0")
            assert(mpdResponse.fields["random"] == "1")
            assert(mpdResponse.fields["state"] == "play")
            assert(mpdResponse.fields["playlistlength"] == "10")
        case .failure:
            fatalError("Parser should succeed for status response")
        }
    }
    
    static func testMPDParserCurrentSongResponse() {
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
            assert(mpdResponse.fields["file"] == "music/song.mp3")
            assert(mpdResponse.fields["Artist"] == "Test Artist")
            assert(mpdResponse.fields["Title"] == "Test Song")
            assert(mpdResponse.fields["Album"] == "Test Album")
            assert(mpdResponse.fields["Time"] == "240")
            assert(mpdResponse.fields["Id"] == "42")
        case .failure:
            fatalError("Parser should succeed for currentsong response")
        }
    }
    
    static func testMPDParserErrorResponse() {
        let response = "ACK [50@0] {play} No such song\n"
        let result = MPDParser.parse(response)
        
        switch result {
        case .success:
            fatalError("Parser should fail for ACK response")
        case .failure(let error):
            if case .commandFailed(let message) = error {
                assert(message == "ACK [50@0] {play} No such song")
            } else {
                fatalError("Expected commandFailed error")
            }
        }
    }
    
    static func testMPDParserFieldsWithColons() {
        let response = """
        file: http://stream.example.com:8000/stream
        Title: Song Name: The Sequel
        OK
        """
        
        let result = MPDParser.parse(response)
        
        switch result {
        case .success(let mpdResponse):
            assert(mpdResponse.fields["file"] == "http://stream.example.com:8000/stream")
            assert(mpdResponse.fields["Title"] == "Song Name: The Sequel")
        case .failure:
            fatalError("Parser should succeed for fields with colons")
        }
    }
    
    static func testMPDErrorDescriptions() {
        let notConnected = MPDError.notConnected
        assert(notConnected.errorDescription == "Not connected to MPD server")
        
        let commandFailed = MPDError.commandFailed("Test error")
        assert(commandFailed.errorDescription == "Command failed: Test error")
        
        let invalidResponse = MPDError.invalidResponse
        assert(invalidResponse.errorDescription == "Invalid response from MPD server")
        
        let connectionFailed = MPDError.connectionFailed("Connection refused")
        assert(connectionFailed.errorDescription == "Connection failed: Connection refused")
    }
}

#endif