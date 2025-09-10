{
  description = "Mac MPD Controls - Swift development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Helper function to create a Swift app
        mkSwiftApp = { name, command, description ? "" }: pkgs.writeShellScriptBin name ''
          # Ensure we're in the project directory
          PROJECT_DIR="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || pwd)"
          cd "$PROJECT_DIR"
          
          ${command}
        '';
        
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Build tools
            git
            gnumake
            pkg-config
            
            # Development tools
            tokei
            jq
            ripgrep
            fd
          ];
          
          shellHook = ''
            echo "Swift MPD Controls Development Environment"
            if command -v swift &> /dev/null; then
              echo "Swift version: $(swift --version | head -n 1)"
            else
              echo "Note: Using system Swift installation"
            fi
            echo ""
            echo "Available commands:"
            echo "  make build      - Build the project"
            echo "  make test       - Run tests"
            echo "  make run        - Run the application"
            echo "  make commit     - Commit and push changes"
            echo ""
            echo "Nix apps:"
            echo "  nix run         - Run MPDControls"
            echo "  nix run .#test  - Run tests"
            echo "  nix run .#dev   - Run in debug mode"
            echo ""
          '';
        };
        
        # Applications
        apps = {
          # Default app - run MPDControls
          default = {
            type = "app";
            program = "${mkSwiftApp {
              name = "mpdcontrols";
              command = ''
                swift build -c release
                ./.build/release/MPDControls "$@"
              '';
              description = "Mac MPD Controls - Control MPD from macOS";
            }}/bin/mpdcontrols";
          };
          
          # Test runner
          test = {
            type = "app";
            program = "${mkSwiftApp {
              name = "mpdcontrols-test";
              command = ''
                echo "Building and running tests..."
                swift build --product MPDControlsTests
                ./.build/debug/MPDControlsTests "$@"
              '';
              description = "Run MPDControls tests";
            }}/bin/mpdcontrols-test";
          };
          
          # Development build
          dev = {
            type = "app";
            program = "${mkSwiftApp {
              name = "mpdcontrols-dev";
              command = ''
                swift build
                ./.build/debug/MPDControls "$@"
              '';
              description = "Run MPDControls in debug mode";
            }}/bin/mpdcontrols-dev";
          };
        };
        
        # Packages (for building with nix build)
        packages = {
          default = mkSwiftApp {
            name = "mpdcontrols";
            command = ''
              swift build -c release
              ./.build/release/MPDControls "$@"
            '';
            description = "Mac MPD Controls - Control MPD from macOS";
          };
          
          # Installable package that builds and installs the binary
          mpdcontrols = pkgs.stdenv.mkDerivation {
            pname = "mpdcontrols";
            version = "1.0.0";
            
            src = ./.;
            
            buildInputs = [ pkgs.swift ];
            
            buildPhase = ''
              swift build -c release --product MPDControls
            '';
            
            installPhase = ''
              mkdir -p $out/bin
              cp .build/release/MPDControls $out/bin/mpdcontrols
            '';
            
            meta = with pkgs.lib; {
              description = "Mac MPD Controls - Control MPD from macOS with media keys";
              homepage = "https://github.com/pkuehn/mac-mpd-controls";
              license = licenses.mit;
              platforms = platforms.darwin;
              mainProgram = "mpdcontrols";
            };
          };
          
          test = mkSwiftApp {
            name = "mpdcontrols-test";
            command = ''
              echo "Building and running tests..."
              swift build --product MPDControlsTests
              ./.build/debug/MPDControlsTests "$@"
            '';
            description = "Run MPDControls tests";
          };
          
          dev = mkSwiftApp {
            name = "mpdcontrols-dev";
            command = ''
              swift build
              ./.build/debug/MPDControls "$@"
            '';
            description = "Run MPDControls in debug mode";
          };
        };
      });
}