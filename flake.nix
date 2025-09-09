{
  description = "Mac MPD Controls - Swift development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        isDarwin = pkgs.stdenv.isDarwin;
        isLinux = pkgs.stdenv.isLinux;
        
        # Use the latest Swift version available in nixpkgs
        swiftPackage = pkgs.swift;
        swiftpmPackage = pkgs.swiftPackages.swiftpm;
        
        darwinPackages = if isDarwin then with pkgs; [
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Cocoa
          darwin.apple_sdk.frameworks.CoreGraphics
          darwin.apple_sdk.frameworks.CoreServices
          darwin.apple_sdk.frameworks.IOKit
          darwin.apple_sdk.frameworks.Carbon
          darwin.apple_sdk.frameworks.Network
        ] else [];
        
        linuxPackages = if isLinux then with pkgs; [
          # For building and testing on Linux
          gnustep-base
          gnustep-gui
        ] else [];
        
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            swiftPackage
            swiftpmPackage
            swiftPackages.Foundation
            git
            gnumake
            pkg-config
            tokei
          ] ++ darwinPackages ++ linuxPackages;
          
          LD_LIBRARY_PATH = if isLinux then
            "${pkgs.swiftPackages.Dispatch}/lib:${pkgs.swiftPackages.Foundation}/lib"
          else "";
          
          shellHook = ''
            echo "Swift MPD Controls Development Environment"
            if command -v swift &> /dev/null; then
              echo "Swift version: $(swift --version | head -n 1)"
            else
              echo "Swift not available"
            fi
            echo ""
            echo "Available commands:"
            echo "  make build      - Build the project"
            echo "  make test       - Run tests"
            echo "  make run        - Run the application"
            echo "  make commit     - Commit and push changes"
            echo ""
          '';
        };
      });
}
