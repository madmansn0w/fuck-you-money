// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CryptoTracker",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CryptoTrackerCore", targets: ["CryptoTrackerCore"]),
        .executable(name: "crypto-tracker-cli", targets: ["CryptoTrackerCLI"]),
    ],
    targets: [
        .target(
            name: "CryptoTrackerCore",
            path: "Sources/CryptoTrackerCore"
        ),
        .testTarget(
            name: "CryptoTrackerCoreTests",
            dependencies: ["CryptoTrackerCore"],
            path: "tests/CryptoTrackerCoreTests"
        ),
        .executableTarget(
            name: "CryptoTrackerCLI",
            dependencies: ["CryptoTrackerCore"],
            path: "Sources/CryptoTrackerCLI"
        ),
    ]
)
