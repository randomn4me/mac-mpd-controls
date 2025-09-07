import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 14))
            
            if let song = appState.mpdClient.currentSong,
               appState.mpdClient.playerState == .play {
                Text(songDisplay(song))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }
        }
    }
    
    private var iconName: String {
        switch appState.mpdClient.connectionStatus {
        case .connected:
            switch appState.mpdClient.playerState {
            case .play:
                return "play.circle.fill"
            case .pause:
                return "pause.circle.fill"
            case .stop, .stopped:
                return "stop.circle"
            }
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .disconnected:
            return "music.note"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
    
    private func songDisplay(_ song: MPDClient.Song) -> String {
        if let title = song.title {
            if let artist = song.artist {
                return "\(artist) - \(title)"
            }
            return title
        }
        return song.file ?? "Unknown"
    }
}