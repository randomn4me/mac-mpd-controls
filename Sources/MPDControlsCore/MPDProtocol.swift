import Foundation

public protocol MPDProtocol {
    func connect(host: String, port: UInt16)
    func disconnect()
    func send(command: String, completion: @escaping (Result<[String: String], Error>) -> Void)
}

public enum MPDError: Error, LocalizedError {
    case notConnected
    case commandFailed(String)
    case invalidResponse
    case connectionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MPD server"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .invalidResponse:
            return "Invalid response from MPD server"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}

public struct MPDResponse {
    public let fields: [String: String]
    public let rawResponse: String
    
    public init(fields: [String: String], rawResponse: String) {
        self.fields = fields
        self.rawResponse = rawResponse
    }
}

public class MPDParser {
    public static func parse(_ response: String) -> Result<MPDResponse, MPDError> {
        var fields: [String: String] = [:]
        let lines = response.split(separator: "\n")
        
        for line in lines {
            if line == "OK" || line.starts(with: "OK MPD") {
                continue
            }
            if line.starts(with: "ACK ") {
                return .failure(.commandFailed(String(line)))
            }
            
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
        }
        
        return .success(MPDResponse(fields: fields, rawResponse: response))
    }
}