// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Numo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NumoCore", targets: ["NumoCore"]),
        .executable(name: "Numo", targets: ["Numo"]),
    ],
    targets: [
        // Pure calculation engine: lexer, parser, evaluator, formatting. No UI dependencies.
        .target(name: "NumoCore"),
        // macOS app (AppKit).
        .executableTarget(
            name: "Numo",
            dependencies: ["NumoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "NumoCoreTests", dependencies: ["NumoCore"]),
    ]
)
