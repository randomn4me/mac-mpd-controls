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

public enum MPDCommand {
    case play
    case pause
    case stop
    case next
    case previous
    case status
    case currentSong
    case setVolume(Int)
    case random(Bool)
    case `repeat`(Bool)
    case single(PlaybackOptions.SingleMode)
    case consume(PlaybackOptions.ConsumeMode)
    case crossfade(Int)
    case shuffle
    case clear
    case update(String?)
    case rescan(String?)
    case outputs
    case search(String, String)
    case add(String)
    case playId(Int)
    case delete(Int)
    case enableOutput(Int)
    case disableOutput(Int)
    case load(String)
    case save(String)
    case albumArt(String, Int)
    case readPicture(String, Int)
    
    public func toString() -> String {
        switch self {
        case .play:
            return "play"
        case .pause:
            return "pause"
        case .stop:
            return "stop"
        case .next:
            return "next"
        case .previous:
            return "previous"
        case .status:
            return "status"
        case .currentSong:
            return "currentsong"
        case .setVolume(let volume):
            return "setvol \(volume)"
        case .random(let enabled):
            return "random \(enabled ? 1 : 0)"
        case .repeat(let enabled):
            return "repeat \(enabled ? 1 : 0)"
        case .single(let mode):
            return "single \(mode.rawValue)"
        case .consume(let mode):
            return "consume \(mode.rawValue)"
        case .crossfade(let seconds):
            return "crossfade \(seconds)"
        case .shuffle:
            return "shuffle"
        case .clear:
            return "clear"
        case .update(let path):
            if let path = path {
                return "update \"\(path)\""
            } else {
                return "update"
            }
        case .rescan(let path):
            if let path = path {
                return "rescan \"\(path)\""
            } else {
                return "rescan"
            }
        case .outputs:
            return "outputs"
        case .search(let type, let query):
            return "search \(type) \"\(query)\""
        case .add(let uri):
            return "add \"\(uri)\""
        case .playId(let id):
            return "playid \(id)"
        case .delete(let position):
            return "delete \(position)"
        case .enableOutput(let id):
            return "enableoutput \(id)"
        case .disableOutput(let id):
            return "disableoutput \(id)"
        case .load(let playlist):
            return "load \"\(playlist)\""
        case .save(let playlist):
            return "save \"\(playlist)\""
        case .albumArt(let uri, let offset):
            return "albumart \"\(uri)\" \(offset)"
        case .readPicture(let uri, let offset):
            return "readpicture \"\(uri)\" \(offset)"
        }
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