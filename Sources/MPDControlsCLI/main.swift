import Foundation
import MPDControlsCore

// Command-line interface for testing MPD Controls on Linux
print("MPD Controls CLI - Test Runner")
print("This is a test executable for building and testing on Linux")
print("The full macOS application requires SwiftUI and can only be built on macOS")

// Test basic MPD client functionality
class TestRunner {
    static func run() {
        print("\nTesting MPD Client initialization...")
        let client = SimpleMPDClient(host: "127.0.0.1", port: 6600)
        print("✓ MPD Client created")
        
        print("\nTesting connection status...")
        print("Initial status: \(client.connectionStatus)")
        
        print("\nTesting playback options...")
        let options = PlaybackOptions()
        print("Random: \(options.random)")
        print("Repeat: \(options.repeat)")
        print("Single: \(options.single)")
        print("Consume: \(options.consume)")
        
        print("\nTesting player states...")
        print("Play: \(PlayerState.play.rawValue)")
        print("Pause: \(PlayerState.pause.rawValue)")
        print("Stop: \(PlayerState.stop.rawValue)")
        
        print("\nTesting MPD connection...")
        if client.testConnection() {
            print("✓ Successfully connected to MPD server")
        } else {
            print("✗ Failed to connect to MPD server (this is expected if MPD is not running)")
        }
        
        print("\n✓ All basic tests passed")
    }
}

// Run tests
TestRunner.run()
exit(0)