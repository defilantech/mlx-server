import ArgumentParser
import Foundation
import Hummingbird
import Logging

@main
struct MLXServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mlx-server",
        abstract: "OpenAI-compatible HTTP server for mlx-swift-lm on Apple Silicon."
    )

    @Option(name: .long, help: "Model identifier (HuggingFace ID or local path). Not yet wired up.")
    var model: String?

    @Option(name: .long, help: "Bind address.")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Bind port.")
    var port: Int = 8080

    @Option(name: .long, help: "Maximum concurrent inference slots.")
    var maxSlots: Int = 4

    func run() async throws {
        let logger = Logger(label: "mlx-server")
        logger.info("mlx-server starting", metadata: [
            "host": .string(host),
            "port": .stringConvertible(port),
            "max_slots": .stringConvertible(maxSlots),
            "model": .string(model ?? "<unset>"),
        ])

        let router = Router()

        // Phase 0: smoke-test endpoint. Real OpenAI handlers land in Phase 1.
        router.get("/health") { _, _ -> String in
            "ok"
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port),
                serverName: "mlx-server"
            ),
            logger: logger
        )

        try await app.runService()
    }
}
