#!/bin/bash

set -e

echo "MPD Controls Uninstaller"
echo "========================"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This uninstaller is for macOS only."
    exit 1
fi

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.mpdcontrols.agent.plist"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# Unload the LaunchAgent if it exists
if [ -f "$PLIST_PATH" ]; then
    echo "Unloading LaunchAgent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    
    echo "Removing LaunchAgent plist..."
    rm -f "$PLIST_PATH"
fi

# Remove the binary
if [ -f "/usr/local/bin/MPDControls" ]; then
    echo "Removing MPDControls binary..."
    sudo rm -f /usr/local/bin/MPDControls
fi

# Clean up log files
echo "Cleaning up log files..."
rm -f /tmp/mpdcontrols.out /tmp/mpdcontrols.err

echo ""
echo "✅ Uninstallation complete!"
echo ""
echo "MPD Controls has been completely removed from your system."