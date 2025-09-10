import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
public final class AlbumArtManager {
    private let mpdClient: MPDClient
    private var artworkCache: [String: NSImage] = [:] // Keyed by album+artist
    private var fileToAlbumCache: [String: String] = [:] // Maps file URI to album key
    private var currentlyFetching: Set<String> = []
    private var musicDirectory: String?
    private let diskCacheDirectory: URL
    
    public init(mpdClient: MPDClient) {
        self.mpdClient = mpdClient
        
        // Set up disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = cacheDir.appendingPathComponent("MPDControls/AlbumArt")
        
        // Create cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true, attributes: nil)
            Logger.shared.log("AlbumArtManager: Disk cache directory created at: \(diskCacheDirectory.path)")
        } catch {
            Logger.shared.log("AlbumArtManager: Failed to create disk cache directory: \(error)")
        }
        
        detectMusicDirectory()
    }
    
    private func detectMusicDirectory() {
        Logger.shared.log("AlbumArtManager: Detecting music directory...")
        
        var possiblePaths: [String] = []
        
        // Check XDG_MUSIC_DIR environment variable first
        if let xdgMusicDir = ProcessInfo.processInfo.environment["XDG_MUSIC_DIR"] {
            possiblePaths.append(xdgMusicDir)
            Logger.shared.log("AlbumArtManager: Found XDG_MUSIC_DIR: \(xdgMusicDir)")
        }
        
        // Add common MPD music directory locations
        possiblePaths.append(contentsOf: [
            "~/Music",
            "/var/lib/mpd/music",
            "/usr/share/mpd/music",
            "/opt/homebrew/var/lib/mpd/music"
        ])
        
        for path in possiblePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            Logger.shared.log("AlbumArtManager: Checking path: \(expandedPath)")
            if FileManager.default.fileExists(atPath: expandedPath) {
                musicDirectory = expandedPath
                Logger.shared.log("AlbumArtManager: Found music directory: \(expandedPath)")
                return
            }
        }
        
        Logger.shared.log("AlbumArtManager: No music directory found in common locations")
    }
    
    private func albumCacheKey(for song: MPDClient.Song) -> String {
        // Create a cache key based on album and artist (not file path)
        let artist = song.artist ?? "unknown_artist"
        let album = song.album ?? "unknown_album"
        return "\(artist)_\(album)"
    }
    
    public func getAlbumArt(for song: MPDClient.Song, completion: @escaping (NSImage?) -> Void) {
        guard let fileURI = song.file else {
            Logger.shared.log("AlbumArtManager: No file URI for song")
            completion(nil)
            return
        }
        
        let albumKey = albumCacheKey(for: song)
        Logger.shared.log("AlbumArtManager: Requesting album art for album key: \(albumKey) (file: \(fileURI))")
        
        // Store the mapping for future reference
        fileToAlbumCache[fileURI] = albumKey
        
        // Check memory cache first using album key
        if let cachedImage = artworkCache[albumKey] {
            Logger.shared.log("AlbumArtManager: Found memory cached album art for album: \(albumKey)")
            completion(cachedImage)
            return
        }
        
        // Check disk cache second using album key
        if let diskCachedImage = loadFromDiskCache(albumKey: albumKey) {
            Logger.shared.log("AlbumArtManager: Found disk cached album art for album: \(albumKey)")
            artworkCache[albumKey] = diskCachedImage // Store in memory cache
            completion(diskCachedImage)
            return
        }
        
        // Avoid duplicate requests for the same album
        if currentlyFetching.contains(albumKey) {
            Logger.shared.log("AlbumArtManager: Already fetching album art for album: \(albumKey)")
            completion(nil)
            return
        }
        
        Logger.shared.log("AlbumArtManager: Starting album art fetch for album: \(albumKey)")
        currentlyFetching.insert(albumKey)
        
        // Try to extract embedded album art first using ffmpeg
        extractEmbeddedAlbumArt(fileURI: fileURI) { [weak self] image in
            if let image = image {
                Logger.shared.log("AlbumArtManager: Successfully extracted embedded album art for album: \(albumKey)")
                self?.artworkCache[albumKey] = image
                self?.saveToDiskCache(image: image, albumKey: albumKey)
                self?.currentlyFetching.remove(albumKey)
                completion(image)
            } else {
                Logger.shared.log("AlbumArtManager: No embedded album art found, trying local cover files for: \(fileURI)")
                // Fallback to looking for cover files in the directory
                self?.findLocalCoverArt(fileURI: fileURI) { [weak self] image in
                    if let image = image {
                        Logger.shared.log("AlbumArtManager: Found local cover art for album: \(albumKey)")
                        self?.artworkCache[albumKey] = image
                        self?.saveToDiskCache(image: image, albumKey: albumKey)
                        self?.currentlyFetching.remove(albumKey)
                        completion(image)
                    } else {
                        Logger.shared.log("AlbumArtManager: No local cover art found, trying online search for: \(fileURI)")
                        // Final fallback: try online search
                        self?.fetchOnlineAlbumArt(for: song) { [weak self] onlineImage in
                            if let onlineImage = onlineImage {
                                Logger.shared.log("AlbumArtManager: Found online album art for album: \(albumKey)")
                                self?.artworkCache[albumKey] = onlineImage
                                self?.saveToDiskCache(image: onlineImage, albumKey: albumKey)
                            } else {
                                Logger.shared.log("AlbumArtManager: No album art found anywhere for album: \(albumKey)")
                            }
                            self?.currentlyFetching.remove(albumKey)
                            completion(onlineImage)
                        }
                    }
                }
            }
        }
    }
    
    private func extractEmbeddedAlbumArt(fileURI: String, completion: @escaping (NSImage?) -> Void) {
        guard let musicDir = musicDirectory else {
            Logger.shared.log("AlbumArtManager: No music directory configured")
            completion(nil)
            return
        }
        
        let fullPath = URL(fileURLWithPath: musicDir).appendingPathComponent(fileURI).path
        Logger.shared.log("AlbumArtManager: Trying to extract from: \(fullPath)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fullPath) else {
            Logger.shared.log("AlbumArtManager: Music file not found at: \(fullPath)")
            completion(nil)
            return
        }
        
        // Create temporary file for extracted artwork
        let tempDir = NSTemporaryDirectory()
        let tempFile = URL(fileURLWithPath: tempDir).appendingPathComponent("album_art_\(UUID().uuidString).jpg").path
        
        // Use ffmpeg to extract embedded album art
        let process = Process()
        process.launchPath = "/usr/local/bin/ffmpeg"
        process.arguments = [
            "-i", fullPath,
            "-map", "0:v:0",
            "-c", "copy",
            tempFile,
            "-y"
        ]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                Logger.shared.log("AlbumArtManager: ffmpeg process terminated with exit code: \(process.terminationStatus)")
                
                // Read error output
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                if !errorData.isEmpty {
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unable to decode error"
                    Logger.shared.log("AlbumArtManager: ffmpeg stderr: \(errorString)")
                }
                
                // Check if the extraction was successful
                if FileManager.default.fileExists(atPath: tempFile) {
                    Logger.shared.log("AlbumArtManager: Temporary album art file created: \(tempFile)")
                    if let image = NSImage(contentsOfFile: tempFile) {
                        Logger.shared.log("AlbumArtManager: Successfully loaded extracted album art")
                        completion(image)
                    } else {
                        Logger.shared.log("AlbumArtManager: Failed to load image from temporary file")
                        completion(nil)
                    }
                    // Clean up temp file
                    do {
                        try FileManager.default.removeItem(atPath: tempFile)
                        Logger.shared.log("AlbumArtManager: Cleaned up temporary file")
                    } catch {
                        Logger.shared.log("AlbumArtManager: Failed to clean up temporary file: \(error)")
                    }
                } else {
                    Logger.shared.log("AlbumArtManager: No temporary album art file created by ffmpeg")
                    completion(nil)
                }
            }
        }
        
        // Check if ffmpeg exists, if not, skip this method
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") ||
              FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") else {
            Logger.shared.log("AlbumArtManager: ffmpeg not found in common locations")
            completion(nil)
            return
        }
        
        // Update ffmpeg path if using homebrew
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") {
            process.launchPath = "/opt/homebrew/bin/ffmpeg"
            Logger.shared.log("AlbumArtManager: Using Homebrew ffmpeg at /opt/homebrew/bin/ffmpeg")
        } else {
            Logger.shared.log("AlbumArtManager: Using system ffmpeg at /usr/local/bin/ffmpeg")
        }
        
        Logger.shared.log("AlbumArtManager: Executing ffmpeg to extract album art")
        do {
            try process.run()
        } catch {
            Logger.shared.log("AlbumArtManager: Failed to launch ffmpeg: \(error)")
            completion(nil)
        }
    }
    
    private func findLocalCoverArt(fileURI: String, completion: @escaping (NSImage?) -> Void) {
        guard let musicDir = musicDirectory else {
            Logger.shared.log("AlbumArtManager: No music directory configured for local cover art search")
            completion(nil)
            return
        }
        
        // Get the directory containing the music file
        let fullPath = URL(fileURLWithPath: musicDir).appendingPathComponent(fileURI).path
        let directoryPath = URL(fileURLWithPath: fullPath).deletingLastPathComponent()
        Logger.shared.log("AlbumArtManager: Searching for local cover art in: \(directoryPath.path)")
        
        // Common cover art filenames
        let coverFilenames = [
            "cover.jpg", "cover.jpeg", "cover.png", "cover.webp",
            "folder.jpg", "folder.jpeg", "folder.png",
            "albumart.jpg", "albumart.jpeg", "albumart.png",
            "front.jpg", "front.jpeg", "front.png"
        ]
        
        for filename in coverFilenames {
            let coverPath = directoryPath.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: coverPath) {
                Logger.shared.log("AlbumArtManager: Found potential cover art: \(coverPath)")
                if let image = NSImage(contentsOfFile: coverPath) {
                    Logger.shared.log("AlbumArtManager: Successfully loaded cover art: \(filename)")
                    completion(image)
                    return
                } else {
                    Logger.shared.log("AlbumArtManager: Failed to load image from: \(filename)")
                }
            }
        }
        
        Logger.shared.log("AlbumArtManager: No local cover art files found")
        completion(nil)
    }
    
    public func setMusicDirectory(_ path: String) {
        musicDirectory = path
        clearCache() // Clear cache when music directory changes
    }
    
    private func fetchOnlineAlbumArt(for song: MPDClient.Song, completion: @escaping (NSImage?) -> Void) {
        // Check if we have network connectivity
        guard isNetworkAvailable() else {
            Logger.shared.log("AlbumArtManager: No network connectivity available")
            completion(nil)
            return
        }
        
        // Build search query from song metadata
        guard let artist = song.artist, let album = song.album else {
            Logger.shared.log("AlbumArtManager: Missing artist or album metadata for online search")
            completion(nil)
            return
        }
        
        // URL encode the search query
        let query = "artist:\"\(artist)\" album:\"\(album)\""
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            Logger.shared.log("AlbumArtManager: Failed to encode search query")
            completion(nil)
            return
        }
        
        let urlString = "https://api.deezer.com/search/album?q=\(encodedQuery)&limit=1"
        guard let url = URL(string: urlString) else {
            Logger.shared.log("AlbumArtManager: Invalid Deezer API URL")
            completion(nil)
            return
        }
        
        Logger.shared.log("AlbumArtManager: Searching Deezer API: \(urlString)")
        
        // Make the API request
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                Logger.shared.log("AlbumArtManager: Deezer API request failed: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                Logger.shared.log("AlbumArtManager: No data received from Deezer API")
                completion(nil)
                return
            }
            
            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let albums = json["data"] as? [[String: Any]],
                   let firstAlbum = albums.first,
                   let coverURL = firstAlbum["cover_xl"] as? String {
                    
                    Logger.shared.log("AlbumArtManager: Found album art URL: \(coverURL)")
                    
                    // Download the image
                    Task { @MainActor in
                        self.downloadImage(from: coverURL, completion: completion)
                    }
                } else {
                    Logger.shared.log("AlbumArtManager: No album art found in Deezer API response")
                    completion(nil)
                }
            } catch {
                Logger.shared.log("AlbumArtManager: Failed to parse Deezer API response: \(error)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    private func downloadImage(from urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                Logger.shared.log("AlbumArtManager: Image download failed: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data, let image = NSImage(data: data) else {
                Logger.shared.log("AlbumArtManager: Failed to create image from downloaded data")
                completion(nil)
                return
            }
            
            Logger.shared.log("AlbumArtManager: Successfully downloaded album art image")
            DispatchQueue.main.async {
                completion(image)
            }
        }
        
        task.resume()
    }
    
    private func isNetworkAvailable() -> Bool {
        // Simple network availability check
        // In a production app, you might want to use Network framework for more sophisticated checking
        return true // For now, assume network is available
    }
    
    public func clearCache() {
        artworkCache.removeAll()
        fileToAlbumCache.removeAll()
        currentlyFetching.removeAll()
        clearDiskCache()
    }
    
    // MARK: - Disk Cache Methods
    
    private func diskCacheFileName(for albumKey: String) -> String {
        // Create a safe filename from the album key
        return albumKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .appending(".jpg")
    }
    
    private func saveToDiskCache(image: NSImage, albumKey: String) {
        let cacheFileName = diskCacheFileName(for: albumKey)
        let cacheURL = diskCacheDirectory.appendingPathComponent(cacheFileName)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            Logger.shared.log("AlbumArtManager: Failed to convert image to JPEG for disk cache")
            return
        }
        
        do {
            try jpegData.write(to: cacheURL)
            Logger.shared.log("AlbumArtManager: Saved image to disk cache: \(cacheFileName)")
        } catch {
            Logger.shared.log("AlbumArtManager: Failed to save image to disk cache: \(error)")
        }
    }
    
    private func loadFromDiskCache(albumKey: String) -> NSImage? {
        let cacheFileName = diskCacheFileName(for: albumKey)
        let cacheURL = diskCacheDirectory.appendingPathComponent(cacheFileName)
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        
        // Check if cache file is older than 30 days
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let daysSinceModification = Date().timeIntervalSince(modificationDate) / (24 * 60 * 60)
                if daysSinceModification > 30 {
                    Logger.shared.log("AlbumArtManager: Disk cache file expired, removing: \(cacheFileName)")
                    try FileManager.default.removeItem(at: cacheURL)
                    return nil
                }
            }
        } catch {
            Logger.shared.log("AlbumArtManager: Failed to check cache file attributes: \(error)")
        }
        
        return NSImage(contentsOf: cacheURL)
    }
    
    private func clearDiskCache() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
            Logger.shared.log("AlbumArtManager: Disk cache cleared")
        } catch {
            Logger.shared.log("AlbumArtManager: Failed to clear disk cache: \(error)")
        }
    }
}