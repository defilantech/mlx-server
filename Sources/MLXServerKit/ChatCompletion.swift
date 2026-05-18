import Foundation
import MLXLMCommon

extension InferenceEngine {
    /// Run a non-streaming chat completion and collect the full result.
    func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let input = try await prepareInput(for: request)
        let parameters = ChatMapping.resolveGenerateParameters(request)

        var splitter = ReasoningSplitter(mode: reasoningMode)
        var content = ""
        var reasoning = ""
        var toolCalls: [ToolCallObject] = []
        var info: GenerateCompletionInfo?

        do {
            let stream = try await container.generate(input: input, parameters: parameters)
            for await generation in stream {
                switch generation {
                case .chunk(let chunk):
                    let split = splitter.push(chunk)
                    content += split.content
                    reasoning += split.reasoning
                case .toolCall(let call):
                    toolCalls.append(Self.toolCallObject(call, index: toolCalls.count))
                case .info(let completionInfo):
                    info = completionInfo
                }
            }
        } catch {
            throw ServerError.inferenceFailed(String(describing: error))
        }
        let tail = splitter.flush()
        content += tail.content
        reasoning += tail.reasoning

        let hasToolCalls = !toolCalls.isEmpty
        let message = ChatCompletionResponse.ResponseMessage(
            content: hasToolCalls && content.isEmpty ? nil : content,
            reasoningContent: reasoning.isEmpty ? nil : reasoning,
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
                    finishReason: Self.finishReason(
                        hasToolCalls: hasToolCalls,
                        generatedTokens: info?.generationTokenCount ?? 0,
                        maxTokens: parameters.maxTokens)
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

    /// OpenAI `finish_reason` for a completed generation: `length` when the
    /// output was truncated at the token limit, `tool_calls` when the model
    /// emitted tool calls, otherwise `stop`. Truncation is inferred by
    /// comparing the generated token count against the requested limit,
    /// since the generator does not surface a stop reason directly.
    static func finishReason(hasToolCalls: Bool, generatedTokens: Int, maxTokens: Int?) -> String {
        if hasToolCalls { return "tool_calls" }
        if let maxTokens, generatedTokens >= maxTokens { return "length" }
        return "stop"
    }
}

/// Semantic events emitted by a streaming completion, before OpenAI framing.
enum StreamEvent: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
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

        var splitter = ReasoningSplitter(mode: reasoningMode)
        var toolCallCount = 0
        var info: GenerateCompletionInfo?
        do {
            let generations = try await container.generate(input: input, parameters: parameters)
            for await generation in generations {
                switch generation {
                case .chunk(let chunk):
                    let split = splitter.push(chunk)
                    if !split.reasoning.isEmpty {
                        continuation.yield(.reasoningDelta(split.reasoning))
                    }
                    if !split.content.isEmpty {
                        continuation.yield(.textDelta(split.content))
                    }
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

        let tail = splitter.flush()
        if !tail.reasoning.isEmpty { continuation.yield(.reasoningDelta(tail.reasoning)) }
        if !tail.content.isEmpty { continuation.yield(.textDelta(tail.content)) }

        continuation.yield(
            .finished(
                reason: Self.finishReason(
                    hasToolCalls: toolCallCount > 0,
                    generatedTokens: info?.generationTokenCount ?? 0,
                    maxTokens: parameters.maxTokens),
                usage: Usage(
                    promptTokens: info?.promptTokenCount ?? 0,
                    completionTokens: info?.generationTokenCount ?? 0)))
    }
}
