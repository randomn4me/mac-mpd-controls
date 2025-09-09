import Foundation
import MPDControlsCore
#if os(macOS)
import AppKit
#endif

@MainActor
public final class MPDClient: ObservableObject {
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var currentSong: Song?
    @Published public var playerState: PlayerState = .stopped
    @Published public var playbackOptions: PlaybackOptions = PlaybackOptions()
    @Published public var volume: Int = 0
    @Published public var crossfade: Int = 0
    
    private var connection: NetworkConnectionProtocol?
    private let host: String
    private let port: UInt16
    private var commandQueue: [MPDCommand] = []
    private var isProcessingCommand = false
    private var receiveBuffer = ""
    private var connectionRetryCount = 0
    private let maxRetryCount = 3
    private var reconnectTimer: Timer?
    private var isIdling = false
    private var shouldIdle = true
    private var lastKnownSongPosition: Int? = nil
    
    // Client-side elapsed time interpolation
    private var lastElapsedTimeFromMPD: TimeInterval = 0
    private var lastElapsedTimeUpdate: Date = Date()
    private var elapsedTimeTimer: Timer?
    
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
        reconnectTimer?.invalidate()
        reconnectTimer = nil
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
        
        connection = NetworkConnectionFactory.create()
        
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionStateChange(state)
            }
        }
        
        connection?.connect(host: host, port: port)
    }
    
    public func disconnect() {
        stopIdleMode()
        stopElapsedTimeTimer()
        connection?.disconnect()
        connection = nil
        commandQueue.removeAll()
        isProcessingCommand = false
        receiveBuffer = ""
        DispatchQueue.main.async {
            self.connectionStatus = .disconnected
        }
    }
    
    // MARK: - Client-side Elapsed Time Interpolation
    
    private func startElapsedTimeTimer() {
        stopElapsedTimeTimer()
        guard playerState == .play else { return }
        
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateInterpolatedElapsedTime()
            }
        }
    }
    
    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
    }
    
    private func updateInterpolatedElapsedTime() {
        guard playerState == .play,
              let updatedSong = currentSong else { return }
        
        let timeSinceLastUpdate = Date().timeIntervalSince(lastElapsedTimeUpdate)
        let interpolatedElapsed = lastElapsedTimeFromMPD + timeSinceLastUpdate
        
        // Clamp elapsed time to not exceed duration
        let clampedElapsed: TimeInterval
        if let duration = updatedSong.duration {
            clampedElapsed = min(interpolatedElapsed, duration)
        } else {
            clampedElapsed = interpolatedElapsed
        }
        
        // Update current song with interpolated elapsed time
        let newSong = Song(
            artist: updatedSong.artist,
            title: updatedSong.title,
            album: updatedSong.album,
            file: updatedSong.file,
            duration: updatedSong.duration,
            elapsed: clampedElapsed
        )
        currentSong = newSong
    }
    
    private func updateElapsedTimeFromMPD(_ elapsed: TimeInterval) {
        lastElapsedTimeFromMPD = elapsed
        lastElapsedTimeUpdate = Date()
        
        // Start/restart timer if playing
        if playerState == .play {
            startElapsedTimeTimer()
        } else {
            stopElapsedTimeTimer()
        }
    }
    
    private func handleConnectionStateChange(_ state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .ready:
                self?.connectionStatus = .connected
                self?.connectionRetryCount = 0
                self?.startReceiving()
                self?.updateStatus()
                self?.updateCurrentSong()
                // Start idle mode for real-time updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.startIdleMode()
                }
            case .failed(let error):
                self?.connectionStatus = .failed(error.localizedDescription)
                self?.connection?.disconnect()
                self?.connection = nil
                self?.scheduleReconnectIfNeeded()
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
        connection?.receive { [weak self] data, error in
            DispatchQueue.main.async {
                if let data = data, !data.isEmpty {
                    self?.handleReceivedData(data)
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
                
                // Process next command or restart idle mode
                if !commandQueue.isEmpty {
                    processNextCommand()
                } else if shouldIdle && connectionStatus == .connected {
                    // No more commands, restart idle mode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.startIdleMode()
                    }
                }
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
    
    private func sendCommand(_ command: String, notifyOnly: Bool = false, completion: (@Sendable (Result<[String: String], Error>) -> Void)? = nil) {
        Logger.shared.log("MPDClient: sendCommand called with: '\(command)', connection status: \(connectionStatus)")
        guard connectionStatus == .connected else {
            Logger.shared.log("MPDClient: Command '\(command)' failed - not connected")
            completion?(.failure(NSError(domain: "MPDClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }
        
        // If we're idling and this isn't a notify-only command, we need to interrupt idle
        if isIdling && !notifyOnly {
            Logger.shared.log("MPDClient: Command '\(command)' - interrupting idle mode")
            stopIdleMode()
            // Give the noidle command time to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                let mpdCommand = MPDCommand(command: command, completion: completion)
                self?.commandQueue.append(mpdCommand)
                Logger.shared.log("MPDClient: Command '\(command)' queued after idle interruption")
                if !(self?.isProcessingCommand ?? false) {
                    self?.processNextCommand()
                }
            }
        } else {
            let mpdCommand = MPDCommand(command: command, completion: completion)
            commandQueue.append(mpdCommand)
            Logger.shared.log("MPDClient: Command '\(command)' queued directly")
            
            if !isProcessingCommand {
                processNextCommand()
            }
        }
    }
    
    private func processNextCommand() {
        guard !isProcessingCommand, !commandQueue.isEmpty else { 
            Logger.shared.log("MPDClient: processNextCommand - isProcessing: \(isProcessingCommand), queueEmpty: \(commandQueue.isEmpty)")
            return 
        }
        
        isProcessingCommand = true
        let command = commandQueue.first!
        Logger.shared.log("MPDClient: Processing command: '\(command.command)'")
        
        let data = (command.command + "\n").data(using: .utf8)!
        connection?.send(data: data) { [weak self] error in
            if let error = error {
                Logger.shared.log("MPDClient: Command '\(command.command)' send failed with error: \(error)")
                Task { @MainActor in
                    self?.commandQueue.removeFirst()
                    self?.isProcessingCommand = false
                    command.completion?(.failure(error))
                    self?.processNextCommand()
                }
            } else {
                Logger.shared.log("MPDClient: Command '\(command.command)' sent successfully, waiting for response")
            }
        }
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
    
    // MARK: - Idle Mode for Real-time Updates
    
    private func startIdleMode() {
        guard connectionStatus == .connected && !isIdling && shouldIdle else { return }
        
        // Send idle command to wait for changes
        isIdling = true
        sendCommand("idle player mixer playlist options", notifyOnly: true) { [weak self] result in
            Task { @MainActor in
                self?.isIdling = false
                
                if case .success(let data) = result {
                    // Process the changed subsystems
                    self?.processIdleResponse(data)
                    
                    // Restart idle mode if still connected
                    if self?.connectionStatus == .connected && self?.shouldIdle == true {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self?.startIdleMode()
                        }
                    }
                }
            }
        }
    }
    
    private func stopIdleMode() {
        if isIdling {
            Logger.shared.log("MPDClient: Stopping idle mode")
            shouldIdle = false
            isIdling = false
            
            // Send noidle directly without queueing to interrupt the current idle command
            let data = "noidle\n".data(using: .utf8)!
            connection?.send(data: data) { error in
                Logger.shared.log("MPDClient: noidle sent directly, error: \(String(describing: error))")
            }
        }
    }
    
    private func processIdleResponse(_ data: [String: String]) {
        // Parse which subsystems changed
        var changedSubsystems: Set<String> = []
        
        for (key, value) in data {
            if key == "changed" {
                changedSubsystems.insert(value)
            }
        }
        
        // Update relevant data based on what changed
        if changedSubsystems.contains("player") {
            updateStatus()
            updateCurrentSong()
        }
        
        if changedSubsystems.contains("mixer") {
            updateStatus()
        }
        
        if changedSubsystems.contains("playlist") {
            // Playlist changed, might need to update queue
            updateCurrentSong()
        }
        
        if changedSubsystems.contains("options") {
            updateStatus()
        }
        
        // Post notification for system now playing update
        NotificationCenter.default.post(name: Notification.Name("MPDStatusChanged"), object: nil)
    }
    
    public func play() {
        sendCommand("play") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
                // Schedule additional update after brief delay to ensure UI reflects change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
            }
        }
    }
    
    public func pause() {
        sendCommand("pause") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
                // Schedule additional update after brief delay to ensure UI reflects change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
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
        Logger.shared.log("MPDClient: Toggle command called, connection status: \(connectionStatus)")
        sendCommand("pause") { [weak self] result in
            Logger.shared.log("MPDClient: Toggle command result: \(result)")
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
                // Schedule additional update after brief delay to ensure UI reflects change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
            }
        }
    }
    
    public func previous() {
        sendCommand("previous") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.updateCurrentSong()
                // Schedule additional update after brief delay to ensure UI reflects change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
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
    
    public func setCrossfade(_ seconds: Int) {
        let clampedSeconds = max(0, min(120, seconds))
        sendCommand("crossfade \(clampedSeconds)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func clearQueue() {
        sendCommand("clear") { _ in }
    }
    
    public func addToQueue(_ uri: String) {
        sendCommand("add \"\(uri)\"") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func addToQueueAndPlay(_ uri: String) {
        sendCommand("add \"\(uri)\"") { [weak self] _ in
            Task { @MainActor in
                self?.sendCommand("play") { _ in
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
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
    
    public func deleteId(_ id: Int) {
        sendCommand("deleteid \(id)") { [weak self] _ in
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
    
    // MARK: - Playlist Management
    
    public func listPlaylists(completion: @escaping ([String]) -> Void) {
        sendCommand("listplaylists") { result in
            switch result {
            case .success(let data):
                let playlists = data.compactMap { key, value in
                    key == "playlist" ? value : nil
                }
                completion(playlists)
            case .failure:
                completion([])
            }
        }
    }
    
    public func loadPlaylist(_ name: String) {
        sendCommand("load \"\(name)\"") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func savePlaylist(_ name: String) {
        sendCommand("save \"\(name)\"") { _ in }
    }
    
    public func deletePlaylist(_ name: String) {
        sendCommand("rm \"\(name)\"") { _ in }
    }
    
    public func addToPlaylist(_ name: String, uri: String) {
        sendCommand("playlistadd \"\(name)\" \"\(uri)\"") { _ in }
    }
    
    public func shuffleQueue() {
        sendCommand("shuffle") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    // MARK: - Database Operations
    
    public func updateDatabase(path: String? = nil) {
        let command = path != nil ? "update \"\(path!)\"" : "update"
        sendCommand(command) { _ in }
    }
    
    public func rescanDatabase(path: String? = nil) {
        let command = path != nil ? "rescan \"\(path!)\"" : "rescan"
        sendCommand(command) { _ in }
    }
    
    // MARK: - Output Control
    
    public func listOutputs(completion: @escaping ([(id: Int, name: String, enabled: Bool)]) -> Void) {
        sendCommand("outputs") { result in
            switch result {
            case .success(let data):
                var outputs: [(id: Int, name: String, enabled: Bool)] = []
                var currentId: Int?
                var currentName: String?
                var currentEnabled: Bool?
                
                for (key, value) in data {
                    switch key {
                    case "outputid":
                        if let id = currentId, let name = currentName, let enabled = currentEnabled {
                            outputs.append((id: id, name: name, enabled: enabled))
                        }
                        currentId = Int(value)
                        currentName = nil
                        currentEnabled = nil
                    case "outputname":
                        currentName = value
                    case "outputenabled":
                        currentEnabled = value == "1"
                    default:
                        break
                    }
                }
                
                if let id = currentId, let name = currentName, let enabled = currentEnabled {
                    outputs.append((id: id, name: name, enabled: enabled))
                }
                
                completion(outputs)
            case .failure:
                completion([])
            }
        }
    }
    
    public func enableOutput(_ id: Int) {
        sendCommand("enableoutput \(id)") { _ in }
    }
    
    public func disableOutput(_ id: Int) {
        sendCommand("disableoutput \(id)") { _ in }
    }
    
    public func toggleOutput(_ id: Int) {
        sendCommand("toggleoutput \(id)") { _ in }
    }
    
    // MARK: - Queue Management
    
    public struct QueueItem: Identifiable {
        public let id: Int
        public let position: Int
        public let file: String?
        public let artist: String?
        public let title: String?
        public let album: String?
        public let duration: TimeInterval?
    }
    
    public func getQueue(completion: @escaping (Result<[QueueItem], Error>) -> Void) {
        sendCommand("playlistinfo") { result in
            switch result {
            case .success(let data):
                var items: [QueueItem] = []
                var currentId: Int?
                var currentPos: Int?
                var currentFile: String?
                var currentArtist: String?
                var currentTitle: String?
                var currentAlbum: String?
                var currentDuration: TimeInterval?
                
                for (key, value) in data.sorted(by: { $0.key < $1.key }) {
                    switch key {
                    case "file":
                        if let id = currentId, let pos = currentPos, let file = currentFile {
                            items.append(QueueItem(
                                id: id,
                                position: pos,
                                file: file,
                                artist: currentArtist,
                                title: currentTitle,
                                album: currentAlbum,
                                duration: currentDuration
                            ))
                        }
                        currentFile = value
                        currentArtist = nil
                        currentTitle = nil
                        currentAlbum = nil
                        currentDuration = nil
                    case "Id":
                        currentId = Int(value)
                    case "Pos":
                        currentPos = Int(value)
                    case "Artist":
                        currentArtist = value
                    case "Title":
                        currentTitle = value
                    case "Album":
                        currentAlbum = value
                    case "Time":
                        currentDuration = TimeInterval(value)
                    default:
                        break
                    }
                }
                
                if let id = currentId, let pos = currentPos, let file = currentFile {
                    items.append(QueueItem(
                        id: id,
                        position: pos,
                        file: file,
                        artist: currentArtist,
                        title: currentTitle,
                        album: currentAlbum,
                        duration: currentDuration
                    ))
                }
                
                completion(.success(items))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    public func deleteFromQueue(position: Int) {
        sendCommand("delete \(position)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func deleteFromQueue(id: Int) {
        sendCommand("deleteid \(id)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func moveInQueue(from: Int, to: Int) {
        sendCommand("move \(from) \(to)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func moveInQueue(id: Int, to: Int) {
        sendCommand("moveid \(id) \(to)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func swapInQueue(pos1: Int, pos2: Int) {
        sendCommand("swap \(pos1) \(pos2)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func swapInQueue(id1: Int, id2: Int) {
        sendCommand("swapid \(id1) \(id2)") { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    public func addAndPlay(_ uri: String) {
        sendCommand("add \"\(uri)\"") { [weak self] _ in
            Task { @MainActor in
                self?.sendCommand("play") { _ in
                    Task { @MainActor in
                        self?.updateStatus()
                        self?.updateCurrentSong()
                    }
                }
            }
        }
    }
    
    public func insertAndPlay(_ uri: String, at position: Int) {
        sendCommand("addid \"\(uri)\" \(position)") { [weak self] result in
            if case .success(let data) = result,
               let idStr = data["Id"],
               let id = Int(idStr) {
                Task { @MainActor in
                    self?.playId(id)
                }
            }
        }
    }
    
    // MARK: - Search
    
    public struct SearchResult {
        public let file: String
        public let artist: String?
        public let title: String?
        public let album: String?
        public let duration: TimeInterval?
    }
    
    public func search(type: String, query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        sendCommand("search \(type) \"\(query)\"") { result in
            switch result {
            case .success(let data):
                var results: [SearchResult] = []
                var currentFile: String?
                var currentArtist: String?
                var currentTitle: String?
                var currentAlbum: String?
                var currentDuration: TimeInterval?
                
                for (key, value) in data {
                    switch key {
                    case "file":
                        if let file = currentFile {
                            results.append(SearchResult(
                                file: file,
                                artist: currentArtist,
                                title: currentTitle,
                                album: currentAlbum,
                                duration: currentDuration
                            ))
                        }
                        currentFile = value
                        currentArtist = nil
                        currentTitle = nil
                        currentAlbum = nil
                        currentDuration = nil
                    case "Artist":
                        currentArtist = value
                    case "Title":
                        currentTitle = value
                    case "Album":
                        currentAlbum = value
                    case "Time":
                        currentDuration = TimeInterval(value)
                    default:
                        break
                    }
                }
                
                if let file = currentFile {
                    results.append(SearchResult(
                        file: file,
                        artist: currentArtist,
                        title: currentTitle,
                        album: currentAlbum,
                        duration: currentDuration
                    ))
                }
                
                completion(.success(results))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    public func searchArtist(_ query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        search(type: "artist", query: query, completion: completion)
    }
    
    public func searchAlbum(_ query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        search(type: "album", query: query, completion: completion)
    }
    
    public func searchTitle(_ query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        search(type: "title", query: query, completion: completion)
    }
    
    public func searchAny(_ query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        search(type: "any", query: query, completion: completion)
    }
    
    // MARK: - Statistics
    
    public struct MPDStats {
        public let artists: Int
        public let albums: Int
        public let songs: Int
        public let uptime: TimeInterval
        public let playtime: TimeInterval
        public let dbPlaytime: TimeInterval
        public let dbUpdate: Date?
    }
    
    public func getStats(completion: @escaping (MPDStats?) -> Void) {
        sendCommand("stats") { result in
            switch result {
            case .success(let data):
                guard let artists = data["artists"].flatMap(Int.init),
                      let albums = data["albums"].flatMap(Int.init),
                      let songs = data["songs"].flatMap(Int.init),
                      let uptime = data["uptime"].flatMap(TimeInterval.init),
                      let playtime = data["playtime"].flatMap(TimeInterval.init),
                      let dbPlaytime = data["db_playtime"].flatMap(TimeInterval.init) else {
                    completion(nil)
                    return
                }
                
                let dbUpdate = data["db_update"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                
                let stats = MPDStats(
                    artists: artists,
                    albums: albums,
                    songs: songs,
                    uptime: uptime,
                    playtime: playtime,
                    dbPlaytime: dbPlaytime,
                    dbUpdate: dbUpdate
                )
                completion(stats)
            case .failure:
                completion(nil)
            }
        }
    }
    
    // MARK: - Idle Command Support
    
    public enum IdleSubsystem: String, CaseIterable {
        case database
        case update
        case storedPlaylist = "stored_playlist"
        case playlist
        case player
        case mixer
        case output
        case options
        case partition
        case sticker
        case subscription
        case message
    }
    
    public func idle(subsystems: [IdleSubsystem] = [], completion: @escaping ([IdleSubsystem]) -> Void) {
        let command: String
        if subsystems.isEmpty {
            command = "idle"
        } else {
            let subsystemStrings = subsystems.map { $0.rawValue }.joined(separator: " ")
            command = "idle \(subsystemStrings)"
        }
        
        sendCommand(command) { result in
            switch result {
            case .success(let data):
                let changedSubsystems = data.compactMap { key, _ in
                    key == "changed" ? nil : IdleSubsystem(rawValue: key)
                }
                completion(changedSubsystems)
            case .failure:
                completion([])
            }
        }
    }
    
    public func noIdle() {
        sendCommand("noidle") { _ in }
    }
    
    // MARK: - Error Recovery
    
    private func scheduleReconnectIfNeeded() {
        guard connectionRetryCount < maxRetryCount else {
            print("Max reconnection attempts reached. Giving up.")
            return
        }
        
        connectionRetryCount += 1
        let delay = TimeInterval(connectionRetryCount * 2) // Exponential backoff
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                print("Attempting to reconnect (attempt \(self?.connectionRetryCount ?? 0)/\(self?.maxRetryCount ?? 0))...")
                self?.connect()
            }
        }
    }
    
    public func resetConnection() {
        disconnect()
        connectionRetryCount = 0
        connect()
    }
    
    // MARK: - Response Parsing
    
    private func parseStatusResponse(_ data: [String: String]) {
        let oldPlayerState = playerState
        
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
        
        if let crossfadeStr = data["xfade"], let xfade = Int(crossfadeStr) {
            crossfade = xfade
        }
        
        // Update elapsed time if available in status response
        if let elapsedStr = data["elapsed"], let elapsed = TimeInterval(elapsedStr) {
            updateElapsedTimeFromMPD(elapsed)
            
            // Update current song with new elapsed time while preserving other info
            // Only update if we're not playing (to avoid overriding interpolated values)
            // or if this is a significant change (indicating a seek or song change)
            if var updatedSong = currentSong {
                let shouldUpdate = playerState != .play || 
                                  updatedSong.elapsed == nil ||
                                  abs((updatedSong.elapsed ?? 0) - elapsed) > 1.0
                
                if shouldUpdate {
                    updatedSong = Song(
                        artist: updatedSong.artist,
                        title: updatedSong.title,
                        album: updatedSong.album,
                        file: updatedSong.file,
                        duration: updatedSong.duration,
                        elapsed: elapsed
                    )
                    currentSong = updatedSong
                }
            }
        }
        
        // Handle player state changes
        if oldPlayerState != playerState {
            switch playerState {
            case .play:
                startElapsedTimeTimer()
            case .pause, .stop, .stopped:
                // When pausing/stopping, capture the current interpolated elapsed time
                if oldPlayerState == .play {
                    updateInterpolatedElapsedTime()
                }
                stopElapsedTimeTimer()
            }
        }
        
        // Check if song position has changed (indicates song change)
        if let songposStr = data["song"], let songpos = Int(songposStr) {
            if songpos != lastKnownSongPosition {
                lastKnownSongPosition = songpos
                // Song changed, update current song info
                updateCurrentSong()
            }
        }
        
        // For streaming sources or other cases where title might change during playback,
        // periodically refresh song metadata if we're playing
        if playerState == .play && currentSong != nil {
            // Check if enough time has passed since last metadata update (avoid too frequent calls)
            // This will be handled by periodic calls to updateCurrentSong() from the timer
        }
    }
    
    private func parseCurrentSongResponse(_ data: [String: String]) {
        let duration = data["Time"].flatMap { TimeInterval($0) }
        let elapsed = data["elapsed"].flatMap { TimeInterval($0) }
        
        // Update elapsed time tracking if available
        if let elapsed = elapsed {
            updateElapsedTimeFromMPD(elapsed)
        }
        
        // Preserve existing elapsed time if not provided in currentsong response
        let finalElapsed = elapsed ?? currentSong?.elapsed
        
        currentSong = Song(
            artist: data["Artist"],
            title: data["Title"],
            album: data["Album"],
            file: data["file"],
            duration: duration,
            elapsed: finalElapsed
        )
    }
}