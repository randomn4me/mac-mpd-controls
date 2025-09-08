# Mac MPD Controls

A unified Swift application that combines MPD (Music Player Daemon) control functionality with macOS system integration, providing both menu bar UI and media key support.

## Features

### Core Functionality
- **Menu Bar Interface**: Quick access to MPD controls from the macOS menu bar
- **Media Key Support**: Control MPD using keyboard media keys (Play/Pause, Next, Previous)
- **Network Communication**: Direct TCP connection to MPD server without external dependencies
- **Auto-Reconnection**: Automatic reconnection with exponential backoff
- **Real-time Updates**: Configurable polling interval for status updates
- **Cross-Platform Core**: Modular design with platform-specific UI and shared core logic

### Playback Features
- **Volume Control**: Integrated volume slider with visual feedback
- **Crossfade Control**: Adjust crossfade duration between tracks
- **Playback Options**: Toggle random, repeat, single, and consume modes
- **Queue Management**: Add, remove, move, and swap items in the play queue
- **Playlist Management**: Load, save, and delete playlists
- **Now Playing Display**: Shows current track information with artist, title, and album

### Advanced Features
- **Search Functionality**: Search by artist, album, title, or any field
- **Database Operations**: Update and rescan music database
- **Output Control**: Manage multiple audio outputs
- **Statistics**: View server statistics (songs, albums, uptime, etc.)
- **Idle Command Support**: Monitor MPD subsystem changes
- **Notifications**: macOS notifications for track changes
- **Settings Persistence**: Save connection and preference settings

## Architecture

The project is structured as a Swift Package with multiple targets:

- **MPDControlsCore**: Platform-agnostic MPD protocol implementation and types
- **MPDControls**: macOS-specific application with menu bar UI and media key handling
- **MPDControlsCLI**: Command-line interface for MPD control

## Development

### Prerequisites

- Nix package manager (for reproducible development environment)
- macOS 13+ (for the GUI application)
- MPD server running locally or on the network

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

### Project Structure

```
.
├── Sources/
│   ├── MPDControlsCore/     # Core MPD protocol and types
│   ├── MPDControls/          # macOS application
│   │   ├── Views/            # SwiftUI views for menu bar
│   │   ├── Network/          # Network connection handling
│   │   └── MediaKeyHandler.swift
│   └── MPDControlsCLI/       # Command-line interface
├── Tests/                    # Test suites
├── Package.swift             # Swift package configuration
└── flake.nix                 # Nix development environment
```

## Configuration

The application stores MPD server configuration in UserDefaults:
- Host: `mpd_host` (default: "127.0.0.1")
- Port: `mpd_port` (default: 6600)

These can be configured through the Settings interface in the menu bar application.

## Testing

The project includes comprehensive test coverage:
- Unit tests for MPD protocol parsing
- Integration tests for client functionality
- Cross-platform compatibility tests

## Origin

This project unifies functionality from two separate projects:
- **mac-mpd-control**: Media key handling and system integration (Objective-C)
- **mpd-menubar**: Menu bar UI and network communication (Swift)

The unified Swift implementation provides better maintainability and modern macOS integration.

## License

See LICENSE file for details.