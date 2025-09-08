import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var showSettings = false
    @State private var showPlaylist = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection Status
            ConnectionStatusView(appState: appState)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            if appState.mpdClient.connectionStatus == .connected {
                // Now Playing
                NowPlayingView(appState: appState)
                    .padding()
                
                Divider()
                
                // Playback Controls
                PlaybackControlsView(appState: appState)
                    .padding()
                
                Divider()
                
                // Playback Options
                PlaybackOptionsView(appState: appState)
                    .padding()
                
                Divider()
                
                // Volume Control
                VolumeControlView(appState: appState)
                    .padding()
                
                Divider()
                
                // Crossfade Control
                CrossfadeControlView(appState: appState)
                    .padding()
                
                Divider()
                
                // Playlist Button
                Button("Manage Queue...") {
                    showPlaylist = true
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
            }
            
            // Bottom Actions
            HStack {
                Button("Settings...") {
                    showSettings = true
                }
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showPlaylist) {
            PlaylistView(appState: appState)
        }
    }
}

struct ConnectionStatusView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
            
            Spacer()
            
            Button(action: toggleConnection) {
                Image(systemName: buttonIcon)
            }
            .buttonStyle(.borderless)
        }
    }
    
    private var statusText: String {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    private var buttonIcon: String {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            return "wifi.slash"
        case .disconnected, .failed:
            return "wifi"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        }
    }
    
    private func toggleConnection() {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            appState.disconnectFromMPD()
        case .disconnected, .failed:
            appState.connectToMPD()
        case .connecting:
            break
        }
    }
}

struct NowPlayingView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 4) {
            if let song = appState.mpdClient.currentSong {
                Text(song.title ?? "Unknown Title")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let album = song.album {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No song playing")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { appState.mpdClient.previous() }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            
            Button(action: playPauseAction) {
                Image(systemName: playPauseIcon)
                    .font(.system(size: 24))
            }
            .buttonStyle(.borderless)
            
            Button(action: { appState.mpdClient.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            
            Button(action: { appState.mpdClient.next() }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var playPauseIcon: String {
        switch appState.mpdClient.playerState {
        case .play:
            return "pause.circle.fill"
        case .pause, .stop, .stopped:
            return "play.circle.fill"
        }
    }
    
    private func playPauseAction() {
        switch appState.mpdClient.playerState {
        case .play:
            appState.mpdClient.pause()
        case .pause, .stop, .stopped:
            appState.mpdClient.play()
        }
    }
}

struct PlaybackOptionsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Random
            Button(action: toggleRandom) {
                Image(systemName: "shuffle")
                    .font(.system(size: 14))
                    .foregroundColor(appState.mpdClient.playbackOptions.random ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Random: \(appState.mpdClient.playbackOptions.random ? "On" : "Off")")
            
            // Repeat
            Button(action: toggleRepeat) {
                Image(systemName: "repeat")
                    .font(.system(size: 14))
                    .foregroundColor(appState.mpdClient.playbackOptions.`repeat` ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Repeat: \(appState.mpdClient.playbackOptions.`repeat` ? "On" : "Off")")
            
            // Single
            Button(action: toggleSingle) {
                HStack(spacing: 2) {
                    Image(systemName: "1.circle")
                        .font(.system(size: 14))
                    if appState.mpdClient.playbackOptions.single == .oneshot {
                        Text("1x")
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(singleColor)
            }
            .buttonStyle(.borderless)
            .help("Single: \(singleModeText)")
            
            // Consume
            Button(action: toggleConsume) {
                HStack(spacing: 2) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                    if appState.mpdClient.playbackOptions.consume == .oneshot {
                        Text("1x")
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(consumeColor)
            }
            .buttonStyle(.borderless)
            .help("Consume: \(consumeModeText)")
        }
    }
    
    private func toggleRandom() {
        appState.mpdClient.toggleRandom()
    }
    
    private func toggleRepeat() {
        appState.mpdClient.toggleRepeat()
    }
    
    private func toggleSingle() {
        appState.mpdClient.toggleSingle()
    }
    
    private func toggleConsume() {
        appState.mpdClient.toggleConsume()
    }
    
    private var singleColor: Color {
        switch appState.mpdClient.playbackOptions.single {
        case .off:
            return .secondary
        case .on, .oneshot:
            return .accentColor
        }
    }
    
    private var consumeColor: Color {
        switch appState.mpdClient.playbackOptions.consume {
        case .off:
            return .secondary
        case .on, .oneshot:
            return .accentColor
        }
    }
    
    private var singleModeText: String {
        switch appState.mpdClient.playbackOptions.single {
        case .off:
            return "Off"
        case .on:
            return "On"
        case .oneshot:
            return "One Shot"
        }
    }
    
    private var consumeModeText: String {
        switch appState.mpdClient.playbackOptions.consume {
        case .off:
            return "Off"
        case .on:
            return "On"
        case .oneshot:
            return "One Shot"
        }
    }
}

struct VolumeControlView: View {
    @ObservedObject var appState: AppState
    @State private var tempVolume: Double = 0
    @State private var isAdjusting = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volumeIcon)
                .font(.system(size: 14))
                .frame(width: 20)
            
            Slider(
                value: isAdjusting ? $tempVolume : .constant(Double(appState.mpdClient.volume)),
                in: 0...100,
                step: 1
            ) { _ in
                // onEditingChanged
                isAdjusting = true
                tempVolume = Double(appState.mpdClient.volume)
            }
            .onChange(of: tempVolume) { newValue in
                if isAdjusting {
                    appState.mpdClient.setVolume(Int(newValue))
                }
            }
            .onAppear {
                tempVolume = Double(appState.mpdClient.volume)
            }
            
            Text("\(appState.mpdClient.volume)%")
                .font(.system(size: 11))
                .frame(width: 35, alignment: .trailing)
        }
    }
    
    private var volumeIcon: String {
        if appState.mpdClient.volume == 0 {
            return "speaker.slash.fill"
        } else if appState.mpdClient.volume < 33 {
            return "speaker.wave.1.fill"
        } else if appState.mpdClient.volume < 66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

struct CrossfadeControlView: View {
    @ObservedObject var appState: AppState
    @State private var tempCrossfade: Double = 0
    @State private var isAdjusting = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 14))
                .frame(width: 20)
            
            Text("Crossfade")
                .font(.system(size: 12))
            
            Slider(
                value: isAdjusting ? $tempCrossfade : .constant(Double(appState.mpdClient.crossfade)),
                in: 0...30,
                step: 1
            ) { _ in
                // onEditingChanged
                isAdjusting = true
                tempCrossfade = Double(appState.mpdClient.crossfade)
            }
            .onChange(of: tempCrossfade) { newValue in
                if isAdjusting {
                    appState.mpdClient.setCrossfade(Int(newValue))
                }
            }
            .onAppear {
                tempCrossfade = Double(appState.mpdClient.crossfade)
            }
            
            Text("\(appState.mpdClient.crossfade)s")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 30, alignment: .trailing)
        }
    }
}