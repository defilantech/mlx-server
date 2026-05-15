import Foundation
import MLXLMCommon

// OpenAI-compatible wire types for /v1/chat/completions and /v1/models.
// `JSONValue` (from MLXLMCommon) is reused as the arbitrary-JSON carrier for
// tool-call arguments and JSON-schema `parameters`.

// MARK: - Request

/// `POST /v1/chat/completions` request body.
public struct ChatCompletionRequest: Decodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var stream: Bool?
    public var tools: [ToolDefinition]?
    public var toolChoice: ToolChoice?
    public var n: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools, n
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
}

/// A single message in the OpenAI `messages` array.
public struct ChatMessage: Codable, Sendable {
    public var role: String
    public var content: MessageContent?
    public var name: String?
    public var toolCalls: [ToolCallObject]?
    public var toolCallId: String?

    public init(
        role: String,
        content: MessageContent? = nil,
        name: String? = nil,
        toolCalls: [ToolCallObject]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

/// OpenAI message `content`: a string, JSON null, or an array of content parts
/// (multimodal). Phase 1 flattens part arrays to their concatenated text.
public enum MessageContent: Codable, Sendable {
    case text(String)
    case null

    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let parts = try? container.decode([ContentPart].self) {
            self = .text(parts.compactMap(\.text).joined())
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// One element of a multimodal `content` array. Only `text` parts are used.
public struct ContentPart: Codable, Sendable {
    public var type: String?
    public var text: String?
}

/// An OpenAI tool definition (`tools[]` in the request).
public struct ToolDefinition: Codable, Sendable {
    public var type: String
    public var function: FunctionSchema

    public init(type: String = "function", function: FunctionSchema) {
        self.type = type
        self.function = function
    }
}

/// The `function` schema inside a ``ToolDefinition``.
public struct FunctionSchema: Codable, Sendable {
    public var name: String
    public var description: String?
    public var parameters: JSONValue?

    public init(name: String, description: String? = nil, parameters: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// OpenAI `tool_choice`: `"none"` / `"auto"` / `"required"` or a forced function.
public enum ToolChoice: Codable, Sendable {
    case none
    case auto
    case required
    case function(name: String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            switch string {
            case "none": self = .none
            case "required": self = .required
            default: self = .auto
            }
            return
        }
        struct Forced: Decodable {
            struct Function: Decodable { let name: String }
            let function: Function
        }
        let forced = try container.decode(Forced.self)
        self = .function(name: forced.function.name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encode("none")
        case .auto: try container.encode("auto")
        case .required: try container.encode("required")
        case .function(let name):
            struct Forced: Encodable {
                struct Function: Encodable { let name: String }
                let type = "function"
                let function: Function
            }
            try container.encode(Forced(function: .init(name: name)))
        }
    }
}

/// An OpenAI tool call (`tool_calls[]`) on a request or response message.
public struct ToolCallObject: Codable, Sendable {
    public var id: String
    public var type: String
    public var function: FunctionCall
    public var index: Int?

    public init(id: String, type: String = "function", function: FunctionCall, index: Int? = nil) {
        self.id = id
        self.type = type
        self.function = function
        self.index = index
    }
}

/// The `function` of a ``ToolCallObject``. `arguments` is a JSON *string*.
public struct FunctionCall: Codable, Sendable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Response

/// `chat.completion` response (non-streaming).
public struct ChatCompletionResponse: Encodable, Sendable {
    public var id: String
    public var object: String = "chat.completion"
    public var created: Int
    public var model: String
    public var choices: [Choice]
    public var usage: Usage

    public struct Choice: Encodable, Sendable {
        public var index: Int
        public var message: ResponseMessage
        public var finishReason: String

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    public struct ResponseMessage: Encodable, Sendable {
        public var role: String = "assistant"
        public var content: String?
        public var reasoningContent: String?
        public var toolCalls: [ToolCallObject]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }
}

/// Token accounting for a completion.
public struct Usage: Encodable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// `chat.completion.chunk` — one SSE event in a streamed completion.
public struct ChatCompletionChunk: Encodable, Sendable {
    public var id: String
    public var object: String = "chat.completion.chunk"
    public var created: Int
    public var model: String
    public var choices: [ChunkChoice]

    public struct ChunkChoice: Encodable, Sendable {
        public var index: Int
        public var delta: Delta
        public var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    public struct Delta: Encodable, Sendable {
        public var role: String?
        public var content: String?
        public var reasoningContent: String?
        public var toolCalls: [ToolCallObject]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }
}

/// `GET /v1/models` response.
public struct ModelListResponse: Encodable, Sendable {
    public var object: String = "list"
    public var data: [ModelObject]
}

/// One entry in a ``ModelListResponse``.
public struct ModelObject: Encodable, Sendable {
    public var id: String
    public var object: String = "model"
    public var created: Int
    public var ownedBy: String = "mlx-server"

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}
