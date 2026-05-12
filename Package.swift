// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "mlx-server",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "mlx-server", targets: ["MLXServer"]),
    ],
    dependencies: [
        // HTTP server framework. SwiftNIO-based, server-focused, low dep surface.
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0"),
        // CLI argument parsing.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // Structured logging.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        // Metrics API (Prometheus backend wired up in Phase 2).
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),

        // TODO(phase-1): add mlx-swift-lm once the upstream Package.swift either
        // exposes mlx-swift as a remote URL dependency or we adopt a workspace
        // / submodule strategy. mlx-swift-lm currently uses .package(path: "../mlx-swift")
        // which blocks remote consumption.
        //   https://github.com/ekryski/mlx-swift-lm/blob/alpha/Package.swift
    ],
    targets: [
        .executableTarget(
            name: "MLXServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]
        ),
        // TODO(phase-1): re-add test target once we have real handlers to test.
        // Will use swift-testing (built into Swift 6+) when targeting a full
        // Xcode toolchain. Command Line Tools-only installs do not ship the
        // Testing module.
    ]
)
