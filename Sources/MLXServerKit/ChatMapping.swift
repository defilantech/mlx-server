import Foundation
import MLXLMCommon

/// Pure conversions between OpenAI wire types and mlx-swift-lm types.
/// No I/O — this is the most heavily unit-tested part of the kit.
enum ChatMapping {
    static let defaultMaxTokens = 2048
    static let maxTokensCeiling = 32768

    /// Map OpenAI messages onto mlx-swift-lm `Chat.Message`s.
    ///
    /// `Chat.Message` carries only role + text content. Tool-call metadata on
    /// assistant messages and `tool_call_id` on tool results are not preserved
    /// here; multi-turn tool-call history fidelity is refined alongside the
    /// tool-calling step.
    static func toChatMessages(_ messages: [ChatMessage]) -> [Chat.Message] {
        messages.map { message in
            let role = Chat.Message.Role(rawValue: message.role) ?? .user
            return Chat.Message(role: role, content: message.content?.text ?? "")
        }
    }

    /// Convert OpenAI tool definitions into mlx-swift-lm `ToolSpec` dictionaries
    /// (the raw schema the model's chat template renders). Returns `nil` for an
    /// absent or empty tool set so the template advertises no tools.
    static func toToolSpecs(_ tools: [ToolDefinition]?) -> [ToolSpec]? {
        guard let tools, !tools.isEmpty else { return nil }
        return tools.map { tool in
            var function: [String: any Sendable] = ["name": tool.function.name]
            if let description = tool.function.description {
                function["description"] = description
            }
            if let parameters = tool.function.parameters {
                function["parameters"] = jsonValueToSendable(parameters)
            }
            return ["type": tool.type, "function": function]
        }
    }

    /// Map OpenAI sampling parameters onto `GenerateParameters`, applying
    /// defaults and clamping `max_tokens` to a sane ceiling.
    static func resolveGenerateParameters(_ request: ChatCompletionRequest) -> GenerateParameters {
        var parameters = GenerateParameters()
        if let temperature = request.temperature {
            parameters.temperature = Float(temperature)
        }
        if let topP = request.topP {
            parameters.topP = Float(topP)
        }
        let requested = request.maxTokens ?? defaultMaxTokens
        parameters.maxTokens = min(max(requested, 1), maxTokensCeiling)
        return parameters
    }

    /// Serialize mlx-swift-lm tool-call arguments into the JSON *string* that
    /// OpenAI's `tool_calls[].function.arguments` field expects.
    static func argumentsJSONString(_ arguments: [String: JSONValue]) -> String {
        let object = arguments.mapValues(jsonValueToFoundation)
        guard JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }

    /// Recursively project a `JSONValue` into `Sendable` Swift values suitable
    /// as `ToolSpec` payloads.
    static func jsonValueToSendable(_ value: JSONValue) -> any Sendable {
        switch value {
        case .null: return String?.none as any Sendable
        case .bool(let bool): return bool
        case .int(let int): return int
        case .double(let double): return double
        case .string(let string): return string
        case .array(let array): return array.map(jsonValueToSendable)
        case .object(let object): return object.mapValues(jsonValueToSendable)
        }
    }

    /// Recursively project a `JSONValue` into Foundation values for
    /// `JSONSerialization`.
    static func jsonValueToFoundation(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let bool): return bool
        case .int(let int): return int
        case .double(let double): return double
        case .string(let string): return string
        case .array(let array): return array.map(jsonValueToFoundation)
        case .object(let object): return object.mapValues(jsonValueToFoundation)
        }
    }
}
