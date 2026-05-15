import ArgumentParser
import MLXServerKit

@main
struct MLXServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mlx-server",
        abstract: "OpenAI-compatible HTTP server for mlx-swift-lm on Apple Silicon."
    )

    @Option(name: .long, help: "Model identifier (HuggingFace ID or local directory path).")
    var model: String?

    @Option(name: .long, help: "Bind address.")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Bind port.")
    var port: Int = 8080

    @Option(name: .long, help: "Maximum concurrent inference slots.")
    var maxSlots: Int = 4

    @Option(name: .long, help: "Tool-call format override (e.g. xml_function, json). Auto-inferred when unset.")
    var toolCallFormat: String?

    @Option(name: .long, help: "Reasoning split mode: auto, prefilled, or off. Use 'prefilled' for Qwen3.5 / Qwen3.6.")
    var reasoning: String = "auto"

    func run() async throws {
        guard let model else {
            throw ValidationError("--model is required (HuggingFace ID or local directory path).")
        }
        guard let reasoningMode = ReasoningMode(rawValue: reasoning) else {
            throw ValidationError("--reasoning must be one of: auto, prefilled, off")
        }

        let config = ServerConfig(
            model: model,
            host: host,
            port: port,
            maxSlots: maxSlots,
            toolCallFormat: toolCallFormat,
            reasoningMode: reasoningMode
        )

        try await MLXServerKit.run(config: config)
    }
}
