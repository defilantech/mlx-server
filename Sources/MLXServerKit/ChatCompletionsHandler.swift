import Foundation
import HTTPTypes
import Hummingbird

/// Handles `POST /v1/chat/completions` — streaming and non-streaming.
enum ChatCompletionsHandler {
    static func handle(
        request: Request,
        context: BasicRequestContext,
        engine: some Inferencing
    ) async throws -> Response {
        let completionRequest: ChatCompletionRequest
        do {
            completionRequest = try await request.decode(
                as: ChatCompletionRequest.self, context: context)
        } catch {
            return errorResponse(
                .badRequest("Malformed request body: \(error)"), status: .badRequest)
        }

        guard !completionRequest.messages.isEmpty else {
            return errorResponse(.badRequest("`messages` must not be empty"), status: .badRequest)
        }
        if let n = completionRequest.n, n != 1 {
            return errorResponse(.unsupportedParameter("`n` must be 1"), status: .badRequest)
        }

        if completionRequest.stream == true {
            return streamingResponse(completionRequest, engine: engine)
        }

        do {
            let completion = try await engine.complete(completionRequest)
            return try jsonResponse(completion)
        } catch let error as ServerError {
            return errorResponse(error, status: .internalServerError)
        } catch {
            return errorResponse(
                .inferenceFailed(String(describing: error)), status: .internalServerError)
        }
    }

    // MARK: Streaming

    /// Build a `text/event-stream` response that relays the engine's events
    /// as OpenAI `chat.completion.chunk` SSE frames.
    private static func streamingResponse(
        _ request: ChatCompletionRequest,
        engine: some Inferencing
    ) -> Response {
        let id = InferenceEngine.completionID()
        let created = InferenceEngine.unixNow()
        let model = request.model
        let events = engine.stream(request)

        let body = ResponseBody { writer in
            var roleSent = false
            do {
                for try await event in events {
                    switch event {
                    case .textDelta(let text):
                        let delta = ChatCompletionChunk.Delta(
                            role: roleSent ? nil : "assistant", content: text, toolCalls: nil)
                        roleSent = true
                        try await writer.write(
                            SSE.event(chunk(id, created, model, delta, finishReason: nil)))
                    case .reasoningDelta(let text):
                        let delta = ChatCompletionChunk.Delta(
                            role: roleSent ? nil : "assistant", content: nil,
                            reasoningContent: text, toolCalls: nil)
                        roleSent = true
                        try await writer.write(
                            SSE.event(chunk(id, created, model, delta, finishReason: nil)))
                    case .toolCall(let call):
                        let delta = ChatCompletionChunk.Delta(
                            role: roleSent ? nil : "assistant", content: nil, toolCalls: [call])
                        roleSent = true
                        try await writer.write(
                            SSE.event(chunk(id, created, model, delta, finishReason: nil)))
                    case .finished(let reason, _):
                        let delta = ChatCompletionChunk.Delta(
                            role: nil, content: nil, toolCalls: nil)
                        try await writer.write(
                            SSE.event(chunk(id, created, model, delta, finishReason: reason)))
                    }
                }
                try await writer.write(SSE.done())
            } catch {
                // Headers are already sent; surface the failure as a final
                // SSE frame on a best-effort basis.
                if let buffer = try? SSE.event(
                    OpenAIErrorResponse(
                        message: String(describing: error), type: "server_error"))
                {
                    try? await writer.write(buffer)
                }
            }
            try await writer.finish(nil)
        }

        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: body)
    }

    private static func chunk(
        _ id: String,
        _ created: Int,
        _ model: String,
        _ delta: ChatCompletionChunk.Delta,
        finishReason: String?
    ) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id,
            created: created,
            model: model,
            choices: [.init(index: 0, delta: delta, finishReason: finishReason)])
    }

    // MARK: Response helpers

    /// Encode an `Encodable` value as an `application/json` response.
    static func jsonResponse(
        _ value: some Encodable,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        var buffer = ByteBuffer()
        buffer.writeBytes(try JSONEncoder().encode(value))
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buffer))
    }

    /// Build an OpenAI-style error response.
    static func errorResponse(_ error: ServerError, status: HTTPResponse.Status) -> Response {
        var buffer = ByteBuffer()
        buffer.writeBytes((try? JSONEncoder().encode(OpenAIErrorResponse(error))) ?? Data())
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buffer))
    }
}
