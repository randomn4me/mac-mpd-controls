import SwiftUI

struct SearchView: View {
    @ObservedObject var appState: AppState
    @State private var searchText = ""
    @State private var searchType: SearchType = .any
    @State private var searchResults: [MPDClient.SearchResult] = []
    @State private var isSearching = false
    @State private var selectedResult: MPDClient.SearchResult?
    
    enum SearchType: String, CaseIterable {
        case any = "any"
        case artist = "artist"
        case album = "album"
        case title = "title"
        case filename = "filename"
        
        var displayName: String {
            switch self {
            case .any: return "All"
            case .artist: return "Artist"
            case .album: return "Album"
            case .title: return "Title"
            case .filename: return "Filename"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            VStack(spacing: 12) {
                Text("Search Music Database")
                    .font(.headline)
                
                HStack {
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            performSearch()
                        }
                    
                    Picker("Type", selection: $searchType) {
                        ForEach(SearchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    
                    Button("Search") {
                        performSearch()
                    }
                    .disabled(searchText.isEmpty || isSearching)
                }
            }
            .padding()
            
            Divider()
            
            // Results
            if isSearching {
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if searchResults.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(searchResults) { result in
                            SearchResultRow(
                                result: result,
                                isSelected: selectedResult?.id == result.id,
                                onSelect: { selectedResult = result },
                                onAdd: { addToQueue(result) },
                                onPlay: { playNow(result) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
            
            Divider()
            
            // Actions
            HStack {
                Text("\(searchResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Add All") {
                    addAllToQueue()
                }
                .disabled(searchResults.isEmpty)
                
                Button("Clear") {
                    clearSearch()
                }
                .disabled(searchResults.isEmpty)
            }
            .padding()
        }
        .frame(width: 500)
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        appState.mpdClient.search(type: searchType.rawValue, query: searchText) { result in
            isSearching = false
            switch result {
            case .success(let results):
                searchResults = results
            case .failure(let error):
                print("Search failed: \(error)")
                searchResults = []
            }
        }
    }
    
    private func addToQueue(_ result: MPDClient.SearchResult) {
        appState.mpdClient.addToQueue(result.file)
    }
    
    private func playNow(_ result: MPDClient.SearchResult) {
        appState.mpdClient.addToQueueAndPlay(result.file)
    }
    
    private func addAllToQueue() {
        for result in searchResults {
            appState.mpdClient.addToQueue(result.file)
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
        selectedResult = nil
    }
}

struct SearchResultRow: View {
    let result: MPDClient.SearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title ?? result.file)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                if let artist = result.artist {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let album = result.album {
                    Text(album)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Duration
            if let duration = result.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Actions
            Button(action: onAdd) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add to queue")
            
            Button(action: onPlay) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Play now")
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

// Note: SearchResult struct is defined in MPDClient.swift
// Making SearchResult Identifiable and Equatable
extension MPDClient.SearchResult: Identifiable, Equatable {
    public var id: String { file }
    
    public static func == (lhs: MPDClient.SearchResult, rhs: MPDClient.SearchResult) -> Bool {
        return lhs.file == rhs.file
    }
}