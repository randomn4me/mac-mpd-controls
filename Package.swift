// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(macOS)
let macOSTargets: [Target] = [
    .executableTarget(
        name: "MPDControls",
        dependencies: ["MPDControlsCore"]
    )
]
let macOSProducts: [Product] = [
    .executable(
        name: "MPDControls",
        targets: ["MPDControls"]
    )
]
#else
let macOSTargets: [Target] = []
let macOSProducts: [Product] = []
#endif

let package = Package(
    name: "mac-mpd-controls",
    platforms: [
        .macOS(.v13)
    ],
    products: macOSProducts + [
        .executable(
            name: "MPDControlsCLI",
            targets: ["MPDControlsCLI"]
        ),
        .library(
            name: "MPDControlsCore",
            targets: ["MPDControlsCore"]
        )
    ],
    targets: macOSTargets + [
        .target(
            name: "MPDControlsCore",
            dependencies: [],
            path: "Sources/MPDControlsCore"
        ),
        .executableTarget(
            name: "MPDControlsCLI",
            dependencies: ["MPDControlsCore"]
        ),
        .testTarget(
            name: "MPDControlsTests",
            dependencies: ["MPDControlsCore"]
        )
    ]
)
