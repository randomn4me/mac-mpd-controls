import SwiftUI

struct PlaylistView: View {
    @ObservedObject var appState: AppState
    @State private var currentQueue: [MPDClient.QueueItem] = []
    @State private var selectedItemId: Int?
    @State private var showAddUrl = false
    @State private var urlToAdd = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Current Queue")
                    .font(.headline)
                
                Spacer()
                
                Button(action: refreshQueue) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                
                Button(action: clearQueue) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                
                Button(action: shuffleQueue) {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Queue List
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(currentQueue) { item in
                        QueueItemRow(
                            item: item,
                            isSelected: selectedItemId == item.id,
                            isPlaying: isCurrentlyPlaying(item),
                            onSelect: { selectedItemId = item.id },
                            onPlay: { playItem(item) },
                            onRemove: { removeItem(item) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            // Add URL Section
            HStack {
                TextField("Add URL or path...", text: $urlToAdd)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addUrl()
                    }
                
                Button("Add") {
                    addUrl()
                }
                .disabled(urlToAdd.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            refreshQueue()
        }
    }
    
    private func isCurrentlyPlaying(_ item: MPDClient.QueueItem) -> Bool {
        guard let currentSong = appState.mpdClient.currentSong else { return false }
        // Check if this queue item matches the current song
        return item.title == currentSong.title && 
               item.artist == currentSong.artist &&
               item.file == currentSong.file
    }
    
    private func refreshQueue() {
        appState.mpdClient.getQueue { result in
            switch result {
            case .success(let items):
                currentQueue = items
            case .failure(let error):
                print("Failed to get queue: \(error)")
            }
        }
    }
    
    private func clearQueue() {
        appState.mpdClient.clearQueue()
        currentQueue = []
    }
    
    private func shuffleQueue() {
        appState.mpdClient.shuffleQueue()
        // Refresh after shuffle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshQueue()
        }
    }
    
    private func playItem(_ item: MPDClient.QueueItem) {
        appState.mpdClient.playId(item.id)
    }
    
    private func removeItem(_ item: MPDClient.QueueItem) {
        appState.mpdClient.deleteId(item.id)
        // Remove from local list immediately for better UX
        currentQueue.removeAll { $0.id == item.id }
    }
    
    private func addUrl() {
        guard !urlToAdd.isEmpty else { return }
        appState.mpdClient.addToQueue(urlToAdd)
        urlToAdd = ""
        // Refresh after adding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshQueue()
        }
    }
}

struct QueueItemRow: View {
    let item: MPDClient.QueueItem
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Playing indicator
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
            } else {
                Color.clear
                    .frame(width: 20)
            }
            
            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? item.file ?? "Unknown")
                    .font(.system(size: 12, weight: isPlaying ? .semibold : .regular))
                    .lineLimit(1)
                
                if let artist = item.artist {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Duration
            if let duration = item.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Actions
            Button(action: onPlay) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .opacity(isPlaying ? 0.5 : 1.0)
            .disabled(isPlaying)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// Note: QueueItem struct is defined in MPDClient.swift
// Making QueueItem Equatable
extension MPDClient.QueueItem: Equatable {
    public static func == (lhs: MPDClient.QueueItem, rhs: MPDClient.QueueItem) -> Bool {
        return lhs.id == rhs.id && lhs.position == rhs.position
    }
}