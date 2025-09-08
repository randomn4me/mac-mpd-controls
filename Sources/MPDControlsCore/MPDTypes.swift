import Foundation

public enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

public enum PlayerState: String {
    case play
    case pause
    case stop
    case stopped
}

public struct Song: Equatable {
    public let artist: String?
    public let title: String?
    public let album: String?
    public let file: String?
    public let duration: TimeInterval?
    public let elapsed: TimeInterval?
    
    public init(artist: String?, title: String?, album: String?, file: String?, duration: TimeInterval?, elapsed: TimeInterval?) {
        self.artist = artist
        self.title = title
        self.album = album
        self.file = file
        self.duration = duration
        self.elapsed = elapsed
    }
}

public struct PlaybackOptions: Equatable {
    public var random: Bool = false
    public var `repeat`: Bool = false
    public var single: SingleMode = .off
    public var consume: ConsumeMode = .off
    
    public enum SingleMode: String {
        case off = "0"
        case on = "1"
        case oneshot = "oneshot"
    }
    
    public enum ConsumeMode: String {
        case off = "0"
        case on = "1"
        case oneshot = "oneshot"
    }
    
    public init(random: Bool = false, repeat: Bool = false, single: SingleMode = .off, consume: ConsumeMode = .off) {
        self.random = random
        self.`repeat` = `repeat`
        self.single = single
        self.consume = consume
    }
}