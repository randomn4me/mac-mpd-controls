#!/bin/bash

echo "Building test executable..."
nix develop -c swift build --product MPDControlsCLI

echo "Running tests directly..."
nix develop -c swift run MPDControlsCLI test

echo "Tests completed!"