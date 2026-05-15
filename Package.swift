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
        // MLX inference for Apple Silicon: LLMs/VLMs plus the chat-template
        // tool-call parsers. Consumed remotely from the v3.32.1-alpha tag.
        .package(url: "https://github.com/ekryski/mlx-swift-lm", exact: "3.32.1-alpha"),
        // HuggingFace hub client + tokenizers. Required by the MLXHuggingFace
        // macros that generate the model Downloader / TokenizerLoader.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    ],
    targets: [
        // Thin executable: CLI parsing only. All logic lives in MLXServerKit.
        .executableTarget(
            name: "MLXServer",
            dependencies: [
                "MLXServerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Library target: server, routing, inference engine, OpenAI types.
        // Separated from the executable so it is unit-testable.
        .target(
            name: "MLXServerKit",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ]
        ),
        // swift-testing (ships with the Swift 6 toolchain; needs a full Xcode).
        .testTarget(
            name: "MLXServerTests",
            dependencies: [
                "MLXServerKit",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
