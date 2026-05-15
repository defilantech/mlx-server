import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import MLXServerKit

/// In-memory ``Inferencing`` implementation for exercising routes without a model.
struct StubEngine: Inferencing {
    var modelID: String = "stub-model"
    var cannedText: String = "hello"
    var cannedToolCall: ToolCallObject?

    func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let hasTool = cannedToolCall != nil
        return ChatCompletionResponse(
            id: "chatcmpl-stub",
            created: 0,
            model: request.model,
            choices: [
                .init(
                    index: 0,
                    message: .init(
                        content: hasTool ? nil : cannedText,
                        toolCalls: cannedToolCall.map { [$0] }),
                    finishReason: hasTool ? "tool_calls" : "stop")
            ],
            usage: Usage(promptTokens: 1, completionTokens: 1))
    }

    func stream(_ request: ChatCompletionRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let text = cannedText
        let tool = cannedToolCall
        return AsyncThrowingStream { continuation in
            if let tool {
                continuation.yield(.toolCall(tool))
            } else {
                continuation.yield(.textDelta(text))
            }
            continuation.yield(
                .finished(
                    reason: tool != nil ? "tool_calls" : "stop",
                    usage: Usage(promptTokens: 1, completionTokens: 1)))
            continuation.finish()
        }
    }
}

@Suite("Routes")
struct RoutesTests {
    private func makeApp(engine: some Inferencing) -> some ApplicationProtocol {
        let router = Router()
        registerRoutes(router: router, engine: engine)
        return Application(router: router)
    }

    private let jsonHeaders: HTTPFields = [.contentType: "application/json"]

    @Test("GET /v1/models lists the loaded model")
    func models() async throws {
        let app = makeApp(engine: StubEngine(modelID: "my-model"))
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/v1/models", method: .get)
            #expect(response.status == .ok)
            let body = String(buffer: response.body)
            #expect(body.contains("\"my-model\""))
            #expect(body.contains("\"object\":\"list\""))
        }
    }

    @Test("non-streaming chat completion returns a chat.completion")
    func nonStreaming() async throws {
        let app = makeApp(engine: StubEngine(modelID: "m", cannedText: "pong"))
        try await app.test(.router) { client in
            let body = ByteBuffer(
                string: #"{"model":"m","messages":[{"role":"user","content":"ping"}]}"#)
            let response = try await client.execute(
                uri: "/v1/chat/completions", method: .post, headers: jsonHeaders, body: body)
            #expect(response.status == .ok)
            let text = String(buffer: response.body)
            #expect(text.contains("\"object\":\"chat.completion\""))
            #expect(text.contains("pong"))
            #expect(text.contains("\"finish_reason\":\"stop\""))
        }
    }

    @Test("streaming chat completion emits SSE frames terminated by [DONE]")
    func streaming() async throws {
        let app = makeApp(engine: StubEngine(modelID: "m", cannedText: "streamed"))
        try await app.test(.router) { client in
            let body = ByteBuffer(
                string: #"{"model":"m","stream":true,"messages":[{"role":"user","content":"go"}]}"#)
            let response = try await client.execute(
                uri: "/v1/chat/completions", method: .post, headers: jsonHeaders, body: body)
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            let text = String(buffer: response.body)
            #expect(text.contains("chat.completion.chunk"))
            #expect(text.contains("data: [DONE]"))
            // The stream must carry a trailing usage chunk for context %.
            #expect(text.contains("\"prompt_tokens\""))
        }
    }

    @Test("tool-call result reports finish_reason tool_calls")
    func toolCalls() async throws {
        let toolCall = ToolCallObject(
            id: "call_1",
            function: FunctionCall(name: "get_weather", arguments: #"{"city":"Paris"}"#),
            index: 0)
        let app = makeApp(engine: StubEngine(modelID: "m", cannedToolCall: toolCall))
        try await app.test(.router) { client in
            let body = ByteBuffer(
                string: #"{"model":"m","messages":[{"role":"user","content":"weather?"}]}"#)
            let response = try await client.execute(
                uri: "/v1/chat/completions", method: .post, headers: jsonHeaders, body: body)
            let text = String(buffer: response.body)
            #expect(text.contains("\"finish_reason\":\"tool_calls\""))
            #expect(text.contains("get_weather"))
        }
    }

    @Test("empty messages array is rejected with 400")
    func emptyMessages() async throws {
        let app = makeApp(engine: StubEngine())
        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"model":"m","messages":[]}"#)
            let response = try await client.execute(
                uri: "/v1/chat/completions", method: .post, headers: jsonHeaders, body: body)
            #expect(response.status == .badRequest)
        }
    }
}
