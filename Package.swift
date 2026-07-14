// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "blik",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "BlikCore", targets: ["BlikCore"]),
        .library(name: "BlikShared", targets: ["BlikShared"]),
        .library(name: "BlikDesign", targets: ["BlikDesign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "BlikCore",
            path: "Sources/BlikCore",
            // Явная линковка системной libsqlite3 (SDK-модуль SQLite3) для
            // History/HistoryStore — не package-зависимость.
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "BlikXPC",
            dependencies: ["BlikCore"],
            path: "Sources/BlikXPC"
        ),
        .target(
            name: "BlikShared",
            dependencies: ["BlikCore", "BlikXPC"],
            path: "Sources/BlikShared"
        ),
        .target(
            name: "BlikDesign",
            path: "Sources/BlikDesign"
        ),
        .executableTarget(
            name: "BlikHelper",
            dependencies: ["BlikCore", "BlikXPC"],
            path: "Sources/BlikHelper"
        ),
        .executableTarget(
            name: "blik",
            dependencies: [
                "BlikCore",
                "BlikXPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/blik"
        ),
        .executableTarget(
            name: "BlikMenuBar",
            dependencies: ["BlikCore", "BlikXPC", "BlikShared", "BlikDesign"],
            path: "Sources/BlikMenuBar"
        ),
        .executableTarget(
            name: "BlikApp",
            dependencies: [
                "BlikCore", "BlikXPC", "BlikShared", "BlikDesign",
            ],
            path: "Sources/BlikApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BlikCoreTests",
            dependencies: ["BlikCore"],
            path: "Tests/BlikCoreTests"
        ),
        .testTarget(
            name: "BlikXPCTests",
            dependencies: ["BlikXPC", "BlikCore"],
            path: "Tests/BlikXPCTests"
        ),
        .testTarget(
            name: "blikTests",
            dependencies: ["blik"],
            path: "Tests/blikTests"
        ),
        .testTarget(
            name: "BlikSharedTests",
            dependencies: ["BlikShared", "BlikCore", "BlikXPC"],
            path: "Tests/BlikSharedTests"
        ),
    ]
)
