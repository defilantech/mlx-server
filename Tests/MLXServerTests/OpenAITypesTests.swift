import Foundation
import Testing

@testable import MLXServerKit

@Suite("OpenAI types")
struct OpenAITypesTests {
    @Test("decodes a chat completion request with tools and streaming")
    func decodeRequest() throws {
        let json = """
        {
          "model": "qwen",
          "messages": [
            {"role": "system", "content": "be brief"},
            {"role": "user", "content": "hi"}
          ],
          "temperature": 0.7,
          "top_p": 0.9,
          "max_tokens": 256,
          "stream": true,
          "tool_choice": "auto",
          "tools": [
            {"type": "function", "function": {"name": "get_weather", "description": "w", "parameters": {"type": "object"}}}
          ]
        }
        """
        let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))

        #expect(request.model == "qwen")
        #expect(request.messages.count == 2)
        #expect(request.messages[1].content?.text == "hi")
        #expect(request.temperature == 0.7)
        #expect(request.topP == 0.9)
        #expect(request.maxTokens == 256)
        #expect(request.stream == true)
        #expect(request.tools?.count == 1)
        #expect(request.tools?.first?.function.name == "get_weather")
        guard case .auto = request.toolChoice else {
            Issue.record("expected tool_choice .auto")
            return
        }
    }

    @Test("decodes tool_choice in forced-function object form")
    func decodeForcedToolChoice() throws {
        let json = """
        {"model":"m","messages":[],"tool_choice":{"type":"function","function":{"name":"f"}}}
        """
        let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
        guard case .function(let name) = request.toolChoice else {
            Issue.record("expected tool_choice .function")
            return
        }
        #expect(name == "f")
    }

    @Test("decodes a tool-result message")
    func decodeToolMessage() throws {
        let json = #"{"role":"tool","content":"42","tool_call_id":"call_abc"}"#
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))

        #expect(message.role == "tool")
        #expect(message.toolCallId == "call_abc")
        #expect(message.content?.text == "42")
    }

    @Test("decodes a null message content")
    func decodeNullContent() throws {
        let json = #"{"role":"assistant","content":null}"#
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(message.content?.text == nil)
    }

    @Test("encodes a chat completion response with snake_case keys")
    func encodeResponse() throws {
        let response = ChatCompletionResponse(
            id: "chatcmpl-1",
            created: 100,
            model: "qwen",
            choices: [
                .init(
                    index: 0,
                    message: .init(content: "hello", toolCalls: nil),
                    finishReason: "stop"
                )
            ],
            usage: Usage(promptTokens: 3, completionTokens: 5)
        )
        let string = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)

        #expect(string.contains(#""finish_reason":"stop""#))
        #expect(string.contains(#""prompt_tokens":3"#))
        #expect(string.contains(#""total_tokens":8"#))
        #expect(string.contains(#""object":"chat.completion""#))
    }

    @Test("encodes a streaming chunk as chat.completion.chunk")
    func encodeChunk() throws {
        let chunk = ChatCompletionChunk(
            id: "chatcmpl-1",
            created: 100,
            model: "qwen",
            choices: [
                .init(index: 0, delta: .init(role: "assistant", content: "hi"), finishReason: nil)
            ]
        )
        let string = String(decoding: try JSONEncoder().encode(chunk), as: UTF8.self)
        #expect(string.contains(#""object":"chat.completion.chunk""#))
        #expect(string.contains(#""content":"hi""#))
    }
}
