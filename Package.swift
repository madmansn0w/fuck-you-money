// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FuckYouMoney",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "FuckYouMoneyCore", targets: ["FuckYouMoneyCore"]),
        .executable(name: "fuck-you-money-cli", targets: ["FuckYouMoneyCLI"]),
    ],
    targets: [
        .target(
            name: "FuckYouMoneyCore",
            path: "Sources/FuckYouMoneyCore"
        ),
        .testTarget(
            name: "FuckYouMoneyCoreTests",
            dependencies: ["FuckYouMoneyCore"],
            path: "tests/FuckYouMoneyCoreTests"
        ),
        .executableTarget(
            name: "FuckYouMoneyCLI",
            dependencies: ["FuckYouMoneyCore"],
            path: "Sources/FuckYouMoneyCLI"
        ),
    ]
)
