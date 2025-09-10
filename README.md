# Mac MPD Controls

A lightweight command-line MPD (Music Player Daemon) client for macOS that provides media key support and system Now Playing integration with comprehensive album art management.

## Features

### Core Functionality
- **Media Key Support**: Control MPD using keyboard media keys (Play/Pause, Next, Previous)
- **System Now Playing Integration**: Display current track in macOS Now Playing center with album artwork
- **Auto-Reconnection**: Automatic reconnection to MPD server with exponential backoff
- **Real-time Updates**: Configurable polling interval for status updates
- **Network Communication**: Direct TCP connection to MPD server without external dependencies

### Album Art Management
- **Embedded Art Extraction**: Extract album art from audio files using ffmpeg
- **Local Art Search**: Find cover art files (cover.jpg, folder.jpg, artwork.jpg, etc.)
- **Online Art Fetching**: Fallback to Deezer API for missing artwork
- **Intelligent Caching**: XDG-compliant disk cache to prevent duplicate requests
- **Multiple Format Support**: Handles JPEG, PNG, and embedded artwork in various audio formats

### Additional Features
- **Desktop Notifications**: macOS notifications for track changes (optional)
- **Comprehensive Logging**: File-based and verbose logging options
- **Flexible Configuration**: Command-line arguments for all settings
- **Cross-Platform Core**: Modular design with platform-specific features and shared core logic

## Architecture

The project is structured as a Swift Package with multiple targets:

- **MPDControlsCore**: Platform-agnostic MPD protocol implementation and types
- **MPDControls**: macOS command-line application with media key handling and Now Playing integration
- **MPDControlsTests**: Comprehensive test suite including unit, integration, and end-to-end tests

## Installation

### macOS

For macOS users, use the provided installation script:

```bash
# Install MPD Controls with LaunchAgent for auto-start
./install.sh

# To uninstall
./uninstall.sh
```

The installer will:
- Build the application
- Install the binary to `/usr/local/bin/MPDControls`
- Set up a LaunchAgent for automatic startup on login
- Start the application immediately

### Manual Installation

```bash
# Build the release version
swift build -c release --product MPDControls

# Copy to your preferred location
cp .build/release/MPDControls /usr/local/bin/

# Run the application
/usr/local/bin/MPDControls
```

## Usage

```bash
MPDControls [OPTIONS]

OPTIONS:
    -h, --help                      Show help message
    -v, --verbose                   Enable verbose logging to stdout
    --host HOST                     MPD server host (default: 127.0.0.1)
    --port PORT                     MPD server port (default: 6600)
    --update-interval SECONDS       Update interval in seconds (default: 2.0)
    --no-notifications             Disable desktop notifications
    --no-auto-reconnect            Disable automatic reconnection
    --no-system-now-playing        Disable system Now Playing integration
    --music-directory PATH          Path to music directory for album art
    --log-file PATH                 Log to file instead of/in addition to stdout

EXAMPLES:
    # Connect to remote MPD server with verbose logging
    MPDControls --host 192.168.1.100 --port 6600 -v
    
    # Enable album art with local music directory
    MPDControls --music-directory ~/Music --log-file ~/.mpd-controls.log
    
    # Minimal setup with longer update interval
    MPDControls --no-notifications --update-interval 5.0
```

## Development

### Prerequisites

- Nix package manager (for reproducible development environment)
- macOS 13+ (for media key and Now Playing support)
- MPD server running locally or on the network
- ffmpeg (for album art extraction, optional)

### Building

Using the Nix flake development environment:

```bash
# Enter the development shell
nix develop

# Build the project
make build

# Run tests
make test

# Run the application
make run
```

Or use Nix apps directly:

```bash
# Run the application (release build)
nix run

# Run tests
nix run .#test

# Run development build
nix run .#dev
```

### Project Structure

```
.
├── Sources/
│   ├── MPDControlsCore/          # Core MPD protocol and types
│   │   ├── MPDProtocol.swift    # MPD protocol implementation
│   │   ├── MPDTypes.swift       # MPD data types
│   │   └── SimpleMPDClient.swift # Basic MPD client
│   └── MPDControls/              # macOS application
│       ├── MPDControlsApp.swift  # Main application and CLI parsing
│       ├── MPDClient.swift       # Enhanced MPD client
│       ├── MediaKeyHandler.swift # Media key event handling
│       ├── SystemNowPlayingManager.swift # Now Playing integration
│       ├── AlbumArtManager.swift # Album art extraction and caching
│       ├── NotificationManager.swift # Desktop notifications
│       └── Network/              # Network connection handling
├── Tests/                        # Test suites
├── Package.swift                 # Swift package configuration
└── flake.nix                    # Nix development environment
```

## Configuration

The application accepts configuration through command-line arguments. For persistent configuration, you can:

1. Create a shell alias:
```bash
alias mpd-controls='MPDControls --host 192.168.1.100 --music-directory ~/Music'
```

2. Use the LaunchAgent (installed via `install.sh`) which can be modified at:
```
~/Library/LaunchAgents/com.mpdcontrols.agent.plist
```

## Album Art Sources

The application searches for album art in the following order:

1. **Embedded artwork** in the audio file (requires ffmpeg)
2. **Local cover files** in the same directory as the audio file:
   - cover.jpg, cover.png
   - folder.jpg, folder.png
   - artwork.jpg, artwork.png
   - front.jpg, front.png
   - album.jpg, album.png
3. **Online sources** (Deezer API) based on artist and album metadata

Album art is cached in `~/.cache/MPDControls/AlbumArt/` following XDG Base Directory specifications.

## Testing

The project includes comprehensive test coverage:
- **Unit Tests**: MPD protocol parsing, command generation, types validation
- **Integration Tests**: Client functionality, connection management, error handling
- **End-to-End Tests**: Complete user workflows, playback scenarios
- **Network Tests**: Connection handling, reconnection logic

Run the test suite:
```bash
# Using Nix environment
nix run .#test

# Or directly with Swift
swift test
```

## Origin

This project unifies functionality from two separate projects:
- **[mac-mpd-control](https://github.com/zrnsm/mac-mpd-control)**: Media key handling and system integration (Objective-C)
- **[mpd-menubar](https://github.com/yoink00/mpd-menubar)**: Menu bar UI and network communication (Swift)

The unified Swift implementation provides better maintainability and modern macOS integration while preserving the core functionality of both original projects.

## License

See LICENSE file for details.