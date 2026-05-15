import Hummingbird
import Logging

/// Builds and runs the mlx-server HTTP service.
///
/// The inference engine is loaded *before* the socket binds, so the process
/// never accepts traffic in a half-ready state.
public func run(config: ServerConfig) async throws {
    let logger = Logger(label: "mlx-server")
    logger.info(
        "mlx-server starting",
        metadata: [
            "host": .string(config.host),
            "port": .stringConvertible(config.port),
            "max_slots": .stringConvertible(config.maxSlots),
            "model": .string(config.model),
        ])

    let engine = try await InferenceEngine.load(config: config, logger: logger)

    let router = Router()
    registerRoutes(router: router, engine: engine)

    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(config.host, port: config.port),
            serverName: "mlx-server"
        ),
        logger: logger
    )

    try await app.runService()
}
