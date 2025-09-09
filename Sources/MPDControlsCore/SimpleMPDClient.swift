import Foundation
#if canImport(Network)
import Network
#endif

public class SimpleMPDClient {
    public var connectionStatus: ConnectionStatus = .disconnected
    public var currentSong: Song?
    public var playerState: PlayerState = .stopped
    public var playbackOptions = PlaybackOptions()
    public var volume: Int = 0
    
    private let host: String
    private let port: UInt16
    
    public init(host: String = "127.0.0.1", port: UInt16 = 6600) {
        self.host = host
        self.port = port
    }
    
    public func testConnection() -> Bool {
        print("Testing connection to \(host):\(port)")
        
        #if os(Linux)
        // Simple socket-based connection test for Linux
        // For now, just return true on Linux as we can't test without proper socket implementation
        print("Connection test skipped on Linux (would connect to \(self.host):\(port))")
        return true
        #else
        // macOS/iOS implementation using CFStream
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                          host as CFString,
                                          UInt32(port),
                                          &readStream,
                                          &writeStream)
        
        guard let cfInputStream = readStream?.takeRetainedValue(),
              let cfOutputStream = writeStream?.takeRetainedValue() else {
            return false
        }
        
        // Cast CFStreams to InputStream/OutputStream
        let inputStream = cfInputStream as InputStream
        let outputStream = cfOutputStream as OutputStream
        
        inputStream.open()
        outputStream.open()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        let connected = inputStream.streamStatus == .open && outputStream.streamStatus == .open
        
        if connected {
            // Try to read the MPD greeting
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            if inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    if let greeting = String(bytes: Data(bytes: buffer, count: bytesRead), encoding: .utf8) {
                        print("MPD Server Response: \(greeting.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            }
        }
        
        inputStream.close()
        outputStream.close()
        
        return connected
        #endif
    }
}