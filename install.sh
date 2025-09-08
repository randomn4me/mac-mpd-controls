#!/bin/bash

set -e

echo "MPD Controls Installer"
echo "====================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This installer is for macOS only."
    exit 1
fi

# Build the project
echo "Building MPD Controls..."
if command -v nix &> /dev/null; then
    echo "Using Nix development shell..."
    nix develop -c swift build -c release --product MPDControls
else
    echo "Building with system Swift..."
    swift build -c release --product MPDControls
fi

# Install the binary
echo "Installing MPDControls to /usr/local/bin..."
sudo cp .build/release/MPDControls /usr/local/bin/
sudo chmod +x /usr/local/bin/MPDControls

# Install LaunchAgent
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.mpdcontrols.agent.plist"

echo "Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$PLIST_NAME" "$LAUNCH_AGENTS_DIR/"

# Load the LaunchAgent
echo "Loading LaunchAgent..."
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo "✅ Installation complete!"
echo ""
echo "MPD Controls is now installed and running."
echo "It will start automatically on login."
echo ""
echo "To uninstall, run: ./uninstall.sh"