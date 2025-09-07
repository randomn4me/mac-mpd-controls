// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mac-mpd-controls",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MPDControls",
            targets: ["MPDControls"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MPDControls",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "MPDControlsTests",
            dependencies: ["MPDControls"]
        )
    ]
)
