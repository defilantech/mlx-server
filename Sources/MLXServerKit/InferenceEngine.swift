import Foundation
import HuggingFace
import Logging
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Owns the loaded model and serializes inference through actor isolation.
///
/// Phase 1 serves a single slot: actor isolation guarantees exactly one
/// generation runs at a time. The Phase 2 multi-slot pool replaces the single
/// `container` here without changing the public method shapes.
public actor InferenceEngine {
    let container: ModelContainer
    /// Model id reported by `/v1/models` and accepted in request `model` fields.
    public let modelID: String
    /// Resolved tool-call format, or `nil` to let the model config decide.
    let toolCallFormat: ToolCallFormat?
    let logger: Logger

    private init(
        container: ModelContainer,
        modelID: String,
        toolCallFormat: ToolCallFormat?,
        logger: Logger
    ) {
        self.container = container
        self.modelID = modelID
        self.toolCallFormat = toolCallFormat
        self.logger = logger
    }

    /// Load the model named by `config.model` — a local directory path or a
    /// HuggingFace id. Blocks until weights are resident; throws
    /// ``ServerError/modelLoadFailed(_:)`` so the process never comes up
    /// half-ready.
    public static func load(config: ServerConfig, logger: Logger) async throws -> InferenceEngine {
        let format = resolveToolCallFormat(config.toolCallFormat, logger: logger)
        let configuration = modelConfiguration(for: config.model, toolCallFormat: format)
        let fromDirectory = directoryExists(config.model)

        logger.info(
            "loading model",
            metadata: [
                "model": .string(config.model),
                "source": .string(fromDirectory ? "local-directory" : "huggingface-id"),
                "tool_call_format": .string(format?.rawValue ?? "auto"),
            ])

        let started = ContinuousClock.now
        let container: ModelContainer
        do {
            container = try await #huggingFaceLoadModelContainer(configuration: configuration)
        } catch {
            throw ServerError.modelLoadFailed(String(describing: error))
        }
        logger.info(
            "model loaded",
            metadata: ["elapsed": .stringConvertible(started.duration(to: .now))])

        return InferenceEngine(
            container: container,
            modelID: config.model,
            toolCallFormat: format,
            logger: logger)
    }

    /// Build a ``ModelConfiguration`` from a local directory or a hub id.
    private static func modelConfiguration(
        for model: String,
        toolCallFormat: ToolCallFormat?
    ) -> ModelConfiguration {
        if directoryExists(model) {
            return ModelConfiguration(
                directory: URL(fileURLWithPath: model, isDirectory: true),
                toolCallFormat: toolCallFormat)
        }
        return ModelConfiguration(id: model, toolCallFormat: toolCallFormat)
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func resolveToolCallFormat(
        _ raw: String?,
        logger: Logger
    ) -> ToolCallFormat? {
        guard let raw else { return nil }
        guard let format = ToolCallFormat(rawValue: raw) else {
            logger.warning(
                "unknown --tool-call-format; inferring from the model instead",
                metadata: ["value": .string(raw)])
            return nil
        }
        return format
    }
}
