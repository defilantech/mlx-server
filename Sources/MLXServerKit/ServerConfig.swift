import Foundation

/// Immutable server configuration assembled from CLI options by the
/// `MLXServer` executable and handed to ``run(config:)``.
public struct ServerConfig: Sendable {
    /// HuggingFace model id or a local model directory path.
    public var model: String
    /// Bind address.
    public var host: String
    /// Bind port.
    public var port: Int
    /// Maximum concurrent inference slots. Phase 1 serves single-slot;
    /// this is carried through for the Phase 2 slot pool.
    public var maxSlots: Int
    /// Optional tool-call format override (e.g. `xml_function`, `json`).
    /// When `nil` the format is inferred from the model's `config.json`.
    public var toolCallFormat: String?

    public init(
        model: String,
        host: String,
        port: Int,
        maxSlots: Int,
        toolCallFormat: String? = nil
    ) {
        self.model = model
        self.host = host
        self.port = port
        self.maxSlots = maxSlots
        self.toolCallFormat = toolCallFormat
    }
}
