import Foundation
import MLXLMCommon

extension InferenceEngine {
    /// Run a non-streaming chat completion and collect the full result.
    func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let input = try await prepareInput(for: request)
        let parameters = ChatMapping.resolveGenerateParameters(request)

        var text = ""
        var toolCalls: [ToolCallObject] = []
        var info: GenerateCompletionInfo?

        do {
            let stream = try await container.generate(input: input, parameters: parameters)
            for await generation in stream {
                switch generation {
                case .chunk(let chunk):
                    text += chunk
                case .toolCall(let call):
                    toolCalls.append(Self.toolCallObject(call, index: toolCalls.count))
                case .info(let completionInfo):
                    info = completionInfo
                }
            }
        } catch {
            throw ServerError.inferenceFailed(String(describing: error))
        }

        let hasToolCalls = !toolCalls.isEmpty
        let message = ChatCompletionResponse.ResponseMessage(
            content: hasToolCalls ? (text.isEmpty ? nil : text) : text,
            toolCalls: hasToolCalls ? toolCalls : nil
        )
        return ChatCompletionResponse(
            id: Self.completionID(),
            created: Self.unixNow(),
            model: modelID,
            choices: [
                .init(
                    index: 0,
                    message: message,
                    finishReason: hasToolCalls ? "tool_calls" : "stop"
                )
            ],
            usage: Usage(
                promptTokens: info?.promptTokenCount ?? 0,
                completionTokens: info?.generationTokenCount ?? 0
            )
        )
    }

    /// Build the prepared model input (chat template applied, tools injected)
    /// from an OpenAI request.
    func prepareInput(for request: ChatCompletionRequest) async throws -> sending LMInput {
        let messages = ChatMapping.toChatMessages(request.messages)
        let tools = ChatMapping.toToolSpecs(request.tools)
        do {
            return try await container.prepare(input: UserInput(chat: messages, tools: tools))
        } catch {
            throw ServerError.inferenceFailed(String(describing: error))
        }
    }

    /// Translate an mlx-swift-lm `ToolCall` into the OpenAI `tool_calls` shape.
    static func toolCallObject(_ call: MLXLMCommon.ToolCall, index: Int) -> ToolCallObject {
        ToolCallObject(
            id: "call_" + UUID().uuidString,
            function: FunctionCall(
                name: call.function.name,
                arguments: ChatMapping.argumentsJSONString(call.function.arguments)
            ),
            index: index
        )
    }

    static func completionID() -> String {
        "chatcmpl-" + UUID().uuidString
    }

    static func unixNow() -> Int {
        Int(Date().timeIntervalSince1970)
    }
}

/// Semantic events emitted by a streaming completion, before OpenAI framing.
enum StreamEvent: Sendable {
    case textDelta(String)
    case toolCall(ToolCallObject)
    case finished(reason: String, usage: Usage)
}

extension InferenceEngine {
    /// Run a streaming chat completion, yielding ``StreamEvent``s as tokens
    /// and tool calls arrive. `nonisolated` so the stream object is returned
    /// synchronously; the backing `Task` hops onto the actor to generate.
    nonisolated func stream(
        _ request: ChatCompletionRequest
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generateStream(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generateStream(
        _ request: ChatCompletionRequest,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let input = try await prepareInput(for: request)
        let parameters = ChatMapping.resolveGenerateParameters(request)

        var toolCallCount = 0
        var info: GenerateCompletionInfo?
        do {
            let generations = try await container.generate(input: input, parameters: parameters)
            for await generation in generations {
                switch generation {
                case .chunk(let chunk):
                    continuation.yield(.textDelta(chunk))
                case .toolCall(let call):
                    continuation.yield(.toolCall(Self.toolCallObject(call, index: toolCallCount)))
                    toolCallCount += 1
                case .info(let completionInfo):
                    info = completionInfo
                }
            }
        } catch {
            throw ServerError.inferenceFailed(String(describing: error))
        }

        continuation.yield(
            .finished(
                reason: toolCallCount > 0 ? "tool_calls" : "stop",
                usage: Usage(
                    promptTokens: info?.promptTokenCount ?? 0,
                    completionTokens: info?.generationTokenCount ?? 0)))
    }
}
