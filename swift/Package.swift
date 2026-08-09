// swift-tools-version: 5.9
// Author: geethudino (Ruthvik)
import PackageDescription

let package = Package(
    name: "Ytapis",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "Ytapis",
            targets: ["Ytapis"]
        ),
        .executable(
            name: "ytapis-cli",
            targets: ["ytapis-cli"]
        )
    ],
    targets: [
        .target(
            name: "Ytapis",
            path: "Sources/Ytapis",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "ytapis-cli",
            dependencies: ["Ytapis"],
            path: "Sources/ytapis-cli"
        )
    ]
)
