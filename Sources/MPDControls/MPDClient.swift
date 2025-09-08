import Foundation
import Network

@MainActor
public final class MPDClient: ObservableObject {
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var currentSong: Song?
    @Published public var playerState: PlayerState = .stopped
    @Published public var playbackOptions: PlaybackOptions = PlaybackOptions()
    @Published public var volume: Int = 0
    
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var commandQueue: [MPDCommand] = []
    private var isProcessingCommand = false
    private var receiveBuffer = ""
    
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
    }
    
    private struct MPDCommand: Sendable {
        let command: String
        let completion: (@Sendable (Result<[String: String], Error>) -> Void)?
    }
    
    public init(host: String = "127.0.0.1", port: UInt16 = 6600) {
        self.host = host
        self.port = port
    }
    
    deinit {
        connection?.cancel()
        connection = nil
        commandQueue.removeAll()
        isProcessingCommand = false
        receiveBuffer = ""
    }
    
    // MARK: - Connection Management
    
    public func connect() {
        guard connection == nil else { return }
        
        connectionStatus = .connecting
        
        let endpoint = NWEndpoint.Host(host)
        let portEndpoint = NWEndpoint.Port(rawValue: port)!
        
        connection = NWConnection(host: endpoint, port: portEndpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionStateChange(state)
            }
        }
        
        connection?.start(queue: .global(qos: .userInitiated))
    }
    
    public func disconnect() {
        connection?.cancel()
        connection = nil
        commandQueue.removeAll()
        isProcessingCommand = false
        receiveBuffer = ""
        DispatchQueue.main.async {
            self.connectionStatus = .disconnected
        }
    }
    
    private func handleConnectionStateChange(_ state: NWConnection.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .ready:
                self?.connectionStatus = .connected
                self?.startReceiving()
                self?.updateStatus()
                self?.updateCurrentSong()
            case .failed(let error):
                self?.connectionStatus = .failed(error.localizedDescription)
                self?.connection?.cancel()
                self?.connection = nil
            case .cancelled:
                self?.connectionStatus = .disconnected
                self?.connection = nil
            case .waiting(let error):
                self?.connectionStatus = .failed("Waiting: \(error.localizedDescription)")
            default:
                break
            }
        }
    }
    
    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                if let data = data, !data.isEmpty {
                    self?.handleReceivedData(data)
                }
                
                if error == nil && !isComplete {
                    self?.startReceiving()
                } else if let error = error {
                    self?.connectionStatus = .failed("Receive error: \(error.localizedDescription)")
                    self?.disconnect()
                }
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        receiveBuffer += string
        
        if receiveBuffer.contains("OK\n") || receiveBuffer.contains("ACK ") {
            let response = receiveBuffer
            receiveBuffer = ""
            
            if let command = commandQueue.first {
                commandQueue.removeFirst()
                isProcessingCommand = false
                
                let result = parseResponse(response)
                command.completion?(.success(result))
                
                processNextCommand()
            } else {
                // Initial connection response
                if response.hasPrefix("OK MPD") {
                    // Successfully connected to MPD
                }
            }
        }
    }
    
    private func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]
        
        let lines = response.split(separator: "\n")
        for line in lines {
            if line == "OK" || line.hasPrefix("ACK ") {
                continue
            }
            
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        
        return result
    }
    
    // MARK: - Command Execution
    
    private func sendCommand(_ command: String, completion: (@Sendable (Result<[String: String], Error>) -> Void)? = nil) {
        guard connectionStatus == .connected else {
            completion?(.failure(NSError(domain: "MPDClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }
        
        let mpdCommand = MPDCommand(command: command, completion: completion)
        commandQueue.append(mpdCommand)
        
        if !isProcessingCommand {
            processNextCommand()
        }
    }
    
    private func processNextCommand() {
        guard !isProcessingCommand, !commandQueue.isEmpty else { return }
        
        isProcessingCommand = true
        let command = commandQueue.first!
        
        let data = (command.command + "\n").data(using: .utf8)!
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.commandQueue.removeFirst()
                    self?.isProcessingCommand = false
                    command.completion?(.failure(error))
                    self?.processNextCommand()
                }
            }
        })
    }
    
    // MARK: - Public Commands
    
    public func updateStatus() {
        sendCommand("status") { [weak self] result in
            if case .success(let data) = result {
                DispatchQueue.main.async {
                    self?.parseStatusResponse(data)
                }
            }
        }
    }
    
    public func updateCurrentSong() {
        sendCommand("currentsong") { [weak self] result in
            if case .success(let data) = result {
                DispatchQueue.main.async {
                    self?.parseCurrentSongResponse(data)
                }
            }
        }
    }
    
    public func play() {
        sendCommand("play") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
            }
        }
    }
    
    public func pause() {
        sendCommand("pause") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func stop() {
        sendCommand("stop") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
            }
        }
    }
    
    public func toggle() {
        sendCommand("pause") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func next() {
        sendCommand("next") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
            }
        }
    }
    
    public func previous() {
        sendCommand("previous") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
            }
        }
    }
    
    public func toggleRandom() {
        let newValue = !playbackOptions.random
        sendCommand("random \(newValue ? 1 : 0)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func toggleRepeat() {
        let newValue = !playbackOptions.`repeat`
        sendCommand("repeat \(newValue ? 1 : 0)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func toggleSingle() {
        let newMode: PlaybackOptions.SingleMode
        switch playbackOptions.single {
        case .off:
            newMode = .on
        case .on:
            newMode = .oneshot
        case .oneshot:
            newMode = .off
        }
        sendCommand("single \(newMode.rawValue)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func toggleConsume() {
        let newMode: PlaybackOptions.ConsumeMode
        switch playbackOptions.consume {
        case .off:
            newMode = .on
        case .on:
            newMode = .off
        case .oneshot:
            newMode = .off
        }
        sendCommand("consume \(newMode.rawValue)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func setRandom(_ enabled: Bool) {
        sendCommand("random \(enabled ? 1 : 0)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func setRepeat(_ enabled: Bool) {
        sendCommand("repeat \(enabled ? 1 : 0)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func setSingle(_ mode: PlaybackOptions.SingleMode) {
        sendCommand("single \(mode.rawValue)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func setConsume(_ mode: PlaybackOptions.ConsumeMode) {
        sendCommand("consume \(mode.rawValue)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func setVolume(_ volume: Int) {
        let clampedVolume = max(0, min(100, volume))
        sendCommand("setvol \(clampedVolume)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func increaseVolume(by amount: Int = 5) {
        setVolume(volume + amount)
    }
    
    public func decreaseVolume(by amount: Int = 5) {
        setVolume(volume - amount)
    }
    
    public func clear() {
        sendCommand("clear") { _ in }
    }
    
    public func addUri(_ uri: String) {
        sendCommand("add \(uri)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func playId(_ id: Int) {
        sendCommand("playid \(id)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
            }
        }
    }
    
    public func seek(to position: TimeInterval) {
        sendCommand("seekcur \(position)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    // MARK: - Response Parsing
    
    private func parseStatusResponse(_ data: [String: String]) {
        if let state = data["state"] {
            switch state {
            case "play":
                playerState = .play
            case "pause":
                playerState = .pause
            case "stop":
                playerState = .stop
            default:
                playerState = .stopped
            }
        }
        
        playbackOptions.random = data["random"] == "1"
        playbackOptions.`repeat` = data["repeat"] == "1"
        
        if let single = data["single"] {
            switch single {
            case "1":
                playbackOptions.single = .on
            case "oneshot":
                playbackOptions.single = .oneshot
            default:
                playbackOptions.single = .off
            }
        }
        
        if let consume = data["consume"] {
            switch consume {
            case "1":
                playbackOptions.consume = .on
            case "oneshot":
                playbackOptions.consume = .oneshot
            default:
                playbackOptions.consume = .off
            }
        }
        
        if let volumeStr = data["volume"], let vol = Int(volumeStr) {
            volume = vol
        }
    }
    
    private func parseCurrentSongResponse(_ data: [String: String]) {
        let duration = data["Time"].flatMap { TimeInterval($0) }
        let elapsed = data["elapsed"].flatMap { TimeInterval($0) }
        
        currentSong = Song(
            artist: data["Artist"],
            title: data["Title"],
            album: data["Album"],
            file: data["file"],
            duration: duration,
            elapsed: elapsed
        )
    }
}