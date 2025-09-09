import Foundation
import MPDControlsCore

#if canImport(Network)
import Network
#endif

#if canImport(Network)
// macOS implementation using Network framework
@available(macOS 10.14, *)
class AppleNetworkConnection: NetworkConnectionProtocol {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "mpd.network.queue")
    var stateUpdateHandler: ((ConnectionState) -> Void)?
    
    func connect(host: String, port: UInt16) {
        let endpoint = NWEndpoint.Host(host)
        let portEndpoint = NWEndpoint.Port(rawValue: port)!
        
        connection = NWConnection(host: endpoint, port: portEndpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            let mappedState: ConnectionState
            switch state {
            case .setup:
                mappedState = .setup
            case .waiting(let error):
                mappedState = .waiting(error)
            case .preparing:
                mappedState = .preparing
            case .ready:
                mappedState = .ready
            case .failed(let error):
                mappedState = .failed(error)
            case .cancelled:
                mappedState = .cancelled
            @unknown default:
                mappedState = .cancelled
            }
            self?.stateUpdateHandler?(mappedState)
        }
        
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    func cancel() {
        connection?.cancel()
    }
    
    func send(data: Data, completion: @escaping (Error?) -> Void) {
        connection?.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }
    
    func receive(completion: @escaping (Data?, Error?) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if isComplete {
                completion(nil, NSError(domain: "NetworkConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection closed"]))
            } else {
                completion(data, error)
            }
        }
    }
}
#endif

// Foundation-based implementation for Linux
class FoundationNetworkConnection: NetworkConnectionProtocol {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let queue = DispatchQueue(label: "mpd.network.queue")
    var stateUpdateHandler: ((ConnectionState) -> Void)?
    
    func connect(host: String, port: UInt16) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                          host as CFString,
                                          UInt32(port),
                                          &readStream,
                                          &writeStream)
        
        inputStream = readStream?.takeRetainedValue()
        outputStream = writeStream?.takeRetainedValue()
        
        inputStream?.schedule(in: .current, forMode: .common)
        outputStream?.schedule(in: .current, forMode: .common)
        
        inputStream?.open()
        outputStream?.open()
        
        // Check connection status
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let input = self?.inputStream, let output = self?.outputStream {
                if input.streamStatus == .open && output.streamStatus == .open {
                    self?.stateUpdateHandler?(.ready)
                } else if input.streamStatus == .error || output.streamStatus == .error {
                    let error = NSError(domain: "NetworkConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect"])
                    self?.stateUpdateHandler?(.failed(error))
                }
            }
        }
    }
    
    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        
        inputStream?.remove(from: .current, forMode: .common)
        outputStream?.remove(from: .current, forMode: .common)
        
        inputStream = nil
        outputStream = nil
        
        stateUpdateHandler?(.cancelled)
    }
    
    func cancel() {
        inputStream?.close()
        outputStream?.close()
    }
    
    func send(data: Data, completion: @escaping (Error?) -> Void) {
        queue.async { [weak self] in
            guard let outputStream = self?.outputStream else {
                completion(NSError(domain: "NetworkConnection", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output stream"]))
                return
            }
            
            data.withUnsafeBytes { bytes in
                let bytesWritten = outputStream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
                if bytesWritten < 0 {
                    completion(outputStream.streamError)
                } else if bytesWritten < data.count {
                    completion(NSError(domain: "NetworkConnection", code: 4, userInfo: [NSLocalizedDescriptionKey: "Partial write"]))
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    func receive(completion: @escaping (Data?, Error?) -> Void) {
        queue.async { [weak self] in
            guard let inputStream = self?.inputStream else {
                completion(nil, NSError(domain: "NetworkConnection", code: 5, userInfo: [NSLocalizedDescriptionKey: "No input stream"]))
                return
            }
            
            let bufferSize = 65536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    completion(data, nil)
                    return
                } else if bytesRead < 0 {
                    completion(nil, inputStream.streamError)
                    return
                }
            }
            
            // No bytes available yet, schedule another receive
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.receive(completion: completion)
            }
        }
    }
}

// Factory for creating appropriate network connection
enum NetworkConnectionFactory {
    static func create() -> NetworkConnectionProtocol {
        #if canImport(Network)
        if #available(macOS 10.14, *) {
            return AppleNetworkConnection()
        } else {
            return FoundationNetworkConnection()
        }
        #else
        return FoundationNetworkConnection()
        #endif
    }
}