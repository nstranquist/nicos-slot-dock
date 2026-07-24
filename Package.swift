// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlotDock",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlotDockCore", targets: ["SlotDockCore"]),
        .executable(name: "SlotDock", targets: ["SlotDock"]),
    ],
    targets: [
        .target(
            name: "SlotDockCore",
            path: "Sources/SlotDockCore"
        ),
        .executableTarget(
            name: "SlotDock",
            dependencies: ["SlotDockCore"],
            path: "Sources/SlotDock"
        ),
        .testTarget(
            name: "SlotDockCoreTests",
            dependencies: ["SlotDockCore"],
            path: "Tests/SlotDockCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
